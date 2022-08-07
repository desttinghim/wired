//! Uses zig-ldtk to convert a ldtk file into a binary format for wired
const std = @import("std");
const LDtk = @import("../deps/zig-ldtk/src/LDtk.zig");
const world = @import("../src/world.zig");

const KB = 1024;
const MB = 1024 * KB;

const LDtkImport = @This();

step: std.build.Step,
builder: *std.build.Builder,
source_path: std.build.FileSource,
output_name: []const u8,
world_data: std.build.GeneratedFile,

pub fn create(b: *std.build.Builder, opt: struct {
    source_path: std.build.FileSource,
    output_name: []const u8,
}) *@This() {
    var result = b.allocator.create(LDtkImport) catch @panic("memory");
    result.* = LDtkImport{
        .step = std.build.Step.init(.custom, "convert and embed a ldtk map file", b.allocator, make),
        .builder = b,
        .source_path = opt.source_path,
        .output_name = opt.output_name,
        .world_data = undefined,
    };
    result.*.world_data = std.build.GeneratedFile{ .step = &result.*.step };
    return result;
}

fn make(step: *std.build.Step) !void {
    const this = @fieldParentPtr(LDtkImport, "step", step);

    const allocator = this.builder.allocator;
    const cwd = std.fs.cwd();

    // Get path to source and output
    const source_src = this.source_path.getPath(this.builder);
    const output = this.builder.getInstallPath(.lib, this.output_name);

    // Open ldtk file and read all of it into `source`
    const source_file = try cwd.openFile(source_src, .{});
    defer source_file.close();
    const source = try source_file.readToEndAlloc(allocator, 10 * MB);
    defer allocator.free(source);

    var ldtk_parser = try LDtk.parse(allocator, source);
    defer ldtk_parser.deinit();

    const ldtk = ldtk_parser.root;

    // Store levels
    var levels = std.ArrayList(world.Level).init(allocator);
    defer levels.deinit();

    for (ldtk.levels) |level| {
        var entity_array = std.ArrayList(world.Entity).init(allocator);
        defer entity_array.deinit();

        const parsed_level = try parseLevel(.{
            .allocator = allocator,
            .ldtk = ldtk,
            .level = level,
            .entity_array = &entity_array,
        });

        try levels.append(parsed_level);
    }
    defer for (levels.items) |level| {
        allocator.free(level.tiles.?);
        allocator.free(level.entities.?);
    };

    var circuit = try buildCircuit(allocator, levels.items);
    defer circuit.deinit();
    // TODO
    for (circuit.items) |node, i| {
        std.log.warn("[{}]: {s} {any}", .{ i, @tagName(node.kind), node.coord });
    }

    // Calculate the offset of each level and store it in the headers.
    // Offset is relative to the beginning of level.data
    var level_headers = std.ArrayList(world.LevelHeader).init(allocator);
    defer level_headers.deinit();

    for (levels.items) |level, i| {
        if (level_headers.items.len == 0) {
            try level_headers.append(.{
                .x = level.world_x,
                .y = level.world_y,
                .offset = 0,
            });
            continue;
        }
        const last_offset = level_headers.items[i - 1].offset;
        const last_size = try levels.items[i - 1].calculateSize();
        const offset = @intCast(u16, last_offset + last_size);
        try level_headers.append(.{
            .x = level.world_x,
            .y = level.world_y,
            .offset = offset,
        });
    }

    // Create array to write data to
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    const writer = data.writer();

    try world.write(level_headers.items, writer);

    // Write levels
    for (levels.items) |level| {
        try level.write(writer);
    }

    // Open output file and write data into it
    cwd.makePath(this.builder.getInstallPath(.lib, "")) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    try cwd.writeFile(output, data.items);

    this.world_data.path = output;
}

/// Returns parsed level. User owns level.tiles
fn parseLevel(opt: struct {
    allocator: std.mem.Allocator,
    ldtk: LDtk.Root,
    level: LDtk.Level,
    entity_array: *std.ArrayList(world.Entity),
}) !world.Level {
    const ldtk = opt.ldtk;
    const level = opt.level;
    const entity_array = opt.entity_array;
    const allocator = opt.allocator;

    const layers = level.layerInstances orelse return error.NoLayers;

    const world_x: i8 = @intCast(i8, @divExact(level.worldX, (ldtk.worldGridWidth orelse 160)));
    const world_y: i8 = @intCast(i8, @divExact(level.worldY, (ldtk.worldGridHeight orelse 160)));

    var circuit_layer: ?LDtk.LayerInstance = null;
    var collision_layer: ?LDtk.LayerInstance = null;

    for (layers) |layer| {
        if (std.mem.eql(u8, layer.__identifier, "Entities")) {
            // Entities
            std.debug.assert(layer.__type == .Entities);

            for (layer.entityInstances) |entity| {
                var kind_opt: ?world.EntityKind = null;
                if (std.mem.eql(u8, entity.__identifier, "Player")) {
                    kind_opt = .Player;
                } else if (std.mem.eql(u8, entity.__identifier, "Wire")) {
                    kind_opt = .WireNode;
                } else if (std.mem.eql(u8, entity.__identifier, "Coin")) {
                    kind_opt = .Coin;
                } else if (std.mem.eql(u8, entity.__identifier, "Door")) {
                    kind_opt = .Door;
                } else if (std.mem.eql(u8, entity.__identifier, "Trapdoor")) {
                    kind_opt = .Trapdoor;
                }

                // Parsing code for wire entities. They're a little more complex
                // than the rest
                if (kind_opt) |kind| {
                    if (kind != .WireNode) {
                        const world_entity = world.Entity{
                            .kind = kind,
                            .x = @intCast(i16, entity.__grid[0]),
                            .y = @intCast(i16, entity.__grid[1]),
                        };
                        try entity_array.append(world_entity);
                    } else {
                        const p1_x: i16 = @intCast(i16, entity.__grid[0]);
                        const p1_y: i16 = @intCast(i16, entity.__grid[1]);
                        var anchor1 = false;
                        var anchor2 = false;
                        var p2_x: i16 = p1_x;
                        var p2_y: i16 = p1_y;
                        for (entity.fieldInstances) |field| {
                            if (std.mem.eql(u8, field.__identifier, "Anchor")) {
                                const anchors = field.__value.Array.items;
                                anchor1 = anchors[0].Bool;
                                anchor2 = anchors[1].Bool;
                            } else if (std.mem.eql(u8, field.__identifier, "Point")) {
                                const end = field.__value.Array.items.len - 1;
                                const endpoint = field.__value.Array.items[end];
                                const x = endpoint.Object.get("cx").?;
                                const y = endpoint.Object.get("cy").?;
                                p2_x = @intCast(i16, x.Integer);
                                p2_y = @intCast(i16, y.Integer);
                            }
                        }
                        const wire_begin = world.Entity{
                            .kind = if (anchor1) .WireAnchor else .WireNode,
                            .x = p1_x,
                            .y = p1_y,
                        };
                        try entity_array.append(wire_begin);

                        const wire_end = world.Entity{
                            .kind = if (anchor2) .WireEndAnchor else .WireEndNode,
                            .x = p2_x,
                            .y = p2_y,
                        };
                        try entity_array.append(wire_end);
                    }
                }
            }
        } else if (std.mem.eql(u8, layer.__identifier, "Circuit")) {
            // Circuit
            std.debug.assert(layer.__type == .IntGrid);

            circuit_layer = layer;
        } else if (std.mem.eql(u8, layer.__identifier, "Collision")) {
            // Collision
            std.debug.assert(layer.__type == .IntGrid);

            collision_layer = layer;
        } else {
            // Unknown
            std.log.warn("{s}: {}", .{ layer.__identifier, layer.__type });
        }
    }

    if (circuit_layer == null) return error.MissingCircuitLayer;
    if (collision_layer == null) return error.MissingCollisionLayer;

    const circuit = circuit_layer.?;
    const collision = collision_layer.?;

    std.debug.assert(circuit.__cWid == collision.__cWid);
    std.debug.assert(circuit.__cHei == collision.__cHei);

    const width = @intCast(u16, circuit.__cWid);
    const size = @intCast(u16, width * circuit.__cHei);

    var parsed_level = world.Level{
        .world_x = world_x,
        .world_y = world_y,
        .width = @intCast(u16, width),
        .size = @intCast(u16, size),
        .entity_count = @intCast(u16, entity_array.items.len),
        .tiles = try allocator.alloc(world.TileData, size),
        .entities = try allocator.dupe(world.Entity, entity_array.items),
    };

    const tiles = parsed_level.tiles.?;

    // Add unchanged tile data
    for (collision.autoLayerTiles) |autotile| {
        const x = @divExact(autotile.px[0], collision.__gridSize);
        const y = @divExact(autotile.px[1], collision.__gridSize);
        const i = @intCast(usize, x + y * width);
        const sx = @divExact(autotile.src[0], collision.__gridSize);
        const sy = @divExact(autotile.src[1], collision.__gridSize);
        const t = sx + sy * 16;
        tiles[i] = world.TileData{ .tile = @intCast(u7, t) };
    }

    // Add circuit tiles
    for (circuit.intGridCsv) |cir64, i| {
        const cir = @intCast(u4, cir64);
        const col = collision.intGridCsv[i];
        if (col == 0 or col == 1) {
            tiles[i] = world.TileData{ .flags = .{
                .solid = col == 1,
                .circuit = @intToEnum(world.CircuitType, cir),
            } };
        }
    }

    return parsed_level;
}

pub fn buildCircuit(alloc: std.mem.Allocator, levels: []world.Level) !std.ArrayList(world.CircuitNode) {
    const Coordinate = [2]i16;
    const SearchItem = struct {
        coord: Coordinate,
        last_node: u16,
    };
    const Queue = std.TailQueue(SearchItem);
    const Node = Queue.Node;

    var nodes = std.ArrayList(world.CircuitNode).init(alloc);

    var sources = Queue{};
    var plugs = Queue{};

    var level_hashmap = std.AutoHashMap(u16, world.Level).init(alloc);
    defer level_hashmap.deinit();

    for (levels) |level| {
        const id: u16 = @bitCast(u8, level.world_x) | @intCast(u16, @bitCast(u8, level.world_y)) << 8;
        // So we can quickly find levels
        try level_hashmap.put(id, level);

        // Use a global coordinate system for our algorithm
        const world_x = @intCast(i16, level.world_x) * 20;
        const world_y = @intCast(i16, level.world_y) * 20;
        for (level.tiles orelse continue) |tileData, i| {
            const x = world_x + @intCast(i16, @mod(i, level.width));
            const y = world_y + @intCast(i16, @divTrunc(i, level.width));
            const coordinate = try alloc.create(Node);
            coordinate.* = .{ .data = .{
                .last_node = @intCast(u16, nodes.items.len),
                .coord = .{ x, y },
            } };
            switch (tileData) {
                .tile => |_| {
                    // Do nothing
                },
                .flags => |flags| {
                    switch (flags.circuit) {
                        .Source => {
                            try nodes.append(.{ .kind = .Source, .coord = .{ x, y } });
                            sources.append(coordinate);
                        },
                        .Plug => {
                            // try nodes.append(.{ .kind = .{ .Plug = null } });
                            coordinate.data.last_node = 20000;
                            plugs.append(coordinate);
                        },
                        else => {
                            // Do nothing
                        },
                    }
                },
            }
        }
    }

    var visited = std.AutoHashMap(Coordinate, void).init(alloc);

    var bfs_queue = Queue{};

    var run: usize = 0;
    while (run < 2) : (run += 1) {
        if (run == 0) bfs_queue.concatByMoving(&sources);
        if (run == 1) bfs_queue.concatByMoving(&plugs);
        // bfs_queue.concatByMoving(&outlets);

        while (bfs_queue.popFirst()) |node| {
            // Make sure we clean up the node's memory
            defer alloc.destroy(node);
            const coord = node.data.coord;
            if (visited.contains(coord)) continue;
            try visited.put(coord, .{});
            // TODO remove magic numbers
            const LEVELSIZE = 20;
            const world_x = @intCast(i8, @divFloor(coord[0], LEVELSIZE));
            const world_y = @intCast(i8, @divFloor(coord[1], LEVELSIZE));
            const id: u16 = @bitCast(u8, world_x) | @intCast(u16, @bitCast(u8, world_y)) << 8;
            // const level_opt: ?world.Level = level_hashmap.get(.{ world_x, world_y });
            if (level_hashmap.getPtr(id) != null) {
                const level = level_hashmap.getPtr(id);
                const level_x = @intCast(i16, world_x) * LEVELSIZE;
                const level_y = @intCast(i16, world_y) * LEVELSIZE;
                const i = @intCast(usize, (coord[0] - level_x) + (coord[1] - level_y) * @intCast(i16, level.?.width));
                const last_node = node.data.last_node;
                var next_node = last_node;

                const tile = level.?.tiles.?[i];

                if (tile != .flags) continue;
                const flags = tile.flags;

                switch (flags.circuit) {
                    .Conduit => {
                        // Collects from two other nodes. Needs to store more info in coordinate queue
                        // TODO
                    },
                    .Plug,
                    .Source,
                    => {
                        // These have already been added, so just continue the
                        // search
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Plug = null },
                            .coord = coord,
                        });
                    },
                    .Outlet => {
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Outlet = last_node },
                            .coord = coord,
                        });
                    },
                    .Switch_Off => {
                        // TODO: Find last coordinate of search and determine flow
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Switch = .Off },
                            .coord = coord,
                        });
                    },
                    .Switch_On => {
                        // TODO: Find last coordinate of search and determine flow
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Switch = .Off },
                            .coord = coord,
                        });
                    },
                    .Join => {
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Join = last_node },
                            .coord = coord,
                        });
                    },
                    .And => {
                        // TODO: verify And gate is properly connected. A source node
                        // should never feed directly into an And gate output. Inputs
                        // should be to the left and right.
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .And = .{ last_node, last_node } },
                            .coord = coord,
                        });
                    },
                    .Xor => {
                        // TODO: verify Xor gate is properly connected
                        next_node = @intCast(u16, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Xor = .{ last_node, last_node } },
                            .coord = coord,
                        });
                    },
                    else => continue,
                }

                const right = try alloc.create(Node);
                const left = try alloc.create(Node);
                const down = try alloc.create(Node);
                const up = try alloc.create(Node);

                right.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = .{ coord[0] + 1, coord[1] },
                } };
                left.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = .{ coord[0] - 1, coord[1] },
                } };
                down.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = .{ coord[0], coord[1] + 1 },
                } };
                up.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = .{ coord[0], coord[1] - 1 },
                } };

                bfs_queue.append(right);
                bfs_queue.append(left);
                bfs_queue.append(down);
                bfs_queue.append(up);
            }
        }
    }

    return nodes;
}
