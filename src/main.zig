const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");

const Vec2f = std.meta.Vector(2, f32);
const AABB = struct { offset: Vec2f, size: Vec2f };
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
const Control = struct {
    controller: enum { player },
    state: enum { stand, walk, jump, fall },
    facing: enum { left, right } = .right,
};
const Sprite = struct { offset: Vec2f = Vec2f{ 0, 0 }, size: w4.Vec2, index: usize, flags: w4.BlitFlags };
const StaticAnim = Anim;
const ControlAnim = struct { anims: []AnimData, state: Anim };
const Kinematic = struct { col: AABB };
const Wire = struct { end: Vec2f, grabbed: ?enum { begin, end } = null };
const Component = struct {
    pos: Pos,
    control: Control,
    sprite: Sprite,
    staticAnim: StaticAnim,
    controlAnim: ControlAnim,
    kinematic: Kinematic,
    wire: Wire,
};
const World = ecs.World(Component);

// Global vars
const KB = 1024;
var heap: [8 * KB]u8 = undefined;
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
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 0, .flags = .{ .bpp = .b1 } },
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
        .kinematic = .{ .col = .{ .offset = .{ -2, -8 }, .size = .{ 4, 8 } } },
    }) catch unreachable;

    for (assets.wire) |wire| {
        w4.trace("begin {}, end {}", .{ wire[0], wire[1] });
        const begin = Vec2f{ @intToFloat(f32, wire[0][0]), @intToFloat(f32, wire[0][1]) };
        const end = Vec2f{ @intToFloat(f32, wire[1][0]), @intToFloat(f32, wire[1][1]) };
        w4.trace("{}, {}, begin {d:3.0}, end {d:3.0}", .{ wire[0], wire[1], begin, end });
        const w = Wire{ .end = end };
        const e = world.create(.{
            .pos = begin,
            .wire = w,
        }) catch {
            w4.trace("problem", .{});
            unreachable;
        };
        w4.trace("{}", .{world.components.items(.wire)[e]});
    }
}

export fn update() void {
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });

    world.process(1, &.{ .pos, .kinematic }, kinematicProcess);
    world.process(1, &.{ .pos, .control }, controlProcess);
    world.process(1, &.{ .sprite, .staticAnim }, staticAnimProcess);
    world.process(1, &.{ .sprite, .controlAnim, .control }, controlAnimProcess);
    world.process(1, &.{ .pos, .sprite }, drawProcess);

    w4.DRAW_COLORS.* = 0x0210;
    for (assets.solid) |tilePlus, i| {
        const tile = tilePlus - 1;
        const t = w4.Vec2{ @intCast(i32, (tile % 16) * 8), @intCast(i32, (tile / 16) * 8) };
        const pos = w4.Vec2{ @intCast(i32, (i % 20) * 8), @intCast(i32, (i / 20) * 8) };
        w4.blitSub(&assets.tiles, pos, .{ 8, 8 }, t, 128, .{ .bpp = .b2 });
        const conduitRaw = assets.conduit[i];
        if (conduitRaw != 0) {
            const conduittile = conduitRaw - 1;
            const tconduit = w4.Vec2{ @intCast(i32, (conduittile % 16) * 8), @intCast(i32, (conduittile / 16) * 8) };
            w4.blitSub(&assets.tiles, pos, .{ 8, 8 }, tconduit, 128, .{ .bpp = .b2 });
        }
    }

    world.process(1, &.{ .pos, .wire }, wireProcess);
    // for (assets.wire) |wire| {
    //     w4.DRAW_COLORS.* = 0x0001;
    //     w4.line(wire[0], wire[1]);
    //     w4.DRAW_COLORS.* = 0x0031;
    //     if (distance(wire[0], w4.MOUSE.pos()) < 8) w4.oval(wire[0] - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
    //     if (distance(wire[1], w4.MOUSE.pos()) < 8) w4.oval(wire[1] - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
    // }

    mouseLast = w4.MOUSE.buttons.left;
}

fn distance(a: w4.Vec2, b: w4.Vec2) i32 {
    var subbed = a - b;
    subbed[0] = std.math.absInt(subbed[0]) catch unreachable;
    subbed[1] = std.math.absInt(subbed[1]) catch unreachable;
    return @reduce(.Max, subbed);
}

var mouseLast = false;

fn wireProcess(_: f32, pos: *Pos, wire: *Wire) void {
    const begin = w4.Vec2{ @floatToInt(i32, pos.*[0]), @floatToInt(i32, pos.*[1]) };
    const end = w4.Vec2{ @floatToInt(i32, wire.end[0]), @floatToInt(i32, wire.end[1]) };
    // if (w4.MOUSE.buttons.left and !mouseLast) w4.trace("pos {}, wire {}, begin {}, end {}", .{ pos.*, wire.end, begin, end });
    w4.DRAW_COLORS.* = 0x0001;
    w4.line(begin, end);
    w4.DRAW_COLORS.* = 0x0031;

    if (wire.grabbed) |whichEnd| {
        switch (whichEnd) {
            .begin => pos.* = vec2tovec2f(w4.MOUSE.pos()),
            .end => wire.end = vec2tovec2f(w4.MOUSE.pos()),
        }
        if (w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = null;
    } else {
        if (distance(begin, w4.MOUSE.pos()) < 8) {
            w4.oval(begin - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
            if (w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = .begin;
        }
        if (distance(end, w4.MOUSE.pos()) < 8) {
            w4.oval(end - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
            if (w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = .end;
        }
    }
}

fn vec2tovec2f(vec2: w4.Vec2) Vec2f {
    return Vec2f{ @intToFloat(f32, vec2[0]), @intToFloat(f32, vec2[1]) };
}

fn vec2ftovec2(vec2f: Vec2f) w4.Vec2 {
    return w4.Vec2{ @floatToInt(i32, vec2f[0]), @intToFloat(i32, vec2f[1]) };
}

fn drawProcess(_: f32, pos: *Pos, sprite: *Sprite) void {
    w4.DRAW_COLORS.* = 0x0010;
    const fpos = pos.* + sprite.offset;
    const ipos = w4.Vec2{ @floatToInt(i32, fpos[0]), @floatToInt(i32, fpos[1]) };
    const t = w4.Vec2{ @intCast(i32, (sprite.index * 8) % 128), @intCast(i32, (sprite.index * 8) / 128) };
    w4.blitSub(&assets.sprites, ipos, sprite.size, t, 128, sprite.flags);
}

fn staticAnimProcess(_: f32, sprite: *Sprite, anim: *StaticAnim) void {
    anim.update(&sprite.index);
}

fn controlAnimProcess(_: f32, sprite: *Sprite, anim: *ControlAnim, control: *Control) void {
    const a: usize = if (control.state == .stand) 0 else 1;
    sprite.flags.flip_x = (control.facing == .left);
    anim.state.play(anim.anims[a]);
    anim.state.update(&sprite.index);
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

fn kinematicProcess(_: f32, pos: *Pos, kinematic: *Kinematic) void {
    pos.* += Vec2f{ 0, 1 };
    var topleft = pos.* + kinematic.col.offset;
    var bottomright = topleft + kinematic.col.size;
    if (bottomright[1] > 160) pos.*[1] = 160 - (kinematic.col.offset[1] + kinematic.col.size[1]);
}
