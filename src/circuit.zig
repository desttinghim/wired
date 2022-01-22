const std = @import("std");
const util = @import("util.zig");

const Vec2 = util.Vec2;
const Cell = util.Cell;

pub fn is_circuit(tile: u8) bool {
    return is_plug(tile) or is_conduit(tile) or is_switch(tile);
}

pub fn is_plug(tile: u8) bool {
    return (tile >= 149 and tile <= 153) or tile == 147;
}

pub fn is_conduit(tile: u8) bool {
    return (tile >= 128 and tile < 132) or
        (tile >= 144 and tile < 148) or
        (tile >= 160 and tile < 164) or
        (tile >= 176 and tile < 180);
}

pub fn is_switch(tile: u8) bool {
    return tile >= 134 and tile < 136;
}

pub fn toggle_switch(tile: u8) u8 {
    return if (tile == 134) 135 else 134;
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
const MAXBRIDGES = 10;
const CellMap = [MAXCELLS]CellState;
const BridgeState = struct { cells: [2]Cell, id: usize, enabled: bool };

offset: Cell,
cells: CellMap,
bridges: std.BoundedArray(BridgeState, MAXBRIDGES),

pub fn init() @This() {
    var this = @This(){
        .offset = Cell{ 0, 0 },
        .cells = undefined,
        .bridges = std.BoundedArray(BridgeState, MAXBRIDGES).init(0) catch unreachable,
    };
    return this;
}

pub fn load(this: *@This(), offset: Cell, map: []const u8, map_size: Vec2) void {
    this.offset = offset;
    var y: usize = 0;
    while (y < 20) : (y += 1) {
        var x: usize = 0;
        while (x < 20) : (x += 1) {
            const i = x + y * 20;
            const a = (@intCast(usize, offset[0]) + x) + (@intCast(usize, offset[1]) + y) * @intCast(usize, map_size[0]);
            this.cells[i].tile = map[a];
        }
    }
}

pub fn indexOf(this: @This(), cell: Cell) ?usize {
    return cell2index(cell - this.offset);
}

pub fn enable(this: *@This(), cell: Cell) void {
    if (this.indexOf(cell)) |c| {
        this.cells[c].enabled = true;
    }
}

pub fn bridge(this: *@This(), cells: [2]Cell, bridgeID: usize) void {
    if (this.indexOf(cells[0])) |_| {
        if (this.indexOf(cells[1])) |_| {
            this.bridges.append(.{ .cells = cells, .id = bridgeID, .enabled = false }) catch unreachable;
        }
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

pub fn clear(this: *@This()) void {
    for (this.cells) |*cell| {
        cell.enabled = false;
    }
    this.bridges.resize(0) catch unreachable;
}

// Returns number of cells filled
pub fn fill(this: *@This(), rootRaw: Cell) usize {
    const Queue = util.Queue(Cell, MAXCELLS);
    var count: usize = 0;
    const root = rootRaw - this.offset;
    var visited: [MAXCELLS]bool = [_]bool{false} ** MAXCELLS;
    var q = Queue.init();
    q.insert(root);
    while (q.remove()) |cell| {
        const index = this.indexOf(cell) orelse continue;
        const tile = this.get_cell(cell) orelse continue;
        if (visited[index]) continue;
        visited[index] = true;
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
