const std = @import("std");
const assets = @import("assets");
const util = @import("util.zig");
const w4 = @import("wasm4.zig");
const world = @import("world.zig");

const Vec2 = util.Vec2;
const Vec2f = util.Vec2f;
const Cell = util.Cell;

const width = 20;
const height = 20;
const tile_width = 8;
const tile_height = 8;
pub const tile_size = Vec2{ 8, 8 };
const tile_sizef = Vec2f{ 8, 8 };
const tilemap_width = 16;
const tilemap_height = 16;
const tilemap_stride = 128;

tiles: []u8,
map_size: Vec2,

pub fn init(map: []u8, map_size: Vec2) @This() {
    var this = @This(){
        .tiles = map,
        .map_size = map_size,
    };
    return this;
}

pub fn clear(this: *@This()) void {
    std.mem.set(u8, this.tiles, 0);
}

pub fn reset(this: *@This(), initialState: []const u8) void {
    std.debug.assert(initialState.len == this.tiles.len);
    std.mem.copy(u8, this.tiles, initialState);
}

pub fn write_diff(this: *@This(), initialState: []const u8, buf: anytype) !u8 {
    var written: u8 = 0;
    for (initialState, 0..) |init_tile, i| {
        if (this.tiles[i] != init_tile) {
            const x = @as(u8, @intCast(i % @as(usize, @intCast(this.map_size[0]))));
            const y = @as(u8, @intCast(@divTrunc(i, @as(usize, @intCast(this.map_size[0])))));
            const temp = [3]u8{ x, y, this.tiles[i] };
            try buf.writeAll(&temp);
            written += 1;
        }
    }
    return written;
}

pub fn load_diff(this: *@This(), diff: []const u8) void {
    var i: usize = 0;
    while (i < diff.len) : (i += 3) {
        const x = diff[i];
        const y = diff[i + 1];
        const tile = diff[i + 2];
        this.set_cell(Cell{ x, y }, tile);
    }
}

pub fn set_cell(this: *@This(), cell: Cell, tile: u8) !void {
    const x = cell[0];
    const y = cell[1];
    if (x < 0 or x > this.map_size[0] or y < 0 or y > this.map_size[1]) return error.OutOfBounds;
    const i = x + y * this.map_size[0];
    this.tiles[@as(usize, @intCast(i))] = tile;
}

pub fn get_cell(this: @This(), cell: Cell) ?u8 {
    const x = cell[0];
    const y = cell[1];
    if (x < 0 or x >= this.map_size[0] or y < 0 or y >= this.map_size[1]) return null;
    const i = x + y * this.map_size[0];
    return this.tiles[@as(u32, @intCast(i))];
}

pub fn draw(this: @This(), offset: Vec2) void {
    w4.DRAW_COLORS.* = 0x0210;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const cell = Vec2{ @as(i32, @intCast(x)), @as(i32, @intCast(y)) } + offset;
            const pos = Vec2{ @as(i32, @intCast(x)), @as(i32, @intCast(y)) } * tile_size;
            const tile = this.get_cell(cell) orelse continue;
            if (tile == world.Tiles.Empty) continue;
            const t = Vec2{
                @as(i32, @intCast((tile % tilemap_width) * tile_width)),
                @as(i32, @intCast((tile / tilemap_width) * tile_width)),
            };
            w4.blitSub(
                &assets.tiles,
                pos,
                .{ tile_width, tile_height },
                t,
                tilemap_stride,
                .{ .bpp = .b2 },
            );
        }
    }
}

/// pos should be in tile coordinates, not world coordinates
fn getTile(this: @This(), x: i32, y: i32) ?u8 {
    if (x < 0 or x >= this.map_size[0] or y < 0 or y >= this.map_size[1]) return null;
    const i = x + y * this.map_size[0];
    return this.tiles[@as(u32, @intCast(i))];
}

pub const BodyInfo = struct {
    /// Rectangle
    rect: util.AABB,
    /// Last position
    last: Vec2f,
    /// Next position
    next: Vec2f,
    /// Pass through one way platforms
    is_passing: bool = false,
};

pub fn collide(this: @This(), body: BodyInfo) CollisionInfo {
    const top_left = body.rect.pos / tile_sizef;
    const bot_right = (body.rect.pos + body.rect.size) / tile_sizef;
    var collisions = CollisionInfo.init();

    var i: isize = @as(i32, @intFromFloat(top_left[0]));
    while (i <= @as(i32, @intFromFloat(bot_right[0]))) : (i += 1) {
        var a: isize = @as(i32, @intFromFloat(top_left[1]));
        while (a <= @as(i32, @intFromFloat(bot_right[1]))) : (a += 1) {
            const tile = this.getTile(i, a) orelse continue;
            const tilex = @as(f32, @floatFromInt(i * tile_width));
            const tiley = @as(f32, @floatFromInt(a * tile_height));
            const bottom = @as(i32, @intFromFloat(bot_right[1]));
            const foot = body.rect.pos[1] + body.rect.size[1];

            if (world.Tiles.is_oneway(tile)) {
                if (!body.is_passing and a == bottom and body.last[1] <= body.next[1] and foot < tiley + 2) {
                    collisions.append(util.AABB{
                        .pos = Vec2f{ tilex, tiley },
                        .size = tile_sizef,
                    });
                }
            } else if (world.Tiles.is_solid(tile)) {
                collisions.append(util.AABB{
                    .pos = Vec2f{ tilex, tiley },
                    .size = tile_sizef,
                });
            }
        }
    }

    return collisions;
}

pub const CollisionInfo = struct {
    len: usize,
    items: [9]util.AABB,

    pub fn init() CollisionInfo {
        return CollisionInfo{
            .len = 0,
            .items = undefined,
        };
    }

    pub fn append(col: *CollisionInfo, item: util.AABB) void {
        std.debug.assert(col.len < 9);
        col.items[col.len] = item;
        col.len += 1;
    }
};

// Debug functions

pub fn trace(this: @This()) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        const i = y * width;
        w4.trace("{any}", .{this.tiles[i .. i + width]});
    }
}

pub fn traceDraw(this: @This()) void {
    for (this.tiles, 0..) |tile, i| {
        const t = Vec2{
            @as(i32, @intCast((tile % tilemap_width) * tile_width)),
            @as(i32, @intCast((tile / tilemap_width) * tile_width)),
        };
        const pos = Vec2{
            @as(i32, @intCast((i % width) * tile_width)),
            @as(i32, @intCast((i / width) * tile_width)),
        };
        w4.trace("{}, {}, {}, {}, {}", .{
            pos,
            .{ tile_width, tile_height },
            t,
            tilemap_stride,
            .{ .bpp = .b2 },
        });
    }
}
