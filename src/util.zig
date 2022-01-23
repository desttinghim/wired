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

pub fn distancef(a: Vec2f, b: Vec2f) f32 {
    var subbed = @fabs(a - b);
    return lengthf(subbed);
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

    pub fn overlaps(a: @This(), b: @This()) bool {
        return a.pos[0] < b.pos[0] + b.size[0] and
            a.pos[0] + a.size[0] > b.pos[0] and
            a.pos[1] < b.pos[1] + b.size[1] and
            a.pos[1] + a.size[1] > b.pos[1];
    }
};

pub fn Queue(comptime T: type, len: usize) type {
    return struct {
        data: std.BoundedArray(T, len),
        pub fn init() @This() {
            return @This(){
                .data = std.BoundedArray(T, len).init(0) catch unreachable,
            };
        }
        pub fn insert(this: *@This(), t: T) void {
            this.data.insert(0, t) catch unreachable;
        }
        pub fn remove(this: *@This()) ?Cell {
            return this.data.popOrNull();
        }
    };
}

pub fn Map(comptime K: type, comptime V: type, len: usize) type {
    return struct {
        keys: std.BoundedArray(K, len),
        values: std.BoundedArray(V, len),
        pub fn init() @This() {
            return @This(){
                .keys = std.BoundedArray(K, len).init(0) catch unreachable,
                .values = std.BoundedArray(V, len).init(0) catch unreachable,
            };
        }
        pub fn get(this: *@This(), key: K) ?*V {
            for (this.keys.slice()) |k, i| {
                if (@reduce(.And, key == k)) {
                    return &this.values.slice()[i];
                }
            }
            return null;
        }
        pub fn get_const(this: @This(), key: Cell) ?V {
            for (this.keys.constSlice()) |k, i| {
                if (@reduce(.And, key == k)) {
                    return this.values.constSlice()[i];
                }
            }
            return null;
        }
        pub fn set(this: *@This(), key: K, new: V) void {
            if (this.get(key)) |v| {
                v.* = new;
            } else {
                this.keys.append(key) catch unreachable;
                this.values.append(new) catch unreachable;
            }
        }
    };
}
