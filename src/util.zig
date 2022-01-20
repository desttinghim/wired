const std = @import("std");

pub const Vec2f = std.meta.Vector(2, f32);
pub const Vec2 = std.meta.Vector(2, i32);
pub const Cell = Vec2;

pub const Dir = struct {
    pub const up = Vec2{ 0, -1 };
    pub const down = Vec2{ 0, 1 };
    pub const left = Vec2{ -1, 0 };
    pub const right = Vec2{ 1, 0 };
};

pub const DirF = struct {
    pub const up = Vec2f{ 0, -1 };
    pub const down = Vec2f{ 0, 1 };
    pub const left = Vec2f{ -1, 0 };
    pub const right = Vec2f{ 1, 0 };
};

pub fn distance(a: Vec2, b: Vec2) i32 {
    var subbed = a - b;
    subbed[0] = std.math.absInt(subbed[0]) catch unreachable;
    subbed[1] = std.math.absInt(subbed[1]) catch unreachable;
    return @reduce(.Max, subbed);
}

pub fn distancef(a: Vec2f, b: Vec2f) f32 {
    var subbed = @fabs(a - b);
    return @reduce(.Max, subbed);
}

pub fn lengthf(vec: Vec2f) f32 {
    var squared = vec * vec;
    return @sqrt(@reduce(.Add, squared));
}

pub fn normalizef(vec: Vec2f) Vec2f {
    return vec / @splat(2, lengthf(vec));
}

pub fn world2cell(vec: Vec2f) Vec2 {
    return vec2fToVec2(vec / @splat(2, @as(f32, 8)));
}

pub fn vec2cell(vec: Vec2) Cell {
    return @divTrunc(vec, @splat(2, @as(i32, 8)));
}

pub fn vec2ToVec2f(vec2: Vec2) Vec2f {
    return Vec2f{ @intToFloat(f32, vec2[0]), @intToFloat(f32, vec2[1]) };
}

pub fn vec2fToVec2(vec2f: Vec2f) Vec2 {
    return Vec2{ @floatToInt(i32, vec2f[0]), @floatToInt(i32, vec2f[1]) };
}

pub const AABB = struct {
    pos: Vec2f,
    size: Vec2f,

    pub fn addv(this: @This(), vec2f: Vec2f) @This() {
        return @This(){ .pos = this.pos + vec2f, .size = this.size };
    }
};
