const std = @import("std");
const assets = @import("assets");
const util = @import("util.zig");
const w4 = @import("wasm4.zig");

const Vec2 = util.Vec2;
const Vec2f = util.Vec2f;
const Cell = util.Cell;

const MAXCELLS = 400;

const width = 20;
const height = 20;
const tile_width = 8;
const tile_height = 8;
pub const tile_size = Vec2{ 8, 8 };
const tile_sizef = Vec2f{ 8, 8 };
const tilemap_width = 16;
const tilemap_height = 16;
const tilemap_stride = 128;

alloc: std.mem.Allocator,
tiles: []u8,
offset: Cell,

pub fn init(alloc: std.mem.Allocator) !@This() {
    var tiles = try alloc.alloc(u8, MAXCELLS);
    var this = @This(){
        .alloc = alloc,
        .offset = Cell{ 0, 0 },
        .tiles = tiles,
    };
    return this;
}

pub fn load(this: *@This(), offset: Cell, map: []const u8, map_size: Vec2) void {
    this.offset = offset;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const i = x + y * 20;
            const a = (@intCast(usize, offset[0]) + x) + (@intCast(usize, offset[1]) + y) * @intCast(usize, map_size[0]);
            this.tiles[i] = map[a];
        }
    }
}

pub fn deinit(this: @This()) void {
    this.alloc.free(this.tiles);
}

pub fn draw(this: @This()) void {
    w4.DRAW_COLORS.* = 0x0210;
    for (this.tiles) |tilePlus, i| {
        if (tilePlus == 0) continue;
        const tile = tilePlus - 1;
        const t = Vec2{
            @intCast(i32, (tile % tilemap_width) * tile_width),
            @intCast(i32, (tile / tilemap_width) * tile_width),
        };
        const pos = Vec2{
            @intCast(i32, (i % width) * tile_width),
            @intCast(i32, (i / width) * tile_width),
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

/// pos should be in tile coordinates, not world coordinates
fn getTile(this: @This(), x: i32, y: i32) ?u8 {
    if (x < 0 or x > 19 or y < 0 or y > 19) return null;
    const i = x + y * 20;
    return this.tiles[@intCast(u32, i)];
}

pub fn collide(this: @This(), rect: util.AABB) std.BoundedArray(util.AABB, 9) {
    const top_left = rect.pos / tile_sizef;
    const bot_right = (rect.pos + rect.size) / tile_sizef;
    var collisions = std.BoundedArray(util.AABB, 9).init(0) catch unreachable;

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            if (this.isSolid(Cell{ i, a })) {
                collisions.append(util.AABB{
                    .pos = Vec2f{
                        @intToFloat(f32, i * tile_width),
                        @intToFloat(f32, a * tile_height),
                    },
                    .size = tile_sizef,
                }) catch unreachable;
            }
        }
    }

    return collisions;
}

pub fn isSolid(this: @This(), cell: Cell) bool {
    if (this.getTile(cell[0], cell[1])) |tile| {
        return tile != 0;
    }
    return true;
}

// Debug functions

pub fn trace(this: @This()) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        const i = y * width;
        w4.trace("{any}", .{this.tiles[i .. i + width]});
    }
}

pub fn traceDraw(this: @This()) void {
    for (this.tiles) |tilePlus, i| {
        const tile = tilePlus - 1;
        const t = Vec2{
            @intCast(i32, (tile % tilemap_width) * tile_width),
            @intCast(i32, (tile / tilemap_width) * tile_width),
        };
        const pos = Vec2{
            @intCast(i32, (i % width) * tile_width),
            @intCast(i32, (i / width) * tile_width),
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
