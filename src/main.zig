const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");

const Vec2f = std.meta.Vector(2, f32);
const Pos = Vec2f;
const Control = enum { player };
const Component = struct {
    pos: Pos,
    control: Control,
};
const World = ecs.World(Component);

const KB = 1024;
var heap: [1 * KB]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap);
var world: World = World.init(fba.allocator());

export fn start() void {
    _ = world.create(.{ .pos = .{ 76, 76 }, .control = .player });
}

export fn update() void {
    w4.DRAW_COLORS.* = 2;
    w4.text("Hello from Zig!", .{ 10, 10 });

    if (w4.GAMEPAD1.button_1) {
        w4.DRAW_COLORS.* = 4;
    }

    world.process(1, &.{ .pos, .control }, controlProcess);
    world.process(1, &.{.pos}, drawProcess);

    w4.DRAW_COLORS.* = 2;
    // w4.blit(&smiley, .{ 76, 76 }, .{ 8, 8 }, .{ .bpp = .b1 });
    w4.text("Press X to blink", .{ 16, 90 });
}

fn drawProcess(_: f32, pos: *Pos) void {
    w4.DRAW_COLORS.* = 0x0030;
    w4.externs.blitSub(&assets.sprites, @floatToInt(i32, pos.*[0]), @floatToInt(i32, pos.*[1]), 8, 8, 0, 0, 128, assets.sprites_flags);
}

fn controlProcess(_: f32, pos: *Pos, control: *Control) void {
    _ = control;
    if (w4.GAMEPAD1.button_up) pos.*[1] -= 1;
    if (w4.GAMEPAD1.button_down) pos.*[1] += 1;
    if (w4.GAMEPAD1.button_left) pos.*[0] -= 1;
    if (w4.GAMEPAD1.button_right) pos.*[0] += 1;
    // w4.trace("here", .{});
}
