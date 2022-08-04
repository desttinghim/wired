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
    };
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
    _ = writer;

    // TODO: Convert LDtk data into wired format
    const ldtk = try LDtk.parse(allocator, source);
    defer ldtk.deinit(allocator);

    if (ldtk.levels.len > 0) {
        const level0 = ldtk.levels[0];
        if (level0.layerInstances) |layers| {
            var circuit: []const u8 = "null";
            var collision: []const u8 = "null";
            for (layers) |layer| {
                if (std.mem.eql(u8, layer.__identifier, "Entities")) {
                    std.debug.assert(layer.__type == .Entities);
                    for (layer.entityInstances) |entity| {
                        std.log.warn("{s}", .{entity.__identifier});
                    }
                }
                else if (std.mem.eql(u8, layer.__identifier, "Circuit")) {
                    std.debug.assert(layer.__type == .IntGrid);

                    var grid_str = try allocator.alloc(u8, @intCast(usize, layer.__cWid * layer.__cHei + layer.__cHei));
                    defer allocator.free(grid_str);
                    var i: usize = 0;
                    var o: usize = 0;
                    for (layer.intGridCsv) |int| {
                        grid_str[i + o] = std.fmt.digitToChar(@intCast(u8, int), .lower);
                        if (grid_str[i] == '0') grid_str[i] = ' ';
                        i += 1;
                        if (@mod(i, @intCast(usize, layer.__cWid)) == 0) {
                            grid_str[i + o] = '\n';
                            o += 1;
                        }
                    }

                    circuit = grid_str;
                }
                else if (std.mem.eql(u8, layer.__identifier, "Collision")) {
                    std.debug.assert(layer.__type == .IntGrid);

                    var grid_str = try allocator.alloc(u8, @intCast(usize, layer.__cWid * layer.__cHei + layer.__cHei));
                    var i: usize = 0;
                    var o: usize = 0;
                    for (layer.intGridCsv) |int| {
                        grid_str[i + o] = std.fmt.digitToChar(@intCast(u8, int), .lower);
                        if (grid_str[i] == '0') grid_str[i] = ' ';
                        i += 1;
                        if (@mod(i, @intCast(usize, layer.__cWid)) == 0) {
                            grid_str[i + o] = '\n';
                            o += 1;
                        }
                    }

                    collision = grid_str;
                } else {
                    std.log.warn("{s}: {}", .{ layer.__identifier, layer.__type });
                }
            }
            std.log.warn("Circuit IntGrid:\n{s}\nCollision IntGrid:\n{s}", .{ circuit, collision});
            allocator.free(circuit);
            allocator.free(collision);
        }
    }

    // Open output file and write data
    cwd.makePath(this.builder.getInstallPath(.lib, "")) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    try cwd.writeFile(output, data.items);
}
