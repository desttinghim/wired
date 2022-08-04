const extract = @import("extract.zig");
const world_data = @embedFile(@import("world_data").path);
const Circuit = @import("circuit.zig");
const input = @import("input.zig");
const Map = @import("map.zig");
const State = @import("main.zig").State;
const std = @import("std");
const w4 = @import("wasm4.zig");
const world = @import("world.zig");

const Vec2 = w4.Vec2;

var frame_fba_buf: [4096]u8 = undefined;
var frame_fba = std.heap.FixedBufferAllocator.init(&frame_fba_buf);
var frame_alloc = frame_fba.allocator();

var map_buf: [400]u8 = undefined;
var map: Map = undefined;

var circuit_lvl_buf: [400]u8 = undefined;
var circuit_buf: [400]u8 = undefined;
var circuit: Circuit = undefined;

var level_size = Vec2{ 20, 20 };

pub fn start() !void {
    circuit = try Circuit.init(&circuit_buf, &circuit_lvl_buf, level_size);
    map = Map.init(&map_buf, level_size);

    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = world_data,
    };
    const world_reader = stream.reader();

    const header = try world.LevelHeader.read(world_reader);
    var tile_buf: [4096]world.TileStore = undefined;
    try header.readTiles(world_reader, &tile_buf);

    const level = world.Level.init(header, &tile_buf);

    try extract.extractLevel(.{
        .alloc = frame_alloc,
        .level = level,
        .map = &map,
        .circuit = &circuit,
        .tileset = world.AutoTileset{ .lookup = .{
            35, // Island
            51, // North
            52, // West
            55, // West-North
            50, // East
            53, // East-North
            19, // East-West
            54, // East-West-North
            49, // South
            20, // South-North
            23, // South-West
            39, // South-West-North
            21, // South-East
            37, // South-East-North
            22, // South-East-West
            0, // South-East-West-North
        }},
        .conduit = world.AutoTileset{ .lookup = .{
            42, // Island
            58, // North
            59, // West
            41, // West-North
            57, // East
            40, // East-North
            26, // East-West
            73, // East-West-North
            56, // South
            27, // South-North
            25, // South-West
            74, // South-West-North
            24, // South-East
            75, // South-East-North
            72, // South-East-West
            43, // South-East-West-North
        } },
        .plug = world.AutoTileset{ .lookup = .{
            02, // Island
            45, // North
            46, // West
            02, // West-North
            47, // East
            02, // East-North
            02, // East-West
            02, // East-West-North
            44, // South
            02, // South-North
            02, // South-West
            02, // South-West-North
            02, // South-East
            02, // South-East-North
            02, // South-East-West
            02, // South-East-West-North
        } },
        .switch_off = world.AutoTileset{ .lookup = .{
            02, // Island
            02, // North
            02, // West
            02, // West-North
            02, // East
            02, // East-North
            02, // East-West
            02, // East-West-North
            02, // South
            32, // South-North
            02, // South-West
            29, // South-West-North
            02, // South-East
            31, // South-East-North
            02, // South-East-West
            02, // South-East-West-North
        } },
        .switch_on = world.AutoTileset{ .lookup = .{
            02, // Island
            02, // North
            02, // West
            02, // West-North
            02, // East
            02, // East-North
            02, // East-West
            02, // East-West-North
            02, // South
            48, // South-North
            02, // South-West
            28, // South-West-North
            02, // South-East
            02, // South-East-North
            30, // South-East-West
            02, // South-East-West-North
        } },
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
