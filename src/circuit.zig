const std = @import("std");

fn is_circuit(tile: u8) bool {
    return is_plug(tile) or is_conduit(tile) or is_switch(tile);
}

pub fn is_plug(tile: u8) bool {
    return (tile >= 149 and tile <= 153) or tile == 147;
}

fn is_conduit(tile: u8) bool {
    return (tile >= 128 and tile < 132) or
        (tile >= 144 and tile < 148) or
        (tile >= 160 and tile < 164) or
        (tile >= 176 and tile < 180);
}

pub fn is_switch(tile: u8) bool {
    return tile >= 134 and tile < 136;
}

fn toggle_switch(tile: u8) u8 {
    return if (tile == 134) 135 else 134;
}

const Side = enum(u2) { up, right, down, left };
fn side(s: Side) u2 {
    return @enumToInt(s);
}

const Current = [4]bool;
/// Returns sides that can conduct current
fn get_inputs(tile: u8) Current {
    return switch (tile) {
        // Corners
        128 => .{ false, true, true, false },
        129 => .{ false, false, true, true },
        144 => .{ true, false, false, true },
        145 => .{ true, true, false, false },
        // Straight
        130 => .{ false, true, false, true },
        131 => .{ true, false, true, false },
        // Cross
        146 => .{ false, false, false, false },
        147 => .{ true, true, true, true },
        // Ends
        160 => .{ false, false, true, false },
        161 => .{ false, true, false, false },
        162 => .{ true, false, false, false },
        163 => .{ false, false, false, true },
        // Tees
        176 => .{ false, true, true, true },
        177 => .{ true, true, false, true },
        178 => .{ true, false, true, true },
        179 => .{ true, true, true, false },
        // Plugs
        150 => .{ false, false, true, false },
        151 => .{ true, false, false, false },
        152 => .{ false, false, false, true },
        153 => .{ false, true, false, false },
        // Closed switch
        134 => .{ true, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Plugs = [4]bool;
/// Returns sides where wires may be plugged
fn get_plugs(tile: u8) Plugs {
    return switch (tile) {
        // Plugs
        150 => .{ true, false, false, false },
        151 => .{ false, false, true, false },
        152 => .{ false, true, false, false },
        153 => .{ false, false, false, true },
        // Cross
        146 => .{ true, true, true, true },
        else => .{ false, false, false, false },
    };
}

const Signals = [4]bool;
/// Returns sides where a signal may be sent
fn get_signals(tile: u8) Signals {
    return switch (tile) {
        // Ends
        160 => .{ true, true, false, true },
        161 => .{ true, false, true, true },
        162 => .{ false, true, true, true },
        163 => .{ true, true, true, false },
        // Switches
        134 => .{ true, false, true, false },
        135 => .{ true, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Vec2 = std.meta.Vector(2, i32);
const Cell = Vec2;
fn dir(s: Side) Cell {
    return switch (s) {
        .up => Vec2{ 0, -1 },
        .down => Vec2{ 0, 1 },
        .left => Vec2{ -1, 0 },
        .right => Vec2{ 1, 0 },
    };
}

pub fn get_cell(this: @This(), c: Cell) ?u8 {
    if (c[0] < 0 or c[0] > 19 or c[1] > 19 or c[1] < 0) return null;
    const i = @intCast(usize, @mod(c[0], 20) + (c[1] * 20));
    return if (this.cells[i].tile != 0) this.cells[i].tile - 1 else null;
}

pub fn set_cell(this: *@This(), c: Cell, tile: u8) void {
    if (c[0] < 0 or c[0] > 19 or c[1] > 19 or c[1] < 0) return;
    const i = @intCast(usize, @mod(c[0], 20) + (c[1] * 20));
    this.cells[i].tile = tile + 1;
}

fn index2cell(i: usize) Cell {
    return Vec2{ i % 20, @divTrunc(i, 20) };
}

fn cell2index(c: Cell) ?usize {
    if (c[0] < 0 or c[0] >= 20 or c[1] >= 20 or c[1] < 0) return null;
    return @intCast(usize, @mod(c[0], 20) + (c[1] * 20));
}

const CellState = struct { enabled: bool = false, tile: u8 };
const MAXCELLS = 400;
const CellMap = [MAXCELLS]CellState; // std.AutoHashMap(Cell, CellState);

offset: Cell,
cells: CellMap,
bridges: std.BoundedArray([2]Cell, 10),

pub fn init(offset: Cell, map: []const u8) @This() {
    var this = @This(){
        .offset = offset,
        .cells = undefined,
        .bridges = std.BoundedArray([2]Cell, 10).init(0) catch unreachable,
    };
    // TODO: copy only part of a map
    for (map) |tile, i| {
        this.cells[i].enabled = false;
        this.cells[i].tile = tile;
    }
    return this;
}

pub fn indexOf(this: @This(), cell: Cell) ?usize {
    return cell2index(cell - this.offset);
}

pub fn enable(this: *@This(), cell: Cell) void {
    if (this.indexOf(cell)) |c| {
        this.cells[c].enabled = true;
    }
}

pub fn bridge(this: *@This(), cells: [2]Cell) void {
    if (this.indexOf(cells[0])) |_| {
        if (this.indexOf(cells[1])) |_| {
            this.bridges.append(cells) catch unreachable;
        }
    }
}

pub fn enabled(this: @This(), cell: Cell) bool {
    if (this.indexOf(cell)) |c| {
        return this.cells[c].enabled;
    }
    return false;
}

pub fn toggle(this: *@This(), cell: Cell) void {
    if (this.get_cell(cell)) |tile| {
        if (is_switch(tile)) {
            this.set_cell(cell, toggle_switch(tile));
        }
    }
}

const Queue = struct {
    data: std.BoundedArray(Cell, MAXCELLS),
    pub fn init() @This() {
        return @This(){
            .data = std.BoundedArray(Cell, MAXCELLS).init(0) catch unreachable,
        };
    }
    pub fn insert(this: *@This(), c: Cell) void {
        this.data.insert(0, c) catch unreachable;
    }
    pub fn remove(this: *@This()) ?Cell {
        return this.data.popOrNull();
    }
};

const w4 = @import("wasm4.zig");
pub fn fill(this: *@This(), root: Cell) void {
    var visited = std.StaticBitSet(MAXCELLS).initEmpty();
    var q = Queue.init();
    q.insert(root);
    while (q.remove()) |cell| {
        const index = this.indexOf(cell) orelse continue;
        const tile = this.get_cell(cell) orelse continue;
        if (visited.isSet(index)) continue;
        visited.set(index);
        this.enable(cell);
        for (get_inputs(tile)) |conductor, i| {
            if (!conductor) continue;
            const s = @intToEnum(Side, i);
            const delta = dir(s);
            q.insert(cell + delta);
        }
        if (is_plug(tile)) {
            for (this.bridges.constSlice()) |b| {
                if (@reduce(.And, b[0] == cell)) {
                    q.insert(b[1]);
                } else if (@reduce(.And, b[1] == cell)) {
                    q.insert(b[0]);
                }
            }
        }
    }
}

pub fn clear(this: *@This()) void {
    for (this.cells) |*cell| {
        cell.enabled = false;
    }
    this.bridges.resize(0) catch unreachable;
}
