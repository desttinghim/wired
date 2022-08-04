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
    return Vec2{ @floatToInt(i32, @floor(vec2f[0])), @floatToInt(i32, @floor(vec2f[1])) };
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

pub fn Queue(comptime T: type) type {
    return struct {
        begin: usize,
        end: usize,
        data: []T,
        pub fn init(slice: []T) @This() {
            return @This(){
                .begin = 0,
                .end = 0,
                .data = slice,
            };
        }
        fn next(this: @This(), idx: usize) usize {
            return ((idx + 1) % this.data.len);
        }
        pub fn insert(this: *@This(), t: T) !void {
            const n = this.next(this.end);
            if (n == this.begin) return error.OutOfMemory;
            this.data[this.end] = t;
            this.end = n;
        }
        pub fn remove(this: *@This()) ?T {
            if (this.begin == this.end) return null;
            const datum = this.data[this.begin];
            this.begin = this.next(this.begin);
            return datum;
        }
    };
}

test "Queue" {
    var items: [3]usize = undefined;
    var q = Queue(usize).init(&items);
    try q.insert(1);
    try q.insert(2);
    try std.testing.expectError(error.OutOfMemory, q.insert(3));
    try std.testing.expectEqual(@as(?usize, 1), q.remove());
    try std.testing.expectEqual(@as(?usize, 2), q.remove());
    try std.testing.expectEqual(@as(?usize, null), q.remove());
}

pub fn Buffer(comptime T: type) type {
    return struct {
        len: usize,
        items: []T,

        pub fn init(slice: []T) @This() {
            return @This(){
                .len = 0,
                .items = slice,
            };
        }

        pub fn reset(buf: *@This()) void {
            buf.len = 0;
        }

        pub fn append(buf: *@This(), item: T) void {
            std.debug.assert(buf.len < buf.items.len);
            buf.items[buf.len] = item;
            buf.len += 1;
        }
    };
}
