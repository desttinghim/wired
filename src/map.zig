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

tiles: []u8,
map_size: Vec2,

pub fn init(map: []u8, map_size: Vec2) @This() {
    var this = @This(){
        .tiles = map,
        .map_size = map_size,
    };
    return this;
}

pub fn set_cell(this: *@This(), cell: Cell, tile: u8) void {
    const x = cell[0];
    const y = cell[1];
    if (x < 0 or x > this.map_size[0] or y < 0 or y > this.map_size[1]) unreachable;
    const i = x + y * this.map_size[0];
    this.tiles[@intCast(usize, i)] = tile;
}

pub fn reset(this: *@This(), initialState: []const u8) void {
    std.debug.assert(initialState.len == this.tiles.len);
    std.mem.copy(u8, this.tiles, initialState);
}

pub fn get_cell(this: @This(), cell: Cell) ?u8 {
    const x = cell[0];
    const y = cell[1];
    if (x < 0 or x > this.map_size[0] or y < 0 or y > this.map_size[1]) return null;
    const i = x + y * this.map_size[0];
    return this.tiles[@intCast(u32, i)];
}

pub fn draw(this: @This(), offset: Vec2) void {
    w4.DRAW_COLORS.* = 0x0210;
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const cell = Vec2{ @intCast(i32, x), @intCast(i32, y) } + offset;
            const pos = Vec2{ @intCast(i32, x), @intCast(i32, y) } * tile_size;
            const tilePlus = this.get_cell(cell) orelse continue;
            if (tilePlus == 0) continue;
            const tile = tilePlus - 1;
            const t = Vec2{
                @intCast(i32, (tile % tilemap_width) * tile_width),
                @intCast(i32, (tile / tilemap_width) * tile_width),
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
    if (x < 0 or x > this.map_size[0] or y < 0 or y > this.map_size[1]) return null;
    const i = x + y * this.map_size[0];
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
    if (this.get_cell(cell)) |tile| {
        return tile != 0 and tile != 1;
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
