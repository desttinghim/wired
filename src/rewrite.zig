const extract = @import("extract.zig");
const world_data = @embedFile(@import("world_data").path);
const Circuit = @import("circuit.zig");
const input = @import("input.zig");
const Map = @import("map.zig");
const State = @import("main.zig").State;
const std = @import("std");
const w4 = @import("wasm4.zig");
const world = @import("world.zig");
const util = @import("util.zig");

const Vec2 = w4.Vec2;

var fba_buf: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
var alloc = fba.allocator();

var frame_fba_buf: [4096]u8 = undefined;
var frame_fba = std.heap.FixedBufferAllocator.init(&frame_fba_buf);
var frame_alloc = frame_fba.allocator();

var map_buf: [400]u8 = undefined;
var map: Map = undefined;

var circuit_lvl_buf: [400]u8 = undefined;
var circuit_buf: [400]u8 = undefined;
var circuit: Circuit = undefined;

var circuit_options: Circuit.Options = undefined;

var level_size = Vec2{ 20, 20 };

pub fn start() !void {
    circuit_options = .{
        .map = &circuit_buf,
        .levels = &circuit_lvl_buf,
        .map_size = level_size,
        .bridges = try alloc.alloc(Circuit.BridgeState, 5),
        .sources = try alloc.alloc(util.Cell, 5),
        .doors = try alloc.alloc(Circuit.DoorState, 5),
    };
    circuit = Circuit.init(circuit_options);

    map = Map.init(&map_buf, level_size);

    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = world_data,
    };
    const world_reader = stream.reader();

    var level = try world.Level.read(world_reader);
    var level_buf = try alloc.alloc(world.TileData, level.size);
    try level.readTiles(world_reader, level_buf);

    try extract.extractLevel(.{
        .alloc = frame_alloc,
        .level = level,
        .map = &map,
        .circuit = &circuit,
        .tileset = world.AutoTileset.initOffsetFull(113),
        .conduit = world.AutoTileset.initOffsetFull(97),
        .plug = world.AutoTileset.initOffsetCardinal(17),
        .switch_off = world.AutoTileset.initSwitches(&.{
            29, // South-North
            25, // South-West-North
            27, // South-East-North
        }, 2),
        .switch_on = world.AutoTileset.initSwitches(&.{
            30, // South-North
            26, // South-West-North
            28, // South-East-West
        }, 2),
    });
}

pub fn update(time: usize) !State {
    _ = time;
    // Reset the frame allocator
    frame_fba.reset();

    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(Vec2{ 0, 0 }, Vec2{ 160, 160 });
    w4.DRAW_COLORS.* = 0x0001;

    const camera = Vec2{ 0, 0 };

    map.draw(camera);
    circuit.draw(camera);

    return .Game;
}
