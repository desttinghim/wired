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

    // Create output array to write to
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    const writer = data.writer();

    var ldtk_parser = try LDtk.parse(allocator, source);
    defer ldtk_parser.deinit();

    const ldtk = ldtk_parser.root;

    if (ldtk.levels.len > 0) {
        const level0 = ldtk.levels[0];
        if (level0.layerInstances) |layers| {
            const world_x: u8 = @intCast(u8, @divExact(level0.worldX, (ldtk.worldGridWidth orelse 160)));
            const world_y: u8 = @intCast(u8, @divExact(level0.worldY, (ldtk.worldGridHeight orelse 160)));

            var entity_array = std.ArrayList(world.Entity).init(allocator);
            defer entity_array.deinit();

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

            var level = world.Level{
                .world_x = world_x,
                .world_y = world_y,
                .width = @intCast(u16, width),
                .size = @intCast(u16, size),
                .entity_count = @intCast(u16, entity_array.items.len),
                .tiles = null,
                .entities = entity_array.items,
            };
            level.tiles = try allocator.alloc(world.TileData, size);
            defer allocator.free(level.tiles.?);

            const tiles = level.tiles.?;

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
                        .circuit = cir,
                    } };
                }
            }

            // Save the level!
            try level.write(writer);
        }
    }

    // Open output file and write data
    cwd.makePath(this.builder.getInstallPath(.lib, "")) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    try cwd.writeFile(output, data.items);

    this.world_data.path = output;
}
