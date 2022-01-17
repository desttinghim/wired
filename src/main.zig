const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");
const input = @import("input.zig");

const Vec2 = std.meta.Vector(2, i32);
const Vec2f = std.meta.Vector(2, f32);
const AABB = struct {
    pos: Vec2f,
    size: Vec2f,

    pub fn addv(this: @This(), vec2f: Vec2f) @This() {
        return @This(){ .pos = this.pos + vec2f, .size = this.size };
    }
};
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
/// Stores last position, for velocity
const LastPos = Vec2f;
const Control = struct {
    controller: enum { player },
    state: enum { stand, walk, jump, fall },
    facing: enum { left, right } = .right,
};
const Sprite = struct { offset: Vec2f = Vec2f{ 0, 0 }, size: w4.Vec2, index: usize, flags: w4.BlitFlags };
const StaticAnim = Anim;
const ControlAnim = struct { anims: []AnimData, state: Anim };
const Kinematic = struct { col: AABB, onWall: bool = false, onFloor: bool = false, onCeil: bool = false };
const Wire = struct { end: Vec2f, grabbed: ?enum { begin, end } = null };
const Gravity = Vec2f;
const Component = struct {
    pos: Pos,
    lastpos: LastPos,
    control: Control,
    sprite: Sprite,
    staticAnim: StaticAnim,
    controlAnim: ControlAnim,
    kinematic: Kinematic,
    wire: Wire,
    gravity: Gravity,
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
        .pos = .{ 100, 80 },
        .lastpos = .{ 100, 80 },
        .control = .{ .controller = .player, .state = .stand },
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 0, .flags = .{ .bpp = .b1 } },
        .gravity = Vec2f{ 0, 0.25 },
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
        .kinematic = .{ .col = .{ .pos = .{ -3, -6 }, .size = .{ 5, 5 } } },
    }) catch unreachable;

    for (assets.wire) |wire| {
        const begin = Vec2f{ @intToFloat(f32, wire[0][0]), @intToFloat(f32, wire[0][1]) };
        const end = Vec2f{ @intToFloat(f32, wire[1][0]), @intToFloat(f32, wire[1][1]) };
        const w = Wire{ .end = end };
        _ = world.create(.{
            .pos = begin,
            .wire = w,
        }) catch {
            w4.trace("problem", .{});
            unreachable;
        };
    }
}

export fn update() void {
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });

    world.process(1, &.{ .pos, .lastpos }, velocityProcess);
    world.process(1, &.{ .pos, .gravity }, gravityProcess);
    world.process(1, &.{ .pos, .control, .gravity, .kinematic }, controlProcess);
    world.process(1, &.{ .pos, .lastpos, .kinematic }, kinematicProcess);
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
    input.update();
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

    w4.DRAW_COLORS.* = 0x0001;
    w4.line(begin, end);
    w4.DRAW_COLORS.* = 0x0031;

    const drawdistance = 16;
    const clickdistance = 3;

    if (wire.grabbed) |whichEnd| {
        switch (whichEnd) {
            .begin => pos.* = vec2tovec2f(w4.MOUSE.pos()),
            .end => wire.end = vec2tovec2f(w4.MOUSE.pos()),
        }
        if (w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = null;
    } else {
        if (distance(begin, w4.MOUSE.pos()) < drawdistance) {
            w4.oval(begin - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
            if (distance(begin, w4.MOUSE.pos()) < clickdistance and w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = .begin;
        }
        if (distance(end, w4.MOUSE.pos()) < drawdistance) {
            w4.oval(end - w4.Vec2{ 2, 2 }, w4.Vec2{ 5, 5 });
            if (distance(end, w4.MOUSE.pos()) < clickdistance and w4.MOUSE.buttons.left and !mouseLast) wire.grabbed = .end;
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

fn controlProcess(_: f32, pos: *Pos, control: *Control, gravity: *Gravity, kinematic: *Kinematic) void {
    var delta = Vec2f{ 0, 0 };
    if (kinematic.onFloor) {
        if (input.btnp(.one, .one)) delta[1] -= 23;
        if (input.btn(.one, .left)) delta[0] -= 1;
        if (input.btn(.one, .right)) delta[0] += 1;
        if (delta[0] != 0 or delta[1] != 0) {
            control.state = .walk;
            if (delta[0] > 0) control.facing = .right;
            if (delta[0] < 0) control.facing = .left;
        } else {
            control.state = .stand;
        }
    } else if (kinematic.onWall) {
        if (input.btn(.one, .left) and input.btnp(.one, .one)) delta = Vec2f{ -1, -23 };
        if (input.btn(.one, .right) and input.btnp(.one, .one)) delta = Vec2f{ 1, -23 };
        gravity.* = Vec2f{ 0, 0.01 };
    } else {
        if (w4.GAMEPAD1.button_left) delta[0] -= 1;
        if (w4.GAMEPAD1.button_right) delta[0] += 1;
        gravity.* = Vec2f{ 0, 0.25 };
    }
    var move = delta * @splat(2, @as(f32, 0.2));
    pos.* += move;
}

/// pos should be in tile coordinates, not world coordinates
fn get_tile(x: i32, y: i32) ?u8 {
    if (x < 0 or x > 19 or y < 0 or y > 19) return null;
    const i = x + y * 20;
    return assets.solid[@intCast(u32, i)];
}

/// rect should be absolutely positioned. Add pos to kinematic.collider
fn level_collide(rect: AABB) std.BoundedArray(AABB, 9) {
    const tileSize = 8;
    const top_left = rect.pos / @splat(2, @as(f32, tileSize));
    const bot_right = (rect.pos + rect.size) / @splat(2, @as(f32, tileSize));
    var collisions = std.BoundedArray(AABB, 9).init(0) catch unreachable;

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            var tile = get_tile(i, a);
            if (tile == null or tile.? != 1) {
                collisions.append(AABB{
                    .pos = Vec2f{
                        @intToFloat(f32, i * tileSize),
                        @intToFloat(f32, a * tileSize),
                    },
                    .size = Vec2f{ tileSize, tileSize },
                }) catch unreachable;
            }
        }
    }

    return collisions;
}

fn kinematicProcess(_: f32, pos: *Pos, lastpos: *LastPos, kinematic: *Kinematic) void {
    var next = lastpos.*;
    next[0] = pos.*[0];
    var hcol = level_collide(kinematic.col.addv(next));
    if (hcol.len > 0) {
        kinematic.onWall = true;
        next[0] = lastpos.*[0];
    } else {
        kinematic.onWall = false;
    }

    next[1] = pos.*[1];
    var vcol = level_collide(kinematic.col.addv(next));
    if (vcol.len > 0) {
        if (next[1] > lastpos.*[1]) kinematic.onFloor = true;
        if (next[1] < lastpos.*[1]) kinematic.onCeil = true;
        next[1] = lastpos.*[1];
    } else {
        kinematic.onFloor = false;
        kinematic.onCeil = false;
    }

    pos.* = next;
}

fn velocityProcess(_: f32, pos: *Pos, lastpos: *LastPos) void {
    var vel = pos.* - lastpos.*;

    vel *= @splat(2, @as(f32, 0.9));
    // vel += Vec2f{ 0, 0.25 };
    vel = @minimum(Vec2f{ 8, 8 }, @maximum(Vec2f{ -8, -8 }, vel));

    lastpos.* = pos.*;
    pos.* += vel;
}

fn gravityProcess(dt: f32, pos: *Pos, gravity: *Gravity) void {
    _ = dt;
    pos.* = pos.* + gravity.*;
}
