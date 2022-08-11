//! Uses zig-ldtk to convert a ldtk file into a binary format for wired
const std = @import("std");
const LDtk = @import("../deps/zig-ldtk/src/LDtk.zig");
const world = @import("../src/world.zig");

const Coord = world.Coordinate;
const Dir = world.Direction;

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

    var entity_array = std.ArrayList(world.Entity).init(allocator);
    defer entity_array.deinit();

    var wires = std.ArrayList(world.Wire).init(allocator);
    defer wires.deinit();

    for (ldtk.levels) |level| {
        std.log.warn("Level: {}", .{levels.items.len});
        const parsed_level = try parseLevel(.{
            .allocator = allocator,
            .ldtk = ldtk,
            .level = level,
            .entity_array = &entity_array,
            .wires = &wires,
        });

        // for (parsed_level.tiles.?) |tile, i| {
        //     if (tile == .tile) {
        //         std.log.warn("{:0>2}: {}", .{ i, tile.tile });
        //     } else if (tile == .flags) {
        //         std.log.warn("{:0>2}: {s} {s}", .{ i, @tagName(tile.flags.solid), @tagName(tile.flags.circuit) });
        //     } else {
        //         std.log.warn("{:0>2}: {}", .{ i, tile });
        //     }
        // }

        try levels.append(parsed_level);
    }
    defer for (levels.items) |level| {
        allocator.free(level.tiles.?);
    };

    var circuit = try buildCircuit(allocator, levels.items);
    defer circuit.deinit();
    // TODO
    for (circuit.items) |node, i| {
        std.log.warn("{:0>2}: {}", .{ i, node });
    }

    for (wires.items) |node, i| {
        std.log.warn("Wire {:0>2}: {any}", .{ i, node });
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

    try world.write(
        writer,
        level_headers.items,
        entity_array.items,
        wires.items,
        circuit.items,
        levels.items,
    );

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
    wires: *std.ArrayList(world.Wire),
}) !world.Level {
    const ldtk = opt.ldtk;
    const level = opt.level;
    const entity_array = opt.entity_array;
    const allocator = opt.allocator;
    const wires = opt.wires;

    const layers = level.layerInstances orelse return error.NoLayers;

    const world_x: i8 = @intCast(i8, @divFloor(level.worldX, (ldtk.worldGridWidth orelse 160)));
    const world_y: i8 = @intCast(i8, @divFloor(level.worldY, (ldtk.worldGridHeight orelse 160)));

    var circuit_layer: ?LDtk.LayerInstance = null;
    var collision_layer: ?LDtk.LayerInstance = null;

    for (layers) |layer| {
        if (std.mem.eql(u8, layer.__identifier, "Entities")) {
            // Entities
            std.debug.assert(layer.__type == .Entities);

            for (layer.entityInstances) |entity| {
                var is_wire = false;
                var kind_opt: ?world.EntityKind = null;
                if (std.mem.eql(u8, entity.__identifier, "Player")) {
                    kind_opt = .Player;
                } else if (std.mem.eql(u8, entity.__identifier, "Wire")) {
                    is_wire = true;
                } else if (std.mem.eql(u8, entity.__identifier, "Coin")) {
                    kind_opt = .Coin;
                } else if (std.mem.eql(u8, entity.__identifier, "Door")) {
                    kind_opt = .Door;
                } else if (std.mem.eql(u8, entity.__identifier, "Trapdoor")) {
                    kind_opt = .Trapdoor;
                }

                const levelc = Coord.fromWorld(world_x, world_y);
                // Parsing code for wire entities. They're a little more complex
                // than the rest
                if (kind_opt) |kind| {
                    const entc = Coord.init(.{
                        @intCast(i16, entity.__grid[0]),
                        @intCast(i16, entity.__grid[1]),
                    });
                    const world_entity = world.Entity{ .kind = kind, .coord = levelc.addC(entc) };
                    try entity_array.append(world_entity);
                }
                if (is_wire) {
                    var anchor1 = false;
                    var anchor2 = false;
                    const p1_c = Coord.init(.{
                        @intCast(i16, entity.__grid[0]),
                        @intCast(i16, entity.__grid[1]),
                    });
                    std.log.warn("[parseLevel:wire] {}", .{ p1_c });
                    var points: []Coord = undefined;
                    for (entity.fieldInstances) |field| {
                        if (std.mem.eql(u8, field.__identifier, "Anchor")) {
                            const anchors = field.__value.Array.items;
                            anchor1 = anchors[0].Bool;
                            anchor2 = anchors[1].Bool;
                        } else if (std.mem.eql(u8, field.__identifier, "Point")) {
                            points = try allocator.alloc(Coord, field.__value.Array.items.len);
                            for (field.__value.Array.items) |point, i| {
                                const x = point.Object.get("cx").?;
                                const y = point.Object.get("cy").?;
                                std.log.warn("\t{} {}", .{ x.Integer, y.Integer });
                                points[i] = Coord.init(.{
                                    @intCast(i16, x.Integer),
                                    @intCast(i16, y.Integer),
                                });
                            }
                        }
                    }

                    if (anchor1) {
                        try wires.append(.{ .BeginPinned = p1_c.addC(levelc) });
                    } else {
                        try wires.append(.{ .Begin = p1_c.addC(levelc) });
                    }

                    std.log.warn("\tConverting to wire nodes", .{});
                    var last_point = p1_c;
                    for (points) |point, i| {
                        const offset = point.subC(last_point).toOffset();
                        std.log.warn("\toffset: {} {}", .{ offset[0], offset[1] });
                        last_point = point;
                        if (i == points.len - 1) {
                            if (anchor2) {
                                try wires.append(.{ .PointPinned = offset });
                                continue;
                            }
                        }
                        try wires.append(.{ .Point = offset });
                    }

                    try wires.append(.End);
                }
            }

            std.log.warn("Entities: {}", .{entity_array.items.len});
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

    // Entities go into global scope now
    var parsed_level = world.Level{
        .world_x = world_x,
        .world_y = world_y,
        .width = @intCast(u16, width),
        .size = @intCast(u16, size),
        .tiles = try allocator.alloc(world.TileData, size),
    };

    const tiles = parsed_level.tiles.?;

    for (tiles) |_, i| {
        tiles[i] = world.TileData{ .tile = 0 };
    }

    // Add unchanged tile data
    for (collision.autoLayerTiles) |autotile| {
        const x = @divExact(autotile.px[0], collision.__gridSize);
        const y = @divExact(autotile.px[1], collision.__gridSize);
        const i = @intCast(usize, x + y * width);
        const t = autotile.t;
        tiles[i] = world.TileData{ .tile = @intCast(u7, t) };
    }

    // Add circuit tiles
    for (circuit.intGridCsv) |cir64, i| {
        const cir = @intToEnum(world.CircuitType, @intCast(u5, cir64));
        const col = collision.intGridCsv[i];
        if (cir != .None and col == 2) return error.DebrisAndCircuitOverlapped;
        if (cir == .None) continue;
        const solid: world.SolidType = switch (col) {
            0 => .Empty,
            1 => .Solid,
            3 => .Oneway,
            else => continue,
        };
        tiles[i] = world.TileData{ .flags = .{
            .solid = solid,
            .circuit = cir,
        } };
    }

    return parsed_level;
}

pub fn buildCircuit(alloc: std.mem.Allocator, levels: []world.Level) !std.ArrayList(world.CircuitNode) {
    const SearchItem = struct {
        coord: Coord,
        last_coord: ?Coord = null,
        last_node: world.NodeID,

        fn next(current: @This(), current_node: world.NodeID, offset: [2]i16) @This() {
            return @This(){
                .coord = current.coord.add(offset),
                .last_coord = current.coord,
                .last_node = current_node,
            };
        }
    };
    const Queue = std.TailQueue(SearchItem);
    const Node = Queue.Node;

    var nodes = std.ArrayList(world.CircuitNode).init(alloc);

    var node_input_dir = std.ArrayList(Dir).init(alloc);
    defer node_input_dir.deinit();

    var source_node = std.ArrayList(world.NodeID).init(alloc);
    defer source_node.deinit();

    var sources = Queue{};
    var sockets = Queue{};

    for (levels) |level| {
        // Use a global coordinate system for our algorithm
        const global_x = @intCast(i16, level.world_x) * 20;
        const global_y = @intCast(i16, level.world_y) * 20;
        for (level.tiles orelse continue) |tileData, i| {
            const x = global_x + @intCast(i16, @mod(i, level.width));
            const y = global_y + @intCast(i16, @divTrunc(i, level.width));
            const search_item = try alloc.create(Node);
            search_item.* = .{ .data = .{
                .last_node = @intCast(world.NodeID, nodes.items.len),
                .coord = Coord.init(.{ x, y }),
            } };
            switch (tileData) {
                .tile => |_| {
                    // Do nothing
                },
                .flags => |flags| {
                    switch (flags.circuit) {
                        .Source => {
                            try nodes.append(.{ .kind = .Source, .coord = Coord.init(.{ x, y }) });
                            sources.append(search_item);
                        },
                        .Socket => {
                            search_item.data.last_node = std.math.maxInt(world.NodeID);
                            sockets.append(search_item);
                        },
                        else => {
                            // Do nothing
                        },
                    }
                },
            }
        }
    }

    var visited = std.AutoHashMap(Coord, void).init(alloc);
    defer visited.deinit();

    var bfs_queue = Queue{};

    var run: usize = 0;
    while (run < 2) : (run += 1) {
        if (run == 0) bfs_queue.concatByMoving(&sources);
        if (run == 1) bfs_queue.concatByMoving(&sockets);

        while (bfs_queue.popFirst()) |node| {
            // Make sure we clean up the node's memory
            defer alloc.destroy(node);
            const coord = node.data.coord;
            if (visited.contains(coord)) continue;
            try visited.put(coord, {});

            const worldc = coord.toWorld();
            // const level = getLevel(levels, worldc[0], worldc[1]);
            if (getLevel(levels, worldc[0], worldc[1])) |level| {
                const last_node = node.data.last_node;
                var next_node = last_node;

                const tile = level.getTile(coord) orelse continue;

                if (tile != .flags) continue;
                const flags = tile.flags;

                const dir = if (last_node != std.math.maxInt(world.NodeID))
                    getInputDirection(coord, nodes.items[last_node].coord)
                else
                    .South;

                switch (flags.circuit) {
                    .Conduit => {
                        // Collects from two other nodes. Intersections will need to be stored so when
                        // we find out we have to outputs, we can add the conduit and possible rewrite
                        // previous nodes to point to the conduit
                        // TODO
                    },
                    .Conduit_Horizontal => {},
                    .Conduit_Vertical => {},
                    .Source => {}, // Do nothing, but add everything around the source
                    .Socket => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Socket = null },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                    },
                    .Plug => {
                        // Plugs by their nature end a conduit path, so don't add
                        // surrounding tiles.
                        try nodes.append(.{
                            .kind = .{ .Plug = last_node },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                        continue;
                    },
                    .Outlet => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Outlet = last_node },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                    },
                    .Switch_Off => {
                        // Add switch
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Switch = .{
                                .source = last_node,
                                .state = 0,
                            } },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);

                        // Loop over sides, check if they are connected, and add a
                        // switch outlet if so
                        for (Dir.each) |side| {
                            const next_coord = coord.add(side.toOffset());
                            if (level.getCircuit(next_coord)) |circuit| {
                                if (circuit.canConnect(side.getOpposite()) and side != dir) {
                                    const outlet = @intCast(world.NodeID, nodes.items.len);
                                    const which = if (side == .North or side == .South) @as(u8, 1) else @as(u8, 0);
                                    try nodes.append(.{
                                        .kind = .{ .SwitchOutlet = .{
                                            .source = next_node,
                                            .which = which,
                                        } },
                                        .coord = next_coord,
                                    });
                                    try node_input_dir.append(side);
                                    try source_node.append(next_node);

                                    const outlet_search = try alloc.create(Node);
                                    outlet_search.* = .{ .data = node.data.next(outlet, side.toOffset()) };
                                    bfs_queue.append(outlet_search);
                                }
                            }
                        }
                    },
                    .Switch_On => {
                        // Add switch
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Switch = .{
                                .source = last_node,
                                .state = 1,
                            } },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                    },
                    .Join => {
                        const last_coord = node.data.last_coord.?;
                        if (last_coord.toLevelTopLeft().eq(coord.toLevelTopLeft())) {
                            std.log.warn("Join first side", .{});
                        } else {
                            next_node = @intCast(world.NodeID, nodes.items.len);
                            std.log.warn("Join second side", .{});
                            try nodes.append(.{
                                .kind = .{ .Join = last_node },
                                .coord = coord,
                            });
                            try node_input_dir.append(dir);
                            try source_node.append(last_node);
                        }
                    },
                    .And => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .And = .{ std.math.maxInt(world.NodeID), std.math.maxInt(world.NodeID) } },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                    },
                    .Xor => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Xor = .{ std.math.maxInt(world.NodeID), std.math.maxInt(world.NodeID) } },
                            .coord = coord,
                        });
                        try node_input_dir.append(dir);
                        try source_node.append(last_node);
                    },
                    .Diode => {
                        // TODO
                    },
                    .None => continue,
                }

                const right = try alloc.create(Node);
                const left = try alloc.create(Node);
                const down = try alloc.create(Node);
                const up = try alloc.create(Node);

                right.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = coord.add(.{ 1, 0 }),
                    .last_coord = coord,
                } };
                left.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = coord.add(.{ -1, 0 }),
                    .last_coord = coord,
                } };
                down.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = coord.add(.{ 0, 1 }),
                    .last_coord = coord,
                } };
                up.* = Node{ .data = .{
                    .last_node = next_node,
                    .coord = coord.add(.{ 0, -1 }),
                    .last_coord = coord,
                } };

                bfs_queue.append(right);
                bfs_queue.append(left);
                bfs_queue.append(down);
                bfs_queue.append(up);
            }
        }
    }

    var i: usize = 0;
    while (i < nodes.items.len) : (i += 1) {
        switch (nodes.items[i].kind) {
            .Source => {},
            .And => {
                const neighbors = try findNeighbors(alloc, levels, nodes.items, i);
                defer neighbors.deinit();

                std.log.warn("[{}]: Found {} neighbors", .{ i, neighbors.items.len });
                for (neighbors.items) |neighbor, a| {
                    std.log.warn("\tNeighbor {}: [{}] {}", .{ a, neighbor.id, neighbor.side });
                    if (neighbor.side == .West) nodes.items[i].kind.And[0] = neighbor.id;
                    if (neighbor.side == .East) nodes.items[i].kind.And[1] = neighbor.id;
                }
            },
            .Xor => {},
            .Conduit => {},
            .Plug => {},
            .Socket => {},
            .Switch => {},
            .SwitchOutlet => {},
            .Join => {},
            .Outlet => {},
        }
    }

    return nodes;
}

const Neighbor = struct {
    side: Dir,
    id: world.NodeID,
};
fn findNeighbors(
    alloc: std.mem.Allocator,
    levels: []world.Level,
    nodes: []world.CircuitNode,
    index: usize,
) !std.ArrayList(Neighbor) {
    var visited = std.AutoHashMap(Coord, void).init(alloc);
    defer visited.deinit();

    const SearchItem = struct {
        side: Dir,
        coord: Coord,

        fn init(side: Dir, coord: Coord) @This() {
            const init_item = @This(){ .side = side, .coord = coord };
            const item = switch (side) {
                .North => init_item.add(.{ 0, -1 }),
                .West => init_item.add(.{ -1, 0 }),
                .East => init_item.add(.{ 1, 0 }),
                .South => init_item.add(.{ 0, 1 }),
            };
            return item;
        }

        fn add(item: @This(), val: [2]i16) @This() {
            var new_item = @This(){
                .side = item.side,
                .coord = item.coord.add(val),
            };
            return new_item;
        }
    };

    const Queue = std.TailQueue(SearchItem);
    const Node = Queue.Node;
    var bfs_queue = Queue{};

    var neighbors = std.ArrayList(Neighbor).init(alloc);

    {
        const coord = nodes[index].coord;
        try visited.put(coord, {});

        const north = try alloc.create(Node);
        const west = try alloc.create(Node);
        const east = try alloc.create(Node);
        const south = try alloc.create(Node);

        north.* = Node{ .data = SearchItem.init(.South, coord) };
        west.* = Node{ .data = SearchItem.init(.West, coord) };
        east.* = Node{ .data = SearchItem.init(.East, coord) };
        south.* = Node{ .data = SearchItem.init(.North, coord) };

        bfs_queue.append(north);
        bfs_queue.append(west);
        bfs_queue.append(east);
        bfs_queue.append(south);
    }

    while (bfs_queue.popFirst()) |node| {
        // Make sure we clean up the node's memory
        defer alloc.destroy(node);
        const coord = node.data.coord;
        const item = node.data;
        if (visited.contains(coord)) continue;
        try visited.put(coord, {});

        const worldc = coord.toWorld();
        const level = getLevel(levels, worldc[0], worldc[1]) orelse continue;

        const tile = level.getTile(coord) orelse continue;
        _ = tile.getCircuit() orelse continue;

        if (getNode(nodes, coord)) |i| {
            try neighbors.append(.{
                .id = i,
                .side = item.side,
            });
            // Stop processing at circuit nodes
            continue;
        }

        const right = try alloc.create(Node);
        const left = try alloc.create(Node);
        const down = try alloc.create(Node);
        const up = try alloc.create(Node);

        right.* = Node{ .data = item.add(.{ 1, 0 }) };
        left.* = Node{ .data = item.add(.{ -1, 0 }) };
        down.* = Node{ .data = item.add(.{ 0, 1 }) };
        up.* = Node{ .data = item.add(.{ 0, -1 }) };

        bfs_queue.append(right);
        bfs_queue.append(left);
        bfs_queue.append(down);
        bfs_queue.append(up);
    }

    return neighbors;
}

fn getInputDirection(coord: Coord, last_coord: Coord) Dir {
    if (last_coord.eq(coord.add(.{ 0, -1 }))) {
        return .North;
    } else if (last_coord.eq(coord.add(.{ -1, 0 }))) {
        return .West;
    } else if (last_coord.eq(coord.add(.{ 1, 0 }))) {
        return .East;
    } else {
        return .South;
    }
}

fn getLevel(levels: []world.Level, x: i8, y: i8) ?world.Level {
    for (levels) |level| {
        if (level.world_x == x and level.world_y == y) return level;
    }
    return null;
}

fn getNode(nodes: []world.CircuitNode, coord: Coord) ?world.NodeID {
    for (nodes) |node, i| {
        if (node.coord.eq(coord)) return @intCast(world.NodeID, i);
    }
    return null;
}
