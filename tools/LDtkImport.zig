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

    const world_x: i8 = @intCast(i8, @divExact(level.worldX, (ldtk.worldGridWidth orelse 160)));
    const world_y: i8 = @intCast(i8, @divExact(level.worldY, (ldtk.worldGridHeight orelse 160)));

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

                const levelc = world.Coordinate.fromWorld(world_x, world_y);
                // Parsing code for wire entities. They're a little more complex
                // than the rest
                if (kind_opt) |kind| {
                    const entc = world.Coordinate.init(.{
                        @intCast(i16, entity.__grid[0]),
                        @intCast(i16, entity.__grid[1]),
                    });
                    const world_entity = world.Entity{ .kind = kind, .coord = levelc.addC(entc) };
                    try entity_array.append(world_entity);
                }
                if (is_wire) {
                    var anchor1 = false;
                    var anchor2 = false;
                    const p1_c = world.Coordinate.init(.{
                        @intCast(i16, entity.__grid[0]),
                        @intCast(i16, entity.__grid[1]),
                    });
                    var p2_c = world.Coordinate.init(.{
                        @intCast(i16, entity.__grid[0]),
                        @intCast(i16, entity.__grid[1]),
                    });
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
                            p2_c.val = .{
                                @intCast(i16, x.Integer),
                                @intCast(i16, y.Integer),
                            };
                        }
                    }

                    if (anchor1) {
                        try wires.append(.{ .BeginPinned = p1_c.addC(levelc) });
                    } else {
                        try wires.append(.{ .Begin = p1_c.addC(levelc) });
                    }

                    if (anchor2) {
                        try wires.append(.{ .PointPinned = p2_c.subC(p1_c).toOffset() });
                    } else {
                        try wires.append(.{ .Point = p2_c.subC(p1_c).toOffset() });
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
    const Coord = world.Coordinate;
    const SearchItem = struct {
        coord: Coord,
        last_coord: ?Coord = null,
        last_node: world.NodeID,
    };
    const Queue = std.TailQueue(SearchItem);
    const Node = Queue.Node;

    var nodes = std.ArrayList(world.CircuitNode).init(alloc);

    var sources = Queue{};
    var sockets = Queue{};

    var level_hashmap = std.AutoHashMap(u16, world.Level).init(alloc);
    defer level_hashmap.deinit();

    for (levels) |level| {
        const id: u16 = @bitCast(u8, level.world_x) | @intCast(u16, @bitCast(u8, level.world_y)) << 8;
        // So we can quickly find levels
        try level_hashmap.put(id, level);

        // Use a global coordinate system for our algorithm
        const global_x = @intCast(i16, level.world_x) * 20;
        const global_y = @intCast(i16, level.world_y) * 20;
        for (level.tiles orelse continue) |tileData, i| {
            const x = global_x + @intCast(i16, @mod(i, level.width));
            const y = global_y + @intCast(i16, @divTrunc(i, level.width));
            const coordinate = try alloc.create(Node);
            coordinate.* = .{ .data = .{
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
                            sources.append(coordinate);
                        },
                        .Socket => {
                            // try nodes.append(.{ .kind = .{ .Plug = null } });
                            coordinate.data.last_node = std.math.maxInt(world.NodeID);
                            sockets.append(coordinate);
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
    var multi_input = std.AutoHashMap(Coord, usize).init(alloc);
    defer multi_input.deinit();

    var bfs_queue = Queue{};

    var run: usize = 0;
    while (run < 2) : (run += 1) {
        if (run == 0) bfs_queue.concatByMoving(&sources);
        if (run == 1) bfs_queue.concatByMoving(&sockets);
        // bfs_queue.concatByMoving(&outlets);

        while (bfs_queue.popFirst()) |node| {
            // Make sure we clean up the node's memory
            defer alloc.destroy(node);
            const coord = node.data.coord;
            if (visited.contains(coord)) continue;
            try visited.put(coord, .{});
            // TODO remove magic numbers
            const worldc = coord.toWorld();
            const id: u16 = @bitCast(u8, worldc[0]) | @intCast(u16, @bitCast(u8, worldc[1])) << 8;
            // const level_opt: ?world.Level = level_hashmap.get(.{ world_x, world_y });
            if (level_hashmap.getPtr(id) != null) {
                const level = level_hashmap.getPtr(id);
                const last_node = node.data.last_node;
                var next_node = last_node;

                const tile = level.?.getTile(coord).?;

                if (tile != .flags) continue;
                const flags = tile.flags;

                switch (flags.circuit) {
                    .Source => {}, // Do nothing, but add everything around the source
                    .Conduit => {
                        // Collects from two other nodes. Intersections will need to be stored so when
                        // we find out we have to outputs, we can add the conduit and possible rewrite
                        // previous nodes to point to the conduit
                        // TODO
                    },
                    .Socket => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Socket = null },
                            .coord = coord,
                        });
                    },
                    .Plug => {
                        // Plugs by their nature end a conduit path, so don't add
                        // surrounding tiles.
                        try nodes.append(.{
                            .kind = .{ .Plug = last_node },
                            .coord = coord,
                        });
                        continue;
                    },
                    .Outlet => {
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Outlet = last_node },
                            .coord = coord,
                        });
                    },
                    .Switch_Off, .Switch_On => {
                        // Identify input side
                        const last_coord = node.data.last_coord.?;
                        const Dir = enum { North, West, East, South };
                        const input_dir: Dir = dir: {
                            if (last_coord.eq(coord.add(.{ 0, -1 }))) {
                                break :dir .North;
                            } else if (last_coord.eq(coord.add(.{ -1, 0 }))) {
                                break :dir .West;
                            } else if (last_coord.eq(coord.add(.{ 1, 0 }))) {
                                break :dir .East;
                            } else {
                                break :dir .South;
                            }
                        };
                        // Find outlets
                        const north_opt = level.?.getTile(coord.add(.{ 0, -1 })).?.getCircuit();
                        const west_opt = level.?.getTile(coord.add(.{ -1, 0 })).?.getCircuit();
                        const east_opt = level.?.getTile(coord.add(.{ 1, 0 })).?.getCircuit();
                        const south_opt = level.?.getTile(coord.add(.{ 0, 1 })).?.getCircuit();

                        const north = (north_opt orelse world.CircuitType.None) != .None;
                        const west = (west_opt orelse world.CircuitType.None) != .None;
                        const east = (east_opt orelse world.CircuitType.None) != .None;
                        const south = (south_opt orelse world.CircuitType.None) != .None;

                        // We don't have four way switches, don't allow them
                        std.debug.assert(west != true or east != true);
                        // We only have vertically oriented switches ATM
                        std.debug.assert(north == true and south == true);

                        // Determine initial state of switch
                        const state: u8 = state: {
                            // Vertical switch
                            if (!west and !east) {
                                if (flags.circuit == .Switch_Off) break :state 0;
                                break :state 1;
                            }
                            if (east and !west) {
                                if (flags.circuit == .Switch_Off) break :state 0;
                                break :state 1;
                            }
                            if (west and !east) {
                                if (flags.circuit == .Switch_Off) break :state 0;
                                break :state 1;
                            }
                            return error.ImpossibleSwitchState;
                        };
                        // Add switch
                        next_node = @intCast(world.NodeID, nodes.items.len);
                        try nodes.append(.{
                            .kind = .{ .Switch = .{
                                .source = last_node,
                                .state = state,
                            } },
                            .coord = coord,
                        });
                        // Add switch outlets
                        if (input_dir != .West and west) {
                            const out_node = @intCast(world.NodeID, nodes.items.len);
                            try nodes.append(.{
                                .kind = .{ .SwitchOutlet = .{
                                    .source = next_node,
                                    .which = 0,
                                } },
                                .coord = coord,
                            });
                            const right = try alloc.create(Node);
                            right.* = Node{ .data = .{
                                .last_node = out_node,
                                .coord = coord.add(.{ 1, 0 }),
                                .last_coord = coord,
                            } };
                            bfs_queue.append(right);
                        }

                        if (input_dir != .East and east) {
                            const out_node = @intCast(world.NodeID, nodes.items.len);
                            try nodes.append(.{
                                .kind = .{ .SwitchOutlet = .{
                                    .source = next_node,
                                    .which = 0,
                                } },
                                .coord = coord,
                            });
                            const left = try alloc.create(Node);
                            left.* = Node{ .data = .{
                                .last_node = out_node,
                                .coord = coord.add(.{ -1, 0 }),
                                .last_coord = coord,
                            } };
                            bfs_queue.append(left);
                        }

                        if (input_dir != .South and south) {
                            const out_node = @intCast(world.NodeID, nodes.items.len);
                            try nodes.append(.{
                                .kind = .{ .SwitchOutlet = .{
                                    .source = next_node,
                                    .which = 1,
                                } },
                                .coord = coord,
                            });
                            const down = try alloc.create(Node);
                            down.* = Node{ .data = .{
                                .last_node = out_node,
                                .coord = coord.add(.{ 0, 1 }),
                                .last_coord = coord,
                            } };
                            bfs_queue.append(down);
                        }

                        if (input_dir != .North and north) {
                            const out_node = @intCast(world.NodeID, nodes.items.len);
                            try nodes.append(.{
                                .kind = .{ .SwitchOutlet = .{
                                    .source = next_node,
                                    .which = 1,
                                } },
                                .coord = coord,
                            });
                            const up = try alloc.create(Node);
                            up.* = Node{ .data = .{
                                .last_node = out_node,
                                .coord = coord.add(.{ 0, -1 }),
                                .last_coord = coord,
                            } };
                            bfs_queue.append(up);
                        }
                        continue;
                    },
                    .Join => {
                        const last_coord = node.data.last_coord.?;
                        if (last_coord.toLevelTopLeft().eq(coord.toLevelTopLeft())) {
                            std.log.warn("Join first side", .{});
                        } else {
                            std.log.warn("Join second side", .{});
                            next_node = @intCast(world.NodeID, nodes.items.len);
                            try nodes.append(.{
                                .kind = .{ .Join = last_node },
                                .coord = coord,
                            });
                        }
                    },
                    .And => {
                        // TODO: verify And gate is properly connected. A source node
                        // should never feed directly into an And gate output. Inputs
                        // should be to the left and right.
                        const last_coord = node.data.last_coord.?;
                        const Side = enum { O, L, R };
                        const side: Side =
                            if (last_coord.val[0] == coord.val[0] - 1)
                            Side.L
                        else if (last_coord.val[0] == coord.val[0] + 1)
                            Side.R
                        else
                            Side.O;
                        // std.log.warn("{any}: {}", .{ coord, side });
                        if (multi_input.get(coord)) |a| {
                            switch (side) {
                                .L => {
                                    // std.log.warn("Filling left", .{});
                                    nodes.items[a].kind.And[0] = last_node;
                                },
                                .R => {
                                    // std.log.warn("Filling right", .{});
                                    nodes.items[a].kind.And[1] = last_node;
                                },
                                else => {}, // reverse connection
                            }
                        } else {
                            _ = visited.remove(coord);
                            if (side == .O) {
                                // TODO: reverse the path, since the search path
                                // may have come from a plug
                                return error.OutputToSource;
                            } else if (side == .L) {
                                next_node = @intCast(world.NodeID, nodes.items.len);
                                try nodes.append(.{
                                    .kind = .{ .And = .{ last_node, std.math.maxInt(world.NodeID) } },
                                    .coord = coord,
                                });
                            } else if (side == .R) {
                                next_node = @intCast(world.NodeID, nodes.items.len);
                                try nodes.append(.{
                                    .kind = .{ .And = .{ std.math.maxInt(world.NodeID), last_node } },
                                    .coord = coord,
                                });
                            }
                            try multi_input.put(coord, next_node);
                        }
                    },
                    .Xor => {
                        // TODO: verify Xor gate is properly connected
                        const last_coord = node.data.last_coord.?;
                        const Side = enum { O, L, R };
                        const side: Side =
                            if (last_coord.val[0] == coord.val[0] - 1)
                            Side.L
                        else if (last_coord.val[0] == coord.val[0] + 1)
                            Side.R
                        else
                            Side.O;
                        // std.log.warn("{any}: {}", .{ coord, side });
                        if (multi_input.get(coord)) |a| {
                            switch (side) {
                                .L => {
                                    // std.log.warn("Filling left", .{});
                                    nodes.items[a].kind.Xor[0] = last_node;
                                },
                                .R => {
                                    // std.log.warn("Filling right", .{});
                                    nodes.items[a].kind.Xor[1] = last_node;
                                },
                                else => {}, // reverse connection
                            }
                        } else {
                            _ = visited.remove(coord);
                            if (side == .O) {
                                // TODO: reverse the path, since the search path
                                // may have come from a plug
                                return error.OutputToSource;
                            } else if (side == .L) {
                                next_node = @intCast(world.NodeID, nodes.items.len);
                                try nodes.append(.{
                                    .kind = .{ .Xor = .{ last_node, std.math.maxInt(world.NodeID) } },
                                    .coord = coord,
                                });
                            } else if (side == .R) {
                                next_node = @intCast(world.NodeID, nodes.items.len);
                                try nodes.append(.{
                                    .kind = .{ .Xor = .{ std.math.maxInt(world.NodeID), last_node } },
                                    .coord = coord,
                                });
                            }
                            try multi_input.put(coord, next_node);
                        }
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
            // .Source => {
            // },
            .And => {},
            .Xor => {},
            .Conduit => {},
            .Plug => {},
            .Switch => {},
            .Join => {},
            .Outlet => {},
            else => {},
        }
    }

    return nodes;
}
