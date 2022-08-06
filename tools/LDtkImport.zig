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
        std.log.warn("[{}] x={} y={}; {} + {} = {}", .{ i, level.world_x, level.world_y, last_offset, last_size, offset });
    }

    // Create array to write data to
    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    const writer = data.writer();

    try world.write(level_headers.items, writer);

    // Write levels
    for (levels.items) |level| {
        std.log.warn("{} + {} + {} + {} + {} + {} + {}", .{
            @sizeOf(i8),
            @sizeOf(i8),
            @sizeOf(u16),
            @sizeOf(u16),
            @sizeOf(u16),
            level.tiles.?.len,
            level.entities.?.len * world.Entity.calculateSize(),
        });

        std.log.warn("x={} y={} w={} s={} ec={} t={} e={}", .{
            level.world_x,
            level.world_y,
            level.width,
            level.size,
            level.entity_count,
            level.tiles.?.len,
            level.entities.?.len,
        });
        try level.write(writer);
    }

    {
        var stream = std.io.FixedBufferStream([]const u8){
            .pos = 0,
            .buffer = data.items,
        };
        const world_reader = stream.reader();
        var lvls = try world.read(allocator, world_reader);
        var level_data_offset = try stream.getPos();
        std.log.warn("level_data_offset {}", .{level_data_offset});

        try stream.seekTo(level_data_offset + lvls[1].offset);
        std.log.warn("seek to 1 {}", .{try stream.getPos()});

        var level = try world.Level.read(world_reader);
        std.log.warn("level x={}, y={}", .{ level.world_x, level.world_y });
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
                .circuit = cir,
            } };
        }
    }

    return parsed_level;
}
