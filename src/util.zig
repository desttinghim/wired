const std = @import("std");

pub const Vec2f = std.meta.Vector(2, f32);
pub const Vec2 = std.meta.Vector(2, i32);
pub const Cell = Vec2;

pub fn world2cell(vec: Vec2f) Vec2 {
    return vec2fToVec2(vec / @splat(2, @as(f32, 8)));
}

fn vec2ToVec2f(vec2: Vec2) Vec2f {
    return Vec2f{ @intToFloat(f32, vec2[0]), @intToFloat(f32, vec2[1]) };
}

fn vec2fToVec2(vec2f: Vec2f) Vec2 {
    return Vec2{ @floatToInt(i32, vec2f[0]), @floatToInt(i32, vec2f[1]) };
}

pub const AABB = struct {
    pos: Vec2f,
    size: Vec2f,

    pub fn addv(this: @This(), vec2f: Vec2f) @This() {
        return @This(){ .pos = this.pos + vec2f, .size = this.size };
    }
};
