const std = @import("std");
const util = @import("util.zig");
const assets = @import("assets");

const Vec2 = util.Vec2;
const Cell = util.Cell;

pub fn is_circuit(tile: u8) bool {
    return is_plug(tile) or is_conduit(tile) or is_switch(tile) or is_logic(tile);
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
    return tile >= 27 and tile <= 30;
}

pub fn is_logic(tile: u8) bool {
    return tile >= 59 and tile <= 62;
}

pub fn toggle_switch(tile: u8) u8 {
    return switch (tile) {
        27 => 28,
        28 => 27,
        29 => 30,
        30 => 29,
        else => unreachable,
    };
}

const Side = enum(u2) {
    up,
    right,
    down,
    left,
    pub fn opposite(s: Side) Side {
        return switch (s) {
            .up => .down,
            .down => .up,
            .left => .right,
            .right => .left,
        };
    }
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
};

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
        // Switch
        27, 28, 29, 30 => .{ true, false, true, false },
        // Logic
        59 => .{ false, true, false, true },
        60 => .{ false, false, true, false },
        61 => .{ false, true, false, true },
        else => .{ false, false, false, false },
    };
}

fn get_outputs(tile: u8) Current {
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
        // Switch
        27, 29 => .{ true, false, true, false },
        28 => .{ false, false, false, true },
        30 => .{ false, true, false, false },
        // Logic
        // Calculated in fill
        // 59 => .{ false, false, false, false },
        // 60 => .{ true, false, false, false },
        // 61 => .{ true, false, false, false },
        else => .{ false, false, false, false },
    };
}

const Logic = union(enum) { Not, And, Xor };

fn get_logic(tile: u8) ?Logic {
    return switch (tile) {
        59 => .And,
        60 => .Not,
        61 => .Xor,
        else => null,
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
    const i = this.indexOf(cell) orelse return null;
    return if (this.map[i] != 0) this.map[i] - 1 else null;
}

pub fn set_cell(this: *@This(), cell: Cell, tile: u8) void {
    const i = this.indexOf(cell) orelse return;
    this.map[i] = tile + 1;
    this.levels[i] = 0;
}

const MAXCELLS = 400;
const MAXBRIDGES = 20;
const MAXSOURCES = 10;
const MAXDOORS = 40;
const MAXLOGIC = 40;

pub const CellData = struct { level: u8 = 0, tile: u8 };

const BridgeState = struct { cells: [2]Cell, id: usize, enabled: bool };
const DoorState = struct { cell: Cell, enabled: bool };

/// Tile id of the tiles
map: []u8,
/// Logic levels of the tiles
levels: []u8,
map_size: Vec2,
bridges: std.BoundedArray(BridgeState, MAXBRIDGES),
sources: std.BoundedArray(Cell, MAXSOURCES),
doors: std.BoundedArray(DoorState, MAXDOORS),

pub fn init(map: []u8, levels: []u8, map_size: Vec2) !@This() {
    std.debug.assert(map.len == levels.len);
    var this = @This(){
        .map = map,
        .levels = levels,
        .map_size = map_size,
        .bridges = try std.BoundedArray(BridgeState, MAXBRIDGES).init(0),
        .sources = try std.BoundedArray(Cell, MAXSOURCES).init(0),
        .doors = try std.BoundedArray(DoorState, MAXDOORS).init(0),
    };
    return this;
}

pub fn indexOf(this: @This(), cell: Cell) ?usize {
    if (cell[0] < 0 or cell[0] >= this.map_size[0] or cell[1] >= this.map_size[1] or cell[1] < 0) return null;
    return @intCast(usize, @mod(cell[0], this.map_size[0]) + (cell[1] * this.map_size[1]));
}

pub fn enable(this: *@This(), cell: Cell) void {
    const i = this.indexOf(cell) orelse return;
    this.levels[i] += 1;
}

pub fn bridge(this: *@This(), cells: [2]Cell, bridgeID: usize) !void {
    if (this.indexOf(cells[0])) |_| {
        if (this.indexOf(cells[1])) |_| {
            try this.bridges.append(.{ .cells = cells, .id = bridgeID, .enabled = false });
        }
    }
}

pub fn addSource(this: *@This(), cell: Cell) !void {
    if (this.indexOf(cell)) |_| {
        try this.sources.append(cell);
    }
}

pub fn addDoor(this: *@This(), cell: Cell) !void {
    if (this.indexOf(cell)) |_| {
        try this.doors.append(.{ .cell = cell, .enabled = false });
    }
}

pub fn enabledBridges(this: @This()) !std.BoundedArray(usize, MAXBRIDGES) {
    var items = try std.BoundedArray(usize, MAXBRIDGES).init(0);
    for (this.bridges.constSlice()) |b| {
        if (b.enabled) try items.append(b.id);
    }
    return items;
}

pub fn enabledDoors(this: @This()) !std.BoundedArray(Cell, MAXDOORS) {
    var items = try std.BoundedArray(Cell, MAXDOORS).init(0);
    for (this.doors.constSlice()) |d| {
        if (d.enabled) try items.append(d.cell);
    }
    return items;
}

pub fn isEnabled(this: @This(), cell: Cell) bool {
    const i = this.indexOf(cell) orelse return false;
    return this.levels[i] >= 1;
}

pub fn toggle(this: *@This(), c: Cell) void {
    const cell = c;
    if (this.get_cell(cell)) |tile| {
        if (is_switch(tile)) {
            const toggled = toggle_switch(tile);
            this.set_cell(cell, toggled);
        }
    }
}

pub fn clear(this: *@This()) void {
    std.mem.set(u8, this.levels, 0);
    for (this.doors.slice()) |*door| {
        door.enabled = false;
    }
    // Resizing to zero should always work
    this.bridges.resize(0) catch unreachable;
}

pub fn reset(this: *@This()) void {
    this.clear();
    // Resizing to zero should always work
    this.sources.resize(0) catch unreachable;
}

const w4 = @import("wasm4.zig");
const Queue = util.Queue(Cell, MAXCELLS);
// Returns number of cells filled
pub fn fill(this: *@This()) !usize {
    var count: usize = 0;
    var visited = try std.BoundedArray(usize, MAXCELLS).init(0);
    var q = try Queue.init();
    for (this.sources.slice()) |source| {
        try q.insert(source);
    }
    while (q.remove()) |cell| {
        const tile = this.get_cell(cell) orelse {
            for (this.doors.slice()) |*d| {
                if (@reduce(.And, d.cell == cell)) {
                    d.enabled = true;
                }
            }
            continue;
        };
        const index = this.indexOf(cell) orelse continue;
        this.enable(cell);
        const hasVisited = std.mem.containsAtLeast(usize, visited.slice(), 1, &.{index});
        if (hasVisited and !is_logic(tile)) continue;
        try visited.append(index);
        count += 1;
        if (get_logic(tile)) |logic| {
            // TODO: implement other logic (though I'm pretty sure that requires a graph...)
            if (logic != .And) continue;
            if (this.levels[index] < 2) continue;
            try q.insert(cell + util.Dir.up);
        }
        for (get_outputs(tile)) |conductor, i| {
            if (!conductor) continue;
            const s = @intToEnum(Side, i);
            const delta = s.dir();
            // TODO: check that cell can recieve from this side
            const nextCell = cell + delta;
            if (nextCell[0] < 0 or nextCell[1] < 0 or
                nextCell[0] >= this.map_size[0] or
                nextCell[1] >= this.map_size[1])
                continue;
            const nextTile = this.get_cell(nextCell) orelse here: {
                for (this.doors.slice()) |*d| {
                    if (@reduce(.And, d.cell == nextCell)) {
                        d.enabled = true;
                    }
                }
                break :here 0;
            };
            if (get_inputs(nextTile)[@enumToInt(s.opposite())])
                try q.insert(nextCell);
        }
        if (is_plug(tile)) {
            for (this.bridges.slice()) |*b| {
                if (@reduce(.And, b.cells[0] == cell)) {
                    try q.insert(b.cells[1]);
                    b.enabled = true;
                } else if (@reduce(.And, b.cells[1] == cell)) {
                    try q.insert(b.cells[0]);
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

pub fn draw(this: @This(), offset: Vec2) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const cell = Vec2{ @intCast(i32, x), @intCast(i32, y) };
            const pos = cell * tile_size;
            const tile = this.get_cell(cell + offset) orelse continue;
            if (tile == 0) continue;
            if (this.isEnabled(cell + offset)) w4.DRAW_COLORS.* = 0x0210 else w4.DRAW_COLORS.* = 0x0310;
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
