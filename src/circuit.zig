const std = @import("std");
const util = @import("util.zig");
const assets = @import("assets");
const world = @import("world.zig");
const T = world.Tiles;

const Vec2 = util.Vec2;
const Cell = util.Cell;

pub fn switchIsOn(tile: u8) bool {
    return switch (tile) {
        T.SwitchTeeWestOn,
        T.SwitchTeeEastOn,
        T.SwitchVerticalOn,
        T.SwitchHorizontalOn,
        => true,

        T.SwitchTeeWestOff,
        T.SwitchTeeEastOff,
        T.SwitchVerticalOff,
        T.SwitchHorizontalOff,
        => false,

        else => false,
    };
}

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

pub fn getCoord(this: @This(), coord: world.Coordinate) ?u8 {
    const i = this.indexOf(coord.toVec2()) orelse return null;
    return if (this.map[i] != 0) this.map[i] else null;
}

pub fn setCoord(this: @This(), coord: world.Coordinate, tile: u8) void {
    const i = this.indexOf(coord.toVec2()) orelse return;
    this.map[i] = tile;
    // this.levels[i] = 255;
}

const MAXCELLS = 400;
const MAXBRIDGES = 20;
const MAXSOURCES = 10;
const MAXDOORS = 40;
const MAXLOGIC = 40;

pub const NodeCoord = struct { coord: world.Coordinate, node_id: world.NodeID };
pub const Source = NodeCoord;
pub const BridgeState = struct { coords: [2]world.Coordinate, id: usize, enabled: bool };
pub const DoorState = struct { coord: world.Coordinate, enabled: bool };

/// Tile id of the tiles
map: []u8,
/// CircuitNode ID for each tile
nodes: []world.NodeID,
map_size: Vec2,
bridges: util.Buffer(BridgeState),
sources: util.Buffer(Source),
doors: util.Buffer(DoorState),

pub const Options = struct {
    map: []u8,
    nodes: []u8,
    map_size: Vec2,
    bridges: []BridgeState,
    sources: []Source,
    doors: []DoorState,
};

pub fn init(opt: Options) @This() {
    std.debug.assert(opt.map.len == opt.nodes.len);
    var this = @This(){
        .map = opt.map,
        .nodes = opt.nodes,
        .map_size = opt.map_size,
        .bridges = util.Buffer(BridgeState).init(opt.bridges),
        .sources = util.Buffer(Source).init(opt.sources),
        .doors = util.Buffer(DoorState).init(opt.doors),
    };
    return this;
}

pub fn indexOf(this: @This(), cell: Cell) ?usize {
    if (cell[0] < 0 or cell[0] >= this.map_size[0] or cell[1] >= this.map_size[1] or cell[1] < 0) return null;
    return @intCast(usize, @mod(cell[0], this.map_size[0]) + (cell[1] * this.map_size[1]));
}

pub fn bridge(this: *@This(), coords: [2]world.Coordinate, bridgeID: usize) void {
    if (this.indexOf(coords[0].toVec2())) |_| {
        if (this.indexOf(coords[1].toVec2())) |_| {
            this.bridges.append(.{ .coords = coords, .id = bridgeID, .enabled = false });
        }
    }
}

pub fn addSource(this: *@This(), source: Source) void {
    w4.tracef("%d, %d", source.coord.val[0], source.coord.val[1]);
    if (this.indexOf(source.coord.toVec2())) |_| {
        this.sources.append(source);
    }
}

pub fn addDoor(this: *@This(), coord: world.Coordinate) !void {
    if (this.indexOf(coord.toVec2())) |_| {
        this.doors.append(.{ .coord = coord, .enabled = false });
    }
}

pub fn enabledBridge(this: @This(), id: usize) ?usize {
    var count: usize = 0;
    for (this.bridges.items) |b| {
        if (b.enabled) {
            if (count == id) {
                return b.id;
            }
            count += 1;
        }
    }
    return null;
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

pub fn getNodeID(this: @This(), coord: world.Coordinate) ?world.NodeID {
    const i = this.indexOf(coord.toVec2()) orelse return null;
    if (this.nodes[i] == std.math.maxInt(world.NodeID)) return null;
    return this.nodes[i];
}

pub fn switchOn(this: *@This(), coord: world.Coordinate) void {
    if (this.getCoord(coord)) |tile| {
        if (T.is_switch(tile)) {
            if (switchIsOn(tile)) return;
            const toggled = toggle_switch(tile);
            this.setCoord(coord, toggled);
            return;
        }
    }
}

pub fn toggle(this: *@This(), coord: world.Coordinate) ?u8 {
    if (this.getCoord(coord)) |tile| {
        if (T.is_switch(tile)) {
            const toggled = toggle_switch(tile);
            this.setCoord(coord, toggled);
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
    std.mem.set(u8, this.nodes, std.math.maxInt(world.NodeID));
    for (this.doors.items) |*door| {
        door.enabled = false;
    }
    this.bridges.reset();
}

pub fn reset(this: *@This()) void {
    this.clear();
    // Resizing to zero should always work
    this.sources.reset();
}

const w4 = @import("wasm4.zig");
// Returns number of cells filled
pub fn fill(this: *@This(), alloc: std.mem.Allocator, db: world.Database, level: world.Level) !usize {
    var count: usize = 0;
    w4.tracef("[fill] begin");

    const Queue = util.Queue(NodeCoord);
    var q_buf = try alloc.alloc(NodeCoord, MAXCELLS);
    var q = Queue.init(q_buf);

    for (this.sources.items) |source| {
        w4.tracef("[fill] inserting source (%d, %d)", source.coord.val[0], source.coord.val[1]);
        try q.insert(source);
    }
    // if (this.sources.items.len == 0) {
    //     w4.tracef("[fill] no sources %d", this.sources.items.len);
    // }

    while (q.remove()) |node| {
        const tile = this.getCoord(node.coord) orelse continue;
        const index = this.indexOf(node.coord.toVec2()) orelse continue;
        const hasVisited = this.nodes[index] != std.math.maxInt(world.NodeID);

        w4.tracef("[fill] %d, %d, %d", tile, index, hasVisited);
        if (hasVisited) continue;

        this.nodes[index] = node.node_id;

        count += 1;

        if (get_logic(tile)) |_| {
            // w4.tracef("[fill] logic");
            const new_id = db.getLevelNodeID(level, node.coord) orelse {
                w4.tracef("[fill] missing logic");
                continue;
            };
            try q.insert(.{ .node_id = new_id, .coord = node.coord.add(.{ 0, -1 }) });
            continue;
        }
        for (get_outputs(tile)) |conductor, i| {
            // w4.tracef("[fill] outputs");
            if (!conductor) continue;
            // w4.tracef("[fill] conductor");
            const s = @intToEnum(Side, i);
            const delta = s.dir();
            // TODO: check that cell can recieve from this side
            const nextCoord = node.coord.addC(world.Coordinate.fromVec2(delta));
            const tl = world.Coordinate.init(.{ 0, 0 });
            const br = world.Coordinate.fromVec2(this.map_size);
            // w4.tracef("[fill] next (%d, %d)", nextCoord.val[0], nextCoord.val[1]);
            // w4.tracef("[fill] range (%d, %d)-(%d, %d)", tl.val[0], tl.val[1], br.val[0], br.val[1]);
            if (!nextCoord.within(tl, br)) continue;
            // w4.tracef("[fill] within %d", nextCoord.within(tl, br));
            const nextTile = this.getCoord(nextCoord) orelse 0;
            // w4.tracef("[fill] nextTile");
            if (get_inputs(nextTile)[@enumToInt(s.opposite())]) {
                // w4.tracef("[fill] get_inputs");
                try q.insert(.{
                    .node_id = node.node_id,
                    .coord = nextCoord,
                });
            }
        }
        if (T.is_plug(tile)) {
            // w4.tracef("[fill] plug");
            for (this.bridges.items) |*b| {
                if (b.coords[0].eq(node.coord)) {
                    try q.insert(.{
                        .coord = b.coords[1],
                        .node_id = node.node_id,
                    });
                    b.enabled = true;
                } else if (b.coords[1].eq(node.coord)) {
                    try q.insert(.{
                        .coord = b.coords[0],
                        .node_id = node.node_id,
                    });
                    b.enabled = true;
                }
            }
        }
        w4.tracef("[fill] end search step");
    }
    return count;
}

const width = 20;
const height = 20;
const tile_size = Vec2{ 8, 8 };
const tilemap_width = 16;
const tilemap_height = 16;
const tilemap_stride = 128;

pub fn draw(this: @This(), db: world.Database, offset: Vec2) void {
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const cell = Vec2{ @intCast(i32, x), @intCast(i32, y) };
            const pos = cell * tile_size;
            const coord = world.Coordinate.fromVec2(cell + offset);
            const tile = this.getCoord(coord) orelse continue;
            if (tile == 0) continue;
            const energized = if (this.getNodeID(coord)) |node| db.circuit_info[node].energized else false;
            if (energized) w4.DRAW_COLORS.* = 0x0210 else w4.DRAW_COLORS.* = 0x0310;
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
