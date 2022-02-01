const std = @import("std");
const w4 = @import("wasm4.zig");
const util = @import("util.zig");
const Vec2 = util.Vec2;
const Vec2f = util.Vec2f;
const AABB = util.AABB;
const Anim = @import("anim.zig");

const approxEqAbs = std.math.approxEqAbs;
const AnimData = []const Anim.Ops;

// Components
pub const Pos = struct {
    pos: Vec2f,
    last: Vec2f,
    pinned: bool = false,
    pub fn init(pos: Vec2f) @This() {
        return @This(){ .pos = pos, .last = pos };
    }
    pub fn initVel(pos: Vec2f, vel: Vec2f) @This() {
        return @This(){ .pos = pos, .last = pos - vel };
    }
};
pub const Control = struct {
    controller: enum { player },
    state: enum { stand, walk, jump, fall, wallSlide },
    facing: enum { left, right, up, down } = .right,
    grabbing: ?struct { id: usize, which: usize } = null,
};
pub const Sprite = struct {
    offset: Vec2 = Vec2{ 0, 0 },
    size: w4.Vec2,
    index: usize,
    flags: w4.BlitFlags,
};
pub const StaticAnim = Anim;
pub const ControlAnim = struct { anims: []AnimData, state: Anim };
pub const Kinematic = struct {
    col: AABB,
    move: Vec2f = Vec2f{ 0, 0 },
    lastCol: Vec2f = Vec2f{ 0, 0 },

    pub fn inAir(this: @This()) bool {
        return approxEqAbs(f32, this.lastCol[1], 0, 0.01);
    }

    pub fn onFloor(this: @This()) bool {
        return approxEqAbs(f32, this.move[1], 0, 0.01) and this.lastCol[1] > 0;
    }

    pub fn isFalling(this: @This()) bool {
        return this.move[1] > 0 and approxEqAbs(f32, this.lastCol[1], 0, 0.01);
    }

    pub fn onWall(this: @This()) bool {
        return this.isFalling() and !approxEqAbs(f32, this.lastCol[0], 0, 0.01);
    }
};
pub const Physics = struct { gravity: Vec2f, friction: Vec2f };
