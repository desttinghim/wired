const std = @import("std");

const PropertyType = enum { @"bool", @"int" };
const Property = struct {
    name: []const u8 = &.{},
    @"type": PropertyType = .@"bool",
    value: union(PropertyType) { @"bool": bool, @"int": i64 },
};

const Point = struct {
    x: f64 = 0,
    y: f64 = 0,
};

const Object = struct {
    height: f64 = 0,
    id: u64 = 0,
    gid: u64 = 0,
    name: []const u8,
    point: bool = false,
    polyline: []Point = &.{},
    properties: []Property = &.{},
    rotation: f64 = 0,
    @"type": enum { wire, source, door, spawn, focus, coin },
    visible: bool = true,
    width: f64 = 0,
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
    editorsettings: struct { chunksize: struct { height: usize = 0, width: usize = 0 } = .{} } = .{},
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
var heap: [256 * KB]u8 = undefined;
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
        try outlist.appendSlice("const AABB = struct {pos: Vec2, size: Vec2};\n");
        try outlist.appendSlice("const Wire = struct { p1: Vec2, p2: Vec2, a1: bool, a2: bool, divisions: u8 };\n");

        var outbuffer: [16 * KB]u8 = undefined;
        for (map.layers) |layer| {
            switch (layer.@"type") {
                .tilelayer => {
                    var outcontent = try std.fmt.bufPrint(
                        &outbuffer,
                        "pub const {2s}_size: Vec2 = Vec2{{ {}, {} }};\npub const {s}: [{}]u8 = .{any};\n",
                        .{ layer.width, layer.height, layer.name, layer.data.len, layer.data },
                    );
                    _ = try outlist.appendSlice(outcontent);
                },
                .objectgroup => {
                    var wirelist = std.ArrayList(Object).init(alloc);
                    defer wirelist.deinit();

                    var doorlist = std.ArrayList(Object).init(alloc);
                    defer doorlist.deinit();

                    var coinlist = std.ArrayList(Object).init(alloc);
                    defer coinlist.deinit();

                    var sourcelist = std.ArrayList(Object).init(alloc);
                    defer sourcelist.deinit();

                    var focilist = std.ArrayList(Object).init(alloc);
                    defer focilist.deinit();

                    for (layer.objects) |obj| {
                        switch (obj.@"type") {
                            .wire => try wirelist.append(obj),
                            .door => try doorlist.append(obj),
                            .coin => try coinlist.append(obj),
                            .source => try sourcelist.append(obj),
                            .focus => try focilist.append(obj),
                            .spawn => try appendSpawn(&outlist, obj),
                        }
                    }

                    try appendWires(&outlist, wirelist);
                    try appendDoors(&outlist, doorlist);
                    try appendCoins(&outlist, coinlist);
                    try appendSources(&outlist, sourcelist);
                    try appendFoci(&outlist, focilist);
                },
            }
        }
        if (verbose) std.log.info("{s}", .{outlist.items});
        _ = try output.writeAll(outlist.items);
    }
}

pub fn length(vec: std.meta.Vector(2, i64)) i64 {
    var squared = vec * vec;
    return @intCast(i64, std.math.sqrt(@intCast(u64, @reduce(.Add, squared))));
}

pub fn appendWires(outlist: *std.ArrayList(u8), wirelist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const wire: [{}]Wire = [_]Wire{{", .{wirelist.items.len});
    try outlist.appendSlice(outcontent);

    for (wirelist.items) |obj| {
        var a1 = true;
        var a2 = true;
        var p1: std.meta.Vector(2, i64) = .{ 0, 0 };
        var p2: std.meta.Vector(2, i64) = .{ 0, 0 };
        var divisions: ?i64 = null;
        for (obj.properties) |p| {
            if (std.mem.eql(u8, p.name, "anchor1")) a1 = p.value.@"bool";
            if (std.mem.eql(u8, p.name, "anchor2")) a2 = p.value.@"bool";
            if (std.mem.eql(u8, p.name, "divisions")) divisions = p.value.@"int";
        }
        for (obj.polyline) |point, i| {
            switch (i) {
                0 => p1 = .{ @floatToInt(i64, obj.x + point.x), @floatToInt(i64, obj.y + point.y) },
                1 => p2 = .{ @floatToInt(i64, obj.x + point.x), @floatToInt(i64, obj.y + point.y) },
                else => return error.TooManyPoints,
            }
        }
        divisions = divisions orelse std.math.max(2, @divTrunc(length(p2 - p1), 6));

        var of = try std.fmt.bufPrint(
            &outbuffer,
            ".{{ .a1 = {}, .a2 = {}, .divisions = {}, .p1 = Vec2{{ {}, {} }}, .p2 = Vec2{{ {}, {} }} }}, ",
            .{ a1, a2, divisions, p1[0], p1[1], p2[0], p2[1] },
        );
        try outlist.appendSlice(of);
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

pub fn appendCoins(outlist: *std.ArrayList(u8), coinlist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const coins: [{}]Vec2 = [_]Vec2{{", .{coinlist.items.len});
    try outlist.appendSlice(outcontent);

    for (coinlist.items) |obj| {
        var sourcef = try std.fmt.bufPrint(&outbuffer, "Vec2{{ {}, {} }},", .{ @floatToInt(i32, @divTrunc(obj.x, 8)), @floatToInt(i32, @divTrunc(obj.y - 8, 8)) });
        try outlist.appendSlice(sourcef);
    }
    try outlist.appendSlice("};\n");
}

pub fn appendFoci(outlist: *std.ArrayList(u8), focilist: std.ArrayList(Object)) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(&outbuffer, "pub const focus: [{}]AABB = [_]AABB{{", .{focilist.items.len});
    try outlist.appendSlice(outcontent);

    for (focilist.items) |obj| {
        var sourcef = try std.fmt.bufPrint(
            &outbuffer,
            "AABB{{ .pos = Vec2{{ {}, {} }}, .size = Vec2{{ {}, {} }} }}",
            .{
                @floatToInt(i32, @divTrunc(obj.x, 8)),
                @floatToInt(i32, @divTrunc(obj.y, 8)),
                @floatToInt(i32, @divTrunc(obj.width, 8)),
                @floatToInt(i32, @divTrunc(obj.height, 8)),
            },
        );
        try outlist.appendSlice(sourcef);
    }
    try outlist.appendSlice("};\n");
}

pub fn appendSpawn(outlist: *std.ArrayList(u8), spawn: Object) !void {
    var outbuffer: [4 * KB]u8 = undefined;
    var outcontent = try std.fmt.bufPrint(
        &outbuffer,
        "pub const spawn: Vec2 = Vec2{{ {}, {} }};\n",
        .{
            @floatToInt(i32, @divTrunc(spawn.x, 8)),
            @floatToInt(i32, @divTrunc(spawn.y, 8)),
        },
    );
    try outlist.appendSlice(outcontent);
}
