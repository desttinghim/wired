const std = @import("std");
const util = @import("util.zig");
const assets = @import("assets");

const Vec2 = util.Vec2;
const Cell = util.Cell;

pub fn is_circuit(tile: u8) bool {
    return is_plug(tile) or is_conduit(tile) or is_switch(tile);
}

pub fn is_plug(tile: u8) bool {
    return (tile >= 43 and tile <= 46) or tile == 41;
}

pub fn is_conduit(tile: u8) bool {
    return (tile >= 23 and tile <= 26) or
        (tile >= 39 and tile <= 42) or
        (tile >= 55 and tile <= 58) or
        (tile >= 71 and tile <= 74);
}

pub fn is_switch(tile: u8) bool {
    return tile == 27 or tile == 28;
}

pub fn toggle_switch(tile: u8) u8 {
    return if (tile == 27) 28 else 27;
}

const Side = enum(u2) { up, right, down, left };
pub fn side(s: Side) u2 {
    return @enumToInt(s);
}

pub fn dir(s: Side) Cell {
    return switch (s) {
        .up => util.Dir.up,
        .down => util.Dir.down,
        .left => util.Dir.left,
        .right => util.Dir.right,
    };
}

const Current = [4]bool;
/// Returns sides that can conduct current
fn get_inputs(tile: u8) Current {
    return switch (tile) {
        // Corners
        23 => .{ false, true, true, false },
        24 => .{ false, false, true, true },
        39 => .{ true, true, false, false },
        40 => .{ true, false, false, true },
        // Straight
        25 => .{ false, true, false, true },
        26 => .{ true, false, true, false },
        // Cross
        41 => .{ false, false, false, false },
        42 => .{ true, true, true, true },
        // Ends
        55 => .{ false, false, true, false },
        56 => .{ false, true, false, false },
        57 => .{ true, false, false, false },
        58 => .{ false, false, false, true },
        // Tees
        71 => .{ false, true, true, true },
        72 => .{ true, true, false, true },
        73 => .{ true, false, true, true },
        74 => .{ true, true, true, false },
        // Plugs
        43 => .{ false, false, true, false },
        44 => .{ true, false, false, false },
        45 => .{ false, false, false, true },
        46 => .{ false, true, false, false },
        // Closed switch
        27 => .{ true, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Plugs = [4]bool;
/// Returns sides where wires may be plugged
fn get_plugs(tile: u8) Plugs {
    return switch (tile) {
        // Plugs
        43 => .{ true, false, false, false },
        44 => .{ false, false, true, false },
        45 => .{ false, true, false, false },
        46 => .{ false, false, false, true },
        // Cross
        41 => .{ true, true, true, true },
        else => .{ false, false, false, false },
    };
}

pub fn get_cell(this: @This(), cell: Cell) ?u8 {
    if (this.cell_map.getConstCell(cell)) |c| return c.tile;
    const c = cell;
    if (c[0] < 0 or c[0] > this.map_size[0] or c[1] > this.map_size[1] or c[1] < 0) return null;
    const i = @intCast(usize, @mod(c[0], this.map_size[0]) + (c[1] * this.map_size[1]));
    return if (this.map[i] != 0) this.map[i] - 1 else null;
}

pub fn set_cell(this: *@This(), cell: Cell, tile: u8) void {
    var cellstate = CellState{ .cell = cell, .tile = tile };
    this.cell_map.setCell(cellstate);
}

const MAXCELLS = 400;
const MAXBRIDGES = 10;
const MAXSOURCES = 10;

const CellState = struct { cell: Cell, enabled: bool = false, tile: u8 };
const CellMap = struct {
    data: std.BoundedArray(CellState, MAXCELLS),
    pub fn init() @This() {
        return @This(){ .data = std.BoundedArray(CellState, MAXCELLS).init(0) catch unreachable };
    }
    pub fn getCell(this: *@This(), cell: Cell) ?*CellState {
        for (this.data.slice()) |*cellstate| {
            if (@reduce(.And, cellstate.cell == cell)) {
                return cellstate;
            }
        }
        return null;
    }
    pub fn getConstCell(this: @This(), cell: Cell) ?CellState {
        for (this.data.constSlice()) |cellstate| {
            if (@reduce(.And, cellstate.cell == cell)) {
                return cellstate;
            }
        }
        return null;
    }
    pub fn setCell(this: *@This(), newcell: CellState) void {
        for (this.data.slice()) |*cellstate| {
            if (@reduce(.And, cellstate.cell == newcell.cell)) {
                cellstate.* = newcell;
                return;
            }
        }
        this.data.append(newcell) catch unreachable;
    }
    pub fn is_enabled(this: @This(), cell: Cell) bool {
        if (this.getConstCell(cell)) |cellstate| {
            return cellstate.enabled;
        }
        return false;
    }
};

const BridgeState = struct { cells: [2]Cell, id: usize, enabled: bool };

offset: Cell,
map: []const u8,
map_size: Vec2,
cell_map: CellMap,
bridges: std.BoundedArray(BridgeState, MAXBRIDGES),
sources: std.BoundedArray(Cell, MAXSOURCES),

pub fn init() @This() {
    var this = @This(){
        .offset = Cell{ 0, 0 },
        .map = &assets.conduit,
        .map_size = assets.conduit_size,
        .cell_map = CellMap.init(),
        .bridges = std.BoundedArray(BridgeState, MAXBRIDGES).init(0) catch unreachable,
        .sources = std.BoundedArray(Cell, MAXSOURCES).init(0) catch unreachable,
    };
    return this;
}

pub fn load(this: *@This(), offset: Cell, map: []const u8, map_size: Vec2) void {
    this.offset = offset;
    this.map = map;
    this.map_size = map_size;
    // var y: usize = 0;
    // while (y < 20) : (y += 1) {
    //     var x: usize = 0;
    //     while (x < 20) : (x += 1) {
    //         const i = x + y * 20;
    //         const a = (@intCast(usize, offset[0]) + x) + (@intCast(usize, offset[1]) + y) * @intCast(usize, map_size[0]);
    //         this.cells[i].tile = map[a];
    //     }
    // }
}

pub fn indexOf(this: @This(), cell: Cell) ?usize {
    if (cell[0] < 0 or cell[0] >= this.map_size[0] or cell[1] >= this.map_size[1] or cell[1] < 0) return null;
    return @intCast(usize, @mod(cell[0], this.map_size[0]) + (cell[1] * this.map_size[1]));
}

pub fn enable(this: *@This(), cell: Cell) void {
    if (this.cell_map.getCell(cell)) |c| {
        c.enabled = true;
        return;
    }
    const t = this.get_cell(cell) orelse unreachable;
    this.cell_map.setCell(.{ .cell = cell, .tile = t, .enabled = true });
}

pub fn bridge(this: *@This(), cells: [2]Cell, bridgeID: usize) void {
    if (this.indexOf(cells[0])) |_| {
        if (this.indexOf(cells[1])) |_| {
            this.bridges.append(.{ .cells = cells, .id = bridgeID, .enabled = false }) catch unreachable;
        }
    }
}

pub fn addSource(this: *@This(), cell: Cell) void {
    if (this.indexOf(cell)) |_| {
        this.sources.append(cell) catch unreachable;
    }
}

pub fn enabledBridges(this: @This()) std.BoundedArray(usize, MAXBRIDGES) {
    var items = std.BoundedArray(usize, MAXBRIDGES).init(0) catch unreachable;
    for (this.bridges.constSlice()) |b| {
        if (b.enabled) items.append(b.id) catch unreachable;
    }
    return items;
}

pub fn isEnabled(this: @This(), cell: Cell) bool {
    return this.cell_map.is_enabled(cell);
}

pub fn toggle(this: *@This(), c: Cell) void {
    const cell = c;
    if (this.get_cell(cell)) |tile| {
        if (is_switch(tile)) {
            const toggled = toggle_switch(tile);
            w4.tracef("%d, %d: %d to %d", cell[0], cell[1], tile, toggled);
            this.set_cell(cell, toggled);
        }
    }
}

pub fn clear(this: *@This()) void {
    for (this.cell_map.data.slice()) |*cell| {
        cell.enabled = false;
    }
    this.bridges.resize(0) catch unreachable;
}

pub fn reset(this: *@This()) void {
    this.clear();
    this.sources.resize(0) catch unreachable;
}

const w4 = @import("wasm4.zig");
// Returns number of cells filled
pub fn fill(this: *@This()) usize {
    const Queue = util.Queue(Cell, MAXCELLS);
    var count: usize = 0;
    var visited = std.BoundedArray(usize, MAXCELLS).init(0) catch unreachable;
    var q = Queue.init();
    for (this.sources.slice()) |source| {
        q.insert(source);
    }
    while (q.remove()) |cell| {
        const index = this.indexOf(cell) orelse continue;
        const hasVisited = std.mem.containsAtLeast(usize, visited.slice(), 1, &.{index});
        if (hasVisited) continue;
        const tile = this.get_cell(cell) orelse continue;
        visited.append(index) catch unreachable;
        this.enable(cell);
        count += 1;
        for (get_inputs(tile)) |conductor, i| {
            if (!conductor) continue;
            const s = @intToEnum(Side, i);
            const delta = dir(s);
            // TODO: check that cell can recieve from this side
            q.insert(cell + delta);
        }
        if (is_plug(tile)) {
            for (this.bridges.slice()) |*b| {
                if (@reduce(.And, b.cells[0] == cell)) {
                    q.insert(b.cells[1]);
                    b.enabled = true;
                } else if (@reduce(.And, b.cells[1] == cell)) {
                    q.insert(b.cells[0]);
                    b.enabled = true;
                }
            }
        }
    }
    return count;
}

const width = 20;
const height = 20;
const tile_size = Vec2{ 8, 8 };
const tilemap_width = 16;
const tilemap_height = 16;
const tilemap_stride = 128;

pub fn draw(this: @This()) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const cell = Vec2{ @intCast(i32, x), @intCast(i32, y) };
            const pos = cell * tile_size;
            const tile = this.get_cell(cell + this.offset) orelse continue;
            if (tile == 0) continue;
            if (this.isEnabled(cell + this.offset)) w4.DRAW_COLORS.* = 0x0210 else w4.DRAW_COLORS.* = 0x0310;
            const t = Vec2{
                @intCast(i32, (tile % tilemap_width) * tile_size[0]),
                @intCast(i32, (tile / tilemap_width) * tile_size[0]),
            };
            w4.blitSub(
                &assets.tiles,
                pos,
                tile_size,
                t,
                tilemap_stride,
                .{ .bpp = .b2 },
            );
        }
    }
}
