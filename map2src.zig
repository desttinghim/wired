const std = @import("std");

const PropertyType = enum { @"bool" };
const Property = struct {
    name: []const u8 = &.{},
    @"type": PropertyType = .@"bool",
    value: union(PropertyType) { @"bool": bool },
};

const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

const Object = struct {
    height: u64 = 0,
    id: u64 = 0,
    name: []const u8,
    point: bool = false,
    polyline: []Point = &.{},
    properties: []Property = &.{},
    rotation: f64 = 0,
    @"type": enum { wire, source, door },
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
        try outlist.appendSlice("const Wire = struct { p1: Vec2, p2: Vec2, a1: bool, a2: bool };\n");

        var outbuffer: [4 * KB]u8 = undefined;
        for (map.layers) |layer| {
            switch (layer.@"type") {
                .tilelayer => {
                    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const {s}: [{}]u8 = .{any};\n", .{ layer.name, layer.data.len, layer.data });
                    _ = try outlist.appendSlice(outcontent);
                },
                .objectgroup => {
                    var wirelist = std.ArrayList(Object).init(alloc);
                    defer wirelist.deinit();

                    var doorlist = std.ArrayList(Object).init(alloc);
                    defer doorlist.deinit();

                    var sourcelist = std.ArrayList(Object).init(alloc);
                    defer sourcelist.deinit();

                    for (layer.objects) |obj| {
                        switch (obj.@"type") {
                            .wire => try wirelist.append(obj),
                            .door => try doorlist.append(obj),
                            .source => try sourcelist.append(obj),
                        }
                    }

                    try appendWires(&outlist, wirelist);
                    try appendDoors(&outlist, doorlist);
                    try appendSources(&outlist, sourcelist);
                },
            }
        }
        if (verbose) std.log.info("{s}", .{outlist.items});
        _ = try output.writeAll(outlist.items);
    }
}

pub fn appendWires(outlist: *std.ArrayList(u8), wirelist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const wire: [{}]Wire = [_]Wire{{", .{wirelist.items.len});
    try outlist.appendSlice(outcontent);

    for (wirelist.items) |obj| {
        try outlist.appendSlice(".{");
        var a1 = true;
        var a2 = true;
        for (obj.properties) |p| {
            if (std.mem.eql(u8, p.name, "anchor1")) a1 = p.value.@"bool";
            if (std.mem.eql(u8, p.name, "anchor2")) a2 = p.value.@"bool";
        }
        var of = try std.fmt.bufPrint(&outbuffer, ".a1 = {}, .a2 = {},", .{ a1, a2 });
        try outlist.appendSlice(of);
        for (obj.polyline) |point, i| {
            var pointf = try std.fmt.bufPrint(&outbuffer, ".p{} = Vec2{{ {}, {} }},", .{ i + 1, @floatToInt(i32, obj.x + point.x), @floatToInt(i32, obj.y + point.y) });
            try outlist.appendSlice(pointf);
        }
        try outlist.appendSlice("}, ");
    }
    try outlist.appendSlice("};\n");
}

pub fn appendDoors(outlist: *std.ArrayList(u8), doorlist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const doors: [{}]Vec2 = [_]Vec2{{", .{doorlist.items.len});
    try outlist.appendSlice(outcontent);

    for (doorlist.items) |obj| {
        var doorf = try std.fmt.bufPrint(&outbuffer, "Vec2{{ {}, {} }},", .{ @floatToInt(i32, @divTrunc(obj.x, 8)), @floatToInt(i32, @divTrunc(obj.y, 8)) });
        try outlist.appendSlice(doorf);
    }
    try outlist.appendSlice("};\n");
}

pub fn appendSources(outlist: *std.ArrayList(u8), sourcelist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const sources: [{}]Vec2 = [_]Vec2{{", .{sourcelist.items.len});
    try outlist.appendSlice(outcontent);

    for (sourcelist.items) |obj| {
        var sourcef = try std.fmt.bufPrint(&outbuffer, "Vec2{{ {}, {} }},", .{ @floatToInt(i32, @divTrunc(obj.x, 8)), @floatToInt(i32, @divTrunc(obj.y, 8)) });
        try outlist.appendSlice(sourcef);
    }
    try outlist.appendSlice("};\n");
}
