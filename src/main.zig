const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");

const Vec2f = std.meta.Vector(2, f32);
const Anim = struct {
    time: usize = 0,
    currentOp: usize = 0,
    delayUntil: usize = 0,
    anim: []const Ops,
    stopped: bool = false,

    pub const Ops = union(enum) { Index: usize, Wait: usize, Stop };

    pub fn play(this: *@This(), anim: []const Ops) void {
        if (this.anim.ptr == anim.ptr) return;
        this.anim = anim;
        this.stopped = false;
        this.currentOp = 0;
    }

    pub fn update(this: *@This(), out: *usize) void {
        this.time += 1;
        while (!this.stopped and this.anim.len > 0 and this.time >= this.delayUntil) {
            switch (this.anim[this.currentOp]) {
                .Index => |index| out.* = index,
                .Wait => |wait| this.delayUntil = this.time + wait,
                .Stop => this.stopped = true,
            }
            this.currentOp = (this.currentOp + 1) % this.anim.len;
        }
    }

    pub fn simple(rate: usize, comptime arr: []const usize) [arr.len * 2]Ops {
        var anim: [arr.len * 2]Ops = undefined;
        inline for (arr) |item, i| {
            anim[i * 2] = Ops{ .Index = item };
            anim[i * 2 + 1] = Ops{ .Wait = rate };
        }
        return anim;
    }

    pub fn frame(comptime index: usize) [2]Ops {
        return [_]Ops{ .{ .Index = index }, .Stop };
    }
};

// Components
const Pos = Vec2f;
const Control = struct { controller: enum { player }, state: enum { stand, walk, jump, fall } };
const Sprite = usize;
const StaticAnim = Anim;
const ControlAnim = struct { anims: []AnimData, state: Anim };
const Component = struct {
    pos: Pos,
    control: Control,
    sprite: Sprite,
    staticAnim: StaticAnim,
    controlAnim: ControlAnim,
};
const World = ecs.World(Component);

// Global vars
const KB = 1024;
var heap: [1 * KB]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap);
var world: World = World.init(fba.allocator());

const anim_store = struct {
    const stand = Anim.frame(0);
    const walk = Anim.simple(4, &[_]usize{ 1, 2, 3, 4 });
    const jump = Anim.frame(5);
    const fall = Anim.frame(6);
};

const AnimData = []const Anim.Ops;

const playerAnim = pac: {
    var animArr = std.BoundedArray(AnimData, 100).init(0) catch unreachable;
    animArr.append(&anim_store.stand) catch unreachable;
    animArr.append(&anim_store.walk) catch unreachable;
    animArr.append(&anim_store.jump) catch unreachable;
    animArr.append(&anim_store.fall) catch unreachable;
    break :pac animArr.slice();
};

export fn start() void {
    _ = world.create(.{
        .pos = .{ 76, 76 },
        .control = .{ .controller = .player, .state = .stand },
        .sprite = 0,
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
    });
}

export fn update() void {
    world.process(1, &.{ .pos, .control }, controlProcess);
    world.process(1, &.{ .sprite, .staticAnim }, staticAnimProcess);
    world.process(1, &.{ .sprite, .controlAnim, .control }, controlAnimProcess);
    world.process(1, &.{ .pos, .sprite }, drawProcess);

    w4.DRAW_COLORS.* = 2;
    w4.text("Hello from Zig!", .{ 10, 10 });

    if (w4.GAMEPAD1.button_1) {
        w4.DRAW_COLORS.* = 4;
    }

    // w4.blit(&smiley, .{ 76, 76 }, .{ 8, 8 }, .{ .bpp = .b1 });
    w4.text("Press X to blink", .{ 16, 90 });
}

fn drawProcess(_: f32, pos: *Pos, sprite: *Sprite) void {
    w4.DRAW_COLORS.* = 0x0030;
    const tx = (sprite.* * 8) % 128;
    const ty = (sprite.* * 8) / 128;
    w4.externs.blitSub(&assets.sprites, @floatToInt(i32, pos.*[0]), @floatToInt(i32, pos.*[1]), 8, 8, tx, ty, 128, assets.sprites_flags);
}

fn staticAnimProcess(_: f32, sprite: *Sprite, anim: *StaticAnim) void {
    anim.update(sprite);
}

fn controlAnimProcess(_: f32, sprite: *Sprite, anim: *ControlAnim, control: *Control) void {
    const a: usize = if (control.state == .stand) 0 else 1;
    anim.state.play(anim.anims[a]);
    anim.state.update(sprite);
}

fn controlProcess(_: f32, pos: *Pos, control: *Control) void {
    var delta = Vec2f{ 0, 0 };
    if (w4.GAMEPAD1.button_up) delta[1] -= 1;
    if (w4.GAMEPAD1.button_down) delta[1] += 1;
    if (w4.GAMEPAD1.button_left) delta[0] -= 1;
    if (w4.GAMEPAD1.button_right) delta[0] += 1;
    if (delta[0] != 0 or delta[1] != 0) {
        control.state = .walk;
        pos.* += delta;
    } else {
        control.state = .stand;
    }
}
