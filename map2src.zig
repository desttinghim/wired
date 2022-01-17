const std = @import("std");

const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

const Object = struct {
    height: u64 = 0,
    id: u64 = 0,
    name: []const u8,
    polyline: []Point,
    rotation: f64 = 0,
    @"type": []const u8 = "",
    visible: bool = true,
    width: u64 = 0,
    x: f64 = 0,
    y: f64 = 0,
};

const Layer = struct {
    data: []u64 = &.{},
    objects: []Object = &.{},
    height: u64 = 0,
    id: u64,
    name: []const u8,
    draworder: enum { topdown, none } = .none,
    opacity: u64,
    @"type": enum { tilelayer, objectgroup },
    visible: bool,
    width: u64 = 0,
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
var verbose = true;

pub fn main() anyerror!void {
    do() catch |e| switch (e) {
        error.NoOutputName => showHelp("No output filename supplied"),
        else => return e,
    };
}

pub fn showHelp(msg: []const u8) void {
    std.log.info("{s}\n map2src <output> input1...", .{msg});
}

pub fn do() !void {
    var argsIter = std.process.args();
    const cwd = std.fs.cwd();

    const progName = (try argsIter.next(alloc)) orelse "";
    defer alloc.free(progName);
    if (verbose) std.log.info("{s}", .{progName});

    const outputName = (try argsIter.next(alloc)) orelse return error.NoOutputName;
    defer alloc.free(outputName);
    var output = try cwd.createFile(outputName, .{});
    defer output.close();

    while (try argsIter.next(alloc)) |arg| {
        defer alloc.free(arg);
        if (verbose) std.log.info("{s}", .{arg});
        var filebuffer: [64 * KB]u8 = undefined;
        var filecontents = try cwd.readFile(arg, &filebuffer);

        @setEvalBranchQuota(10000);
        var tokenstream = std.json.TokenStream.init(filecontents);
        const options = std.json.ParseOptions{ .allocator = fba.allocator() };
        const map = try std.json.parse(MapType, &tokenstream, options);
        defer std.json.parseFree(MapType, map, options);

        var outlist = std.ArrayList(u8).init(alloc);
        defer outlist.deinit();

        try outlist.appendSlice("const std = @import(\"std\");\n");
        try outlist.appendSlice("const Vec2 = std.meta.Vector(2,i32);\n");

        var outbuffer: [4 * KB]u8 = undefined;
        for (map.layers) |layer| {
            switch (layer.@"type") {
                .tilelayer => {
                    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const {s}: [{}]u8 = .{any};\n", .{ layer.name, layer.data.len, layer.data });
                    _ = try outlist.appendSlice(outcontent);
                },
                .objectgroup => {
                    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const {s}: [{}][2]Vec2 = [_][2]Vec2{{", .{ layer.name, layer.objects.len });
                    try outlist.appendSlice(outcontent);

                    for (layer.objects) |obj| {
                        try outlist.appendSlice(".{");
                        for (obj.polyline) |point| {
                            var pointf = try std.fmt.bufPrint(&outbuffer, ".{{ {}, {} }},", .{ @floatToInt(i32, obj.x + point.x), @floatToInt(i32, obj.y + point.y) });
                            try outlist.appendSlice(pointf);
                        }
                        try outlist.appendSlice("}, ");
                    }
                    try outlist.appendSlice("};\n");
                },
            }
        }
        if (verbose) std.log.info("{s}", .{outlist.items});
        _ = try output.writeAll(outlist.items);
    }
}
