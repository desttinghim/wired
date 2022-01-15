const std = @import("std");

const Layer = struct {
    data: []u64,
    height: u64,
    id: u64,
    name: []const u8,
    opacity: u64,
    @"type": enum { tilelayer },
    visible: bool,
    width: u64,
    x: i64,
    y: i64,
};

const MapType = struct {
    compressionlevel: i64 = -1,
    height: u64 = 0,
    infinite: bool = false,
    layers: []Layer,
    nextlayerid: u64 = 0,
    nextobjectid: u64 = 0,
    orientation: enum { orthogonal } = .orthogonal,
    renderorder: enum { @"right-down" } = .@"right-down",
    tiledversion: []const u8 = "",
    tileheight: u64 = 0,
    tilesets: []struct { firstgid: u64, source: []const u8 },
    tilewidth: u64 = 0,
    @"type": enum { map } = .map,
    version: []const u8 = "",
    width: u64 = 0,
};

const KB = 1024;
var heap: [64 * KB]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap);
var alloc = fba.allocator();

pub fn main() anyerror!void {
    const cwd = std.fs.cwd();
    var output = try cwd.createFile("map.zig", .{});
    defer output.close();

    var argsIter = std.process.args();
    const progName = (try argsIter.next(alloc)) orelse "";
    defer alloc.free(progName);
    std.log.info("{s}", .{progName});

    while (try argsIter.next(alloc)) |arg| {
        defer alloc.free(arg);
        std.log.info("{s}", .{arg});
        var filebuffer: [64 * KB]u8 = undefined;
        var filecontents = try cwd.readFile(arg, &filebuffer);

        @setEvalBranchQuota(10000);
        var tokenstream = std.json.TokenStream.init(filecontents);
        const options = std.json.ParseOptions{ .allocator = fba.allocator() };
        const map = try std.json.parse(MapType, &tokenstream, options);
        defer std.json.parseFree(MapType, map, options);

        var outbuffer: [64 * KB]u8 = undefined;
        var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const map: [{}]u8 = {any};\n", .{ map.layers[0].data.len, map.layers[0].data });
        _ = try output.writeAll(outcontent);
    }
}
