const world_data = @import("world_data");
const Circuit = @import("map.zig");
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
var circuit_buf : [400]u8 = undefined;
var circuit: Circuit = undefined;

var level_size = Vec2{20, 20};

pub fn start() void {
    circuit = try Circuit.init(&circuit_buf, &circuit_lvl_buf, level_size);
    map = Map.init(&map_buf, level_size);

    const extract_opt = world.ExtractOptions{
        .map = &map,
        .circuit = &circuit,
    };

    const world_reader = std.io.FixedBufferStream([]const u8).reader();
    const level = world_reader.readStruct(world.Level);

    world.extractLevel(frame_alloc, level, extract_opt);
}

pub fn update() State {
    // Reset the frame allocator
    frame_fba.reset();

    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(Vec2{ 0, 0 }, Vec2{ 160, 160 });
    w4.DRAW_COLORS.* = 0x0001;

    const camera = Vec2{0, 0};

    map.draw(camera);
    circuit.draw(camera);

    return .Game;
}
