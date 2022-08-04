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

    // TODO: Convert LDtk data into wired format
    const ldtk = try LDtk.parse(allocator, source);
    defer ldtk.deinit(allocator);

    if (ldtk.levels.len > 0) {
        const level0 = ldtk.levels[0];
        if (level0.layerInstances) |layers| {
            const world_x: u8 = @intCast(u8, @divExact(level0.worldX, (ldtk.worldGridWidth orelse 160)));
            const world_y: u8 = @intCast(u8, @divExact(level0.worldY, (ldtk.worldGridHeight orelse 160)));

            var circuit_layer: ?LDtk.LayerInstance = null;
            var collision_layer: ?LDtk.LayerInstance = null;
            for (layers) |layer| {
                if (std.mem.eql(u8, layer.__identifier, "Entities")) {
                    std.debug.assert(layer.__type == .Entities);
                    for (layer.entityInstances) |entity| {
                        std.log.warn("{s}", .{entity.__identifier});
                    }
                } else if (std.mem.eql(u8, layer.__identifier, "Circuit")) {
                    std.debug.assert(layer.__type == .IntGrid);

                    circuit_layer = layer;
                } else if (std.mem.eql(u8, layer.__identifier, "Collision")) {
                    std.debug.assert(layer.__type == .IntGrid);

                    collision_layer = layer;
                } else {
                    std.log.warn("{s}: {}", .{ layer.__identifier, layer.__type });
                }
            }

            if (circuit_layer == null) return error.MissingCircuitLayer;
            if (collision_layer == null) return error.MissingCollisionLayer;

            std.log.warn("Layers found", .{});

            const circuit = circuit_layer.?;
            const collision = collision_layer.?;

            std.debug.assert(circuit.__cWid == collision.__cWid);
            std.debug.assert(circuit.__cHei == collision.__cHei);

            const width = @intCast(u16, circuit.__cWid);
            const size = @intCast(u16, width * circuit.__cHei);

            try (world.LevelHeader{
                .world_x = world_x,
                .world_y = world_y,
                .width = @intCast(u16, width),
                .size = @intCast(u16, size),
            }).write(writer);

            var tiles = try allocator.alloc(world.TileStore, size);
            defer allocator.free(tiles);

            for (collision.autoLayerTiles) |autotile| {
                const x = @divExact(autotile.px[0], collision.__gridSize);
                const y = @divExact(autotile.px[1], collision.__gridSize);
                const i = @intCast(usize, x + y * width);
                tiles[i] = world.TileStore{
                    .is_tile = true,
                    .data = .{ .tile = @intCast(u7, autotile.t) },
                };
            }

            for (circuit.intGridCsv) |cir64, i| {
                const cir = @intCast(u4, cir64);
                const col = collision.intGridCsv[i];
                tiles[i] = world.TileStore{
                    .is_tile = false,
                    .data = .{
                        .flags = .{
                            .solid = col == 1,
                            .circuit = cir,
                        },
                    },
                };
                try writer.writeByte(tiles[i].toByte());
            }
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
