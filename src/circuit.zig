const std = @import("std");
const util = @import("util.zig");
const assets = @import("assets");
const world = @import("world.zig");
const T = world.Tiles;

const Vec2 = util.Vec2;
const Cell = util.Cell;

pub fn toggle_switch(tile: u8) u8 {
    return switch (tile) {
        // Tee west
        T.SwitchTeeWestOff => T.SwitchTeeWestOn,
        T.SwitchTeeWestOn => T.SwitchTeeWestOff,
        // Tee east
        T.SwitchTeeEastOff => T.SwitchTeeEastOn,
        T.SwitchTeeEastOn => T.SwitchTeeEastOff,
        // Vertical
        T.SwitchVerticalOn => T.SwitchVerticalOff,
        T.SwitchVerticalOff => T.SwitchVerticalOn,
        // Horizontal
        T.SwitchHorizontalOn => T.SwitchHorizontalOff,
        T.SwitchHorizontalOff => T.SwitchHorizontalOn,
        // Not a switch, pass tile through
        else => tile,
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
        // Conduit recieves from every side
        T.PlugNorth...T.PlugSouth,
        T.ConduitCross...T.ConduitSingle,
        => .{ true, true, true, true },
        // Switch_On
        T.SwitchTeeWestOn,
        T.SwitchTeeEastOn,
        T.SwitchVerticalOn,
        => .{ true, false, true, false },
        // Switch_Off
        T.SwitchTeeWestOff => .{ false, false, true, true },
        T.SwitchTeeEastOff => .{ false, true, true, false },
        // And, Xor
        T.LogicAnd,
        T.LogicXor,
        => .{ false, true, false, true },
        // Not
        T.LogicNot => .{ false, false, true, false },
        else => .{ false, false, false, false },
    };
}

fn get_outputs(tile: u8) Current {
    return switch (tile) {
        // Conduit goes out every side
        T.PlugNorth...T.PlugSouth,
        T.ConduitCross...T.ConduitSingle,
        => .{ true, true, true, true },
        // Switches
        // Tee west
        T.SwitchTeeWestOn => .{ false, false, true, true },
        T.SwitchTeeWestOff => .{ true, false, true, false },
        // Tee east
        T.SwitchTeeEastOn => .{ false, true, true, false },
        T.SwitchTeeEastOff => .{ true, false, true, false },
        // Vertical
        T.SwitchVerticalOn => .{ true, false, true, false },
        T.SwitchVerticalOff => .{ false, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Logic = union(enum) { Not, And, Xor };

fn get_logic(tile: u8) ?Logic {
    return switch (tile) {
        T.LogicAnd => .And,
        T.LogicNot => .Not,
        T.LogicXor => .Xor,
        else => null,
    };
}

const Plugs = [4]bool;
/// Returns sides where wires may be plugged
fn get_plugs(tile: u8) Plugs {
    return switch (tile) {
        world.Tiles.PlugNorth => .{ false, false, true, false },
        world.Tiles.PlugWest => .{ false, true, false, false },
        world.Tiles.PlugEast => .{ false, false, false, true },
        world.Tiles.PlugSouth => .{ true, false, false, false },
        else => .{ false, false, false, false },
    };
}

pub fn get_cell(this: @This(), cell: Cell) ?u8 {
    const i = this.indexOf(cell) orelse return null;
    return if (this.map[i] != 0) this.map[i] else null;
}

pub fn set_cell(this: *@This(), cell: Cell, tile: u8) void {
    const i = this.indexOf(cell) orelse return;
    this.map[i] = tile;
    this.levels[i] = 0;
}

const MAXCELLS = 400;
const MAXBRIDGES = 20;
const MAXSOURCES = 10;
const MAXDOORS = 40;
const MAXLOGIC = 40;

pub const CellData = struct { level: u8 = 0, tile: u8 };

pub const BridgeState = struct { cells: [2]Cell, id: usize, enabled: bool };
pub const DoorState = struct { cell: Cell, enabled: bool };

/// Tile id of the tiles
map: []u8,
/// Logic levels of the tiles
levels: []u8,
map_size: Vec2,
bridges: util.Buffer(BridgeState),
sources: util.Buffer(Cell),
doors: util.Buffer(DoorState),

pub const Options = struct {
    map: []u8,
    levels: []u8,
    map_size: Vec2,
    bridges: []BridgeState,
    sources: []Cell,
    doors: []DoorState,
};

pub fn init(opt: Options) @This() {
    std.debug.assert(opt.map.len == opt.levels.len);
    var this = @This(){
        .map = opt.map,
        .levels = opt.levels,
        .map_size = opt.map_size,
        .bridges = util.Buffer(BridgeState).init(opt.bridges),
        .sources = util.Buffer(Cell).init(opt.sources),
        .doors = util.Buffer(DoorState).init(opt.doors),
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

pub fn bridge(this: *@This(), cells: [2]Cell, bridgeID: usize) void {
    if (this.indexOf(cells[0])) |_| {
        if (this.indexOf(cells[1])) |_| {
            this.bridges.append(.{ .cells = cells, .id = bridgeID, .enabled = false });
        }
    }
}

pub fn addSource(this: *@This(), cell: Cell) void {
    if (this.indexOf(cell)) |_| {
        this.sources.append(cell);
    }
}

pub fn addDoor(this: *@This(), cell: Cell) !void {
    if (this.indexOf(cell)) |_| {
        this.doors.append(.{ .cell = cell, .enabled = false });
    }
}

pub fn enabledBridges(this: @This(), alloc: std.mem.Allocator) !util.Buffer(usize) {
    var items = try alloc.alloc(usize, this.bridges.len);
    var buffer = util.Buffer(usize).init(items);
    for (this.bridges.items) |b| {
        if (b.enabled) buffer.append(b.id);
    }
    return buffer;
}

pub fn enabledDoors(this: @This(), alloc: std.mem.Allocator) !util.Buffer(Cell) {
    var items = try alloc.alloc(Cell, this.doors.items.len);
    var buffer = util.Buffer(Cell).init(items);
    for (this.doors.items) |d| {
        const x = d.cell[0];
        const y = d.cell[1];
        w4.tracef("%d, %d", x, y);
        if (d.enabled) buffer.append(d.cell);
    }
    return buffer;
}

pub fn isEnabled(this: @This(), cell: Cell) bool {
    const i = this.indexOf(cell) orelse return false;
    return this.levels[i] >= 1;
}

pub fn toggle(this: *@This(), c: Cell) ?u8 {
    const cell = c;
    if (this.get_cell(cell)) |tile| {
        if (T.is_switch(tile)) {
            const toggled = toggle_switch(tile);
            this.set_cell(cell, toggled);
            return toggled;
        }
    }
    return null;
}

pub fn clearMap(this: *@This()) void {
    this.clear();
    std.mem.set(u8, this.map, 0);
    this.doors.reset();
    this.bridges.reset();
    this.sources.reset();
}

pub fn clear(this: *@This()) void {
    std.mem.set(u8, this.levels, 0);
    for (this.doors.items) |*door| {
        door.enabled = false;
    }
    this.bridges.reset();
}

pub fn reset(this: *@This()) void {
    this.clear();
    // Resizing to zero should always work
    this.sources.resize(0) catch unreachable;
}

const w4 = @import("wasm4.zig");
const Queue = util.Queue(Cell);
// Returns number of cells filled
pub fn fill(this: *@This(), alloc: std.mem.Allocator) !usize {
    var count: usize = 0;

    var items = try alloc.alloc(usize, MAXCELLS);
    defer alloc.free(items);

    var visited = util.Buffer(usize).init(items);

    var q_buf = try alloc.alloc(Cell, MAXCELLS);
    var q = Queue.init(q_buf);

    for (this.sources.items) |source| {
        try q.insert(source);
    }
    while (q.remove()) |cell| {
        const tile = this.get_cell(cell) orelse {
            for (this.doors.items) |*d| {
                if (@reduce(.And, d.cell == cell)) {
                    d.enabled = true;
                }
            }
            continue;
        };
        const index = this.indexOf(cell) orelse continue;
        this.enable(cell);
        const hasVisited = std.mem.containsAtLeast(usize, visited.items, 1, &.{index});
        if (hasVisited and !T.is_logic(tile)) continue;
        visited.append(index);
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
                for (this.doors.items) |*d| {
                    if (@reduce(.And, d.cell == nextCell)) {
                        d.enabled = true;
                    }
                }
                break :here 0;
            };
            if (get_inputs(nextTile)[@enumToInt(s.opposite())])
                try q.insert(nextCell);
        }
        if (T.is_plug(tile)) {
            for (this.bridges.items) |*b| {
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
