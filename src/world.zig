//! Data types used for storing world info

const std = @import("std");

/// The CircuitType of a tile modifies how the tile responds to
/// electricity
pub const CircuitType = enum(u4) {
    None = 0,
    Conduit = 1,
    Plug = 2,
    Switch_Off = 3,
    Switch_On = 4,
    Join = 5,
    And = 6,
    Xor = 7,
    Outlet = 8,
    Source = 9,
    Socket = 10,
};

/// This lists the most important tiles so I don't have to keep rewriting things
pub const Tiles = struct {
    // Switches
    pub const SwitchTeeWestOff = 24;
    pub const SwitchTeeWestOn = 25;

    pub const SwitchTeeEastOff = 26;
    pub const SwitchTeeEastOn = 27;

    pub const SwitchVerticalOff = 28;
    pub const SwitchVerticalOn = 29;

    pub const SwitchHorizontalOff = 30;
    pub const SwitchHorizontalOn = 31;

    pub fn is_switch(tile: u8) bool {
        return tile >= SwitchTeeWestOff and tile <= SwitchHorizontalOn;
    }

    // Plugs, sorted by autotile order
    pub const PlugNorth = 16;
    pub const PlugWest = 17;
    pub const PlugEast = 18;
    pub const PlugSouth = 19;

    pub fn is_plug(tile: u8) bool {
        return tile >= 16 and tile < 20;
    }

    pub const LogicAnd = 21;
    pub const LogicNot = 22;
    pub const LogicXor = 23;

    pub fn is_logic(tile: u8) bool {
        return tile >= 21 and tile <= 24;
    }

    pub const ConduitCross = 96;
    pub const ConduitSingle = 112;

    pub fn is_conduit(tile: u8) bool {
        return tile >= ConduitCross and tile <= ConduitSingle;
    }

    pub fn is_circuit(tile: u8) bool {
        return is_plug(tile) or is_conduit(tile) or is_switch(tile) or is_logic(tile);
    }

    pub const WallSingle = 112;
    pub const WallSurrounded = 127;

    pub fn is_wall(tile: u8) bool {
        return tile >= WallSingle and tile <= WallSurrounded;
    }

    pub const Door = 2;
    pub const Trapdoor = 3;

    pub fn is_door(tile: u8) bool {
        return tile == Door or tile == Trapdoor;
    }

    pub fn is_solid(tile: u8) bool {
        return is_wall(tile) or is_door(tile);
    }

    pub const OneWayLeft = 33;
    pub const OneWayMiddle = 34;
    pub const OneWayRight = 35;

    pub fn is_oneway(tile: u8) bool {
        return tile >= OneWayLeft and tile <= OneWayRight;
    }

    pub const Empty = 0;

    pub const Walls = AutoTileset.initOffsetFull(WallSingle);
    pub const Conduit = AutoTileset.initOffsetFull(ConduitCross);
    pub const Plugs = AutoTileset.initOffsetCardinal(PlugNorth);
    pub const SwitchesOff = AutoTileset.initSwitches(&.{
        SwitchVerticalOff, // South-North
        SwitchTeeWestOff, // South-West-North
        SwitchTeeEastOff, // South-East-North
    }, 2);
    pub const SwitchesOn = AutoTileset.initSwitches(&.{
        SwitchVerticalOn, // South-North
        SwitchTeeWestOn, // South-West-North
        SwitchTeeEastOn, // South-East-North
    }, 2);
};

pub const TileData = union(enum) {
    tile: u7,
    flags: struct {
        solid: bool,
        circuit: CircuitType,
    },

    pub fn getCircuit(data: TileData) ?CircuitType {
        switch (data) {
            .tile => |_| return null,
            .flags => |flags| {
                if (flags.circuit == .None) return null;
                return flags.circuit;
            },
        }
    }

    pub fn toByte(data: TileData) u8 {
        switch (data) {
            .tile => |int| return 0b1000_0000 | @intCast(u8, int),
            .flags => |flags| {
                const circuit = @enumToInt(flags.circuit);
                return (@intCast(u7, @boolToInt(flags.solid))) | (@intCast(u7, circuit) << 1);
            },
        }
    }

    pub fn fromByte(byte: u8) TileData {
        const is_tile = (0b1000_0000 & byte) > 0;
        if (is_tile) {
            const tile = @intCast(u7, (0b0111_1111 & byte));
            return TileData{ .tile = tile };
        } else {
            const is_solid = (0b0000_0001 & byte) > 0;
            const circuit = @intCast(u4, (0b0001_1110 & byte) >> 1);
            return TileData{ .flags = .{
                .solid = is_solid,
                .circuit = @intToEnum(CircuitType, circuit),
            } };
        }
    }
};

// Shorthand
const Coord = Coordinate;
pub const Coordinate = struct {
    const LEVELSIZE = 20;
    val: [2]i16,

    pub fn init(val: [2]i16) Coordinate {
        return Coordinate{ .val = val };
    }

    pub fn read(reader: anytype) !Coordinate {
        return Coordinate{ .val = .{
            try reader.readInt(i16, .Little),
            try reader.readInt(i16, .Little),
        } };
    }

    pub fn write(coord: Coordinate, writer: anytype) !void {
        try writer.writeInt(i16, coord.val[0], .Little);
        try writer.writeInt(i16, coord.val[1], .Little);
    }

    pub fn add(coord: Coordinate, val: [2]i16) Coordinate {
        return .{ .val = .{ coord.val[0] + val[0], coord.val[1] + val[1] } };
    }

    pub fn sub(coord: Coordinate, val: [2]i16) Coordinate {
        return .{ .val = .{ coord.val[0] - val[0], coord.val[1] - val[1] } };
    }

    pub fn addC(coord: Coordinate, other: Coordinate) Coordinate {
        return .{ .val = .{ coord.val[0] + other.val[0], coord.val[1] + other.val[1] } };
    }

    pub fn subC(coord: Coordinate, other: Coordinate) Coordinate {
        return .{ .val = .{ coord.val[0] - other.val[0], coord.val[1] - other.val[1] } };
    }

    pub fn addOffset(coord: Coordinate, val: [2]i4) Coordinate {
        return .{ .val = .{ coord.val[0] + val[0], coord.val[1] + val[1] } };
    }

    pub fn eq(coord: Coordinate, other: Coordinate) bool {
        return coord.val[0] == other.val[0] and coord.val[1] == other.val[1];
    }

    pub fn within(coord: Coord, nw: Coord, se: Coord) bool {
        return coord.val[0] >= nw.val[0] and coord.val[1] >= nw.val[1] and
            coord.val[0] < se.val[0] and coord.val[1] < se.val[1];
    }

    pub fn toWorld(coord: Coordinate) [2]i8 {
        const world_x = @intCast(i8, @divFloor(coord.val[0], LEVELSIZE));
        const world_y = @intCast(i8, @divFloor(coord.val[1], LEVELSIZE));
        return .{ world_x, world_y };
    }

    pub fn toVec2(coord: Coordinate) @Vector(2, i32) {
        return .{ coord.val[0], coord.val[1] };
    }

    pub fn toOffset(coord: Coordinate) [2]i4 {
        return .{ @intCast(i4, coord.val[0]), @intCast(i4, coord.val[1]) };
    }

    pub fn fromWorld(x: i8, y: i8) Coordinate {
        return .{ .val = .{
            @intCast(i16, x) * 20,
            @intCast(i16, y) * 20,
        } };
    }

    pub fn fromVec2(vec: @Vector(2, i32)) Coordinate {
        return .{ .val = .{ @intCast(i16, vec[0]), @intCast(i16, vec[1]) } };
    }

    pub fn fromVec2f(vec: @Vector(2, f32)) Coordinate {
        return fromVec2(.{ @floatToInt(i32, vec[0]), @floatToInt(i32, vec[1]) });
    }

    pub fn toLevelTopLeft(coord: Coordinate) Coordinate {
        const worldc = coord.toWorld();
        return .{ .val = .{
            @intCast(i16, worldc[0]) * LEVELSIZE,
            @intCast(i16, worldc[1]) * LEVELSIZE,
        } };
    }

    pub fn format(coord: Coordinate, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "p")) {
            return std.fmt.format(writer, "({d:>5},{d:>5})", .{ coord.val[0], coord.val[1] });
        } else {
            @compileError("Unknown format character: '" ++ fmt ++ "'");
        }
    }
};

pub const Level = struct {
    world_x: i8,
    world_y: i8,
    width: u16,
    size: u16,
    tiles: ?[]TileData,

    pub fn init(x: u8, y: u8, width: u16, buf: []TileData) Level {
        return Level{
            .world_x = x,
            .world_y = y,
            .width = width,
            .size = buf.len,
            .tiles = buf,
        };
    }

    pub fn calculateSize(level: Level) !usize {
        const tiles = level.tiles orelse return error.NullTiles;
        return @sizeOf(i8) + // world_x
            @sizeOf(i8) + // world_y
            @sizeOf(u16) + // width
            @sizeOf(u16) + // size
            tiles.len;
    }

    pub fn write(level: Level, writer: anytype) !void {
        var tiles = level.tiles orelse return error.NullTiles;
        try writer.writeInt(i8, level.world_x, .Little);
        try writer.writeInt(i8, level.world_y, .Little);
        try writer.writeInt(u16, level.width, .Little);
        try writer.writeInt(u16, level.size, .Little);

        for (tiles) |tile| {
            try writer.writeByte(tile.toByte());
        }
    }

    pub fn read(reader: anytype) !Level {
        return Level{
            .world_x = try reader.readInt(i8, .Little),
            .world_y = try reader.readInt(i8, .Little),
            .width = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u16, .Little),
            .tiles = null,
        };
    }

    pub fn readTiles(level: *Level, reader: anytype, buf: []TileData) !void {
        std.debug.assert(buf.len >= level.size);
        level.tiles = buf;
        var i: usize = 0;
        while (i < level.size) : (i += 1) {
            buf[i] = TileData.fromByte(try reader.readByte());
        }
    }

    pub fn getTile(level: Level, globalc: Coord) ?TileData {
        const tiles = level.tiles orelse return null;
        const worldc = globalc.toLevelTopLeft();
        const x = globalc.val[0] - worldc.val[0];
        const y = globalc.val[1] - worldc.val[1];
        const w = @intCast(i16, level.width);
        const i = @intCast(usize, x + y * w);
        return tiles[i];
    }

    pub fn getJoin(level: Level, which: usize) ?Coordinate {
        const tiles = level.tiles orelse return null;
        var joinCount: usize = 0;
        for (tiles) |tile, i| {
            switch (tile) {
                .flags => |flag| {
                    if (flag.circuit == .Join) {
                        if (joinCount == which) {
                            const x = @intCast(i16, @mod(i, 20));
                            const y = @intCast(i16, @divFloor(i, 20));
                            return Coord.init(.{ x, y });
                        }
                        joinCount += 1;
                    }
                },
                else => continue,
            }
        }
        return null;
    }
};

// AutoTile algorithm datatypes
pub const AutoTile = packed struct {
    North: bool,
    West: bool,
    East: bool,
    South: bool,

    pub fn to_u4(autotile: AutoTile) u4 {
        return @bitCast(u4, autotile);
    }

    pub fn from_u4(int: u4) AutoTile {
        return @bitCast(AutoTile, int);
    }
};

pub const AutoTileset = struct {
    lookup: []const u8 = "",
    offset: u8 = 0,
    kind: enum {
        Cardinal,
        Switches,
        Full,
        OffsetFull,
        OffsetCardinal,
    },
    default: u8 = 0,

    pub fn initFull(table: []const u8) AutoTileset {
        std.debug.assert(table.len == 16);
        return AutoTileset{
            .lookup = table,
            .kind = .Full,
        };
    }

    pub fn initCardinal(table: []const u8, default: u8) AutoTileset {
        std.debug.assert(table.len == 4);
        return AutoTileset{
            .lookup = table,
            .kind = .Cardinal,
            .default = default,
        };
    }

    pub fn initSwitches(table: []const u8, default: u8) AutoTileset {
        std.debug.assert(table.len == 3);
        return AutoTileset{
            .lookup = table,
            .kind = .Switches,
            .default = default,
        };
    }

    pub fn initOffsetFull(offset: u8) AutoTileset {
        // std.debug.assert(offset < 128 - 16);
        return AutoTileset{
            .offset = offset,
            .kind = .OffsetFull,
        };
    }

    pub fn initOffsetCardinal(offset: u8) AutoTileset {
        // std.debug.assert(offset < 128 - 4);
        return AutoTileset{
            .offset = offset,
            .kind = .OffsetCardinal,
        };
    }

    pub fn find(tileset: AutoTileset, autotile: AutoTile) u8 {
        const autoint = autotile.to_u4();
        switch (tileset.kind) {
            .Full => return tileset.lookup[autoint],
            .OffsetFull => return tileset.offset + autoint,
            .Cardinal, .OffsetCardinal => {
                const index: u8 = switch (autoint) {
                    0b0001 => 0,
                    0b0010 => 1,
                    0b0100 => 2,
                    0b1000 => 3,
                    else => return tileset.default,
                };
                if (tileset.kind == .Cardinal) {
                    return tileset.lookup[index];
                } else {
                    return tileset.offset + index;
                }
            },
            .Switches => switch (autoint) {
                0b1001 => return tileset.lookup[0],
                0b1011 => return tileset.lookup[1],
                0b1101 => return tileset.lookup[2],
                else => return tileset.default,
            },
        }
    }
};

pub const EntityKind = enum(u8) {
    Player,
    Coin,
    Door,
    Trapdoor,
    Collected,
};

pub const Entity = struct {
    kind: EntityKind,
    coord: Coordinate,

    pub fn calculateSize() usize {
        return @sizeOf(u8) + // kind
            @sizeOf(i16) + // x
            @sizeOf(i16); // y
    }

    pub fn write(entity: Entity, writer: anytype) !void {
        try writer.writeInt(u8, @enumToInt(entity.kind), .Little);
        try entity.coord.write(writer);
    }

    pub fn read(reader: anytype) !Entity {
        return Entity{
            .kind = @intToEnum(EntityKind, try reader.readInt(u8, .Little)),
            .coord = try Coordinate.read(reader),
        };
    }
};

const WireKind = enum {
    Begin,
    BeginPinned,
    Point,
    PointPinned,
    End,
};

/// A wire is stored as a coordinate and at least one point relative to it,
/// and then an end byte
pub const Wire = union(enum) {
    Begin: Coordinate,
    BeginPinned: Coordinate,
    /// Relative to the last point
    Point: [2]i4,
    /// Relative to the last point
    PointPinned: [2]i4,
    End,

    const EndData = struct { coord: Coordinate, anchored: bool };

    pub fn getEnds(wires: []Wire) ![2]EndData {
        std.debug.assert(wires[0] == .Begin or wires[0] == .BeginPinned);
        var ends: [2]EndData = undefined;
        for (wires) |wire| {
            switch (wire) {
                .Begin => |coord| {
                    ends[0] = .{ .coord = coord, .anchored = false };
                    ends[1] = ends[0];
                },
                .BeginPinned => |coord| {
                    ends[0] = .{ .coord = coord, .anchored = true };
                    ends[1] = ends[0];
                },
                .Point => |offset| {
                    ends[1] = .{ .coord = ends[1].coord.addOffset(offset), .anchored = false };
                },
                .PointPinned => |offset| {
                    ends[1] = .{ .coord = ends[1].coord.addOffset(offset), .anchored = true };
                },
                .End => {
                    return ends;
                },
            }
        }
        return error.MissingEnds;
    }

    pub fn write(wire: Wire, writer: anytype) !void {
        try writer.writeByte(@enumToInt(wire));
        switch (wire) {
            .Begin => |coord| {
                try coord.write(writer);
            },
            .BeginPinned => |coord| {
                try coord.write(writer);
            },
            .Point => |point| {
                const byte = @bitCast(u8, @intCast(i8, point[0])) | @bitCast(u8, @intCast(i8, point[1])) << 4;
                try writer.writeByte(byte);
            },
            .PointPinned => |point| {
                const byte = @bitCast(u8, @intCast(i8, point[0])) | @bitCast(u8, @intCast(i8, point[1])) << 4;
                try writer.writeByte(byte);
            },
            .End => {},
        }
    }

    pub fn read(reader: anytype) !Wire {
        const kind = @intToEnum(WireKind, try reader.readByte());
        switch (kind) {
            .Begin => return Wire{ .Begin = try Coord.read(reader) },
            .BeginPinned => return Wire{ .BeginPinned = try Coord.read(reader) },
            .Point => {
                const byte = try reader.readByte();
                return Wire{ .Point = .{
                    @bitCast(i4, @truncate(u4, 0b0000_1111 & byte)),
                    @bitCast(i4, @truncate(u4, (0b1111_0000 & byte) >> 4)),
                } };
            },
            .PointPinned => {
                const byte = try reader.readByte();
                return Wire{ .PointPinned = .{
                    @bitCast(i4, @truncate(u4, 0b0000_1111 & byte)),
                    @bitCast(i4, @truncate(u4, (0b1111_0000 & byte) >> 4)),
                } };
            },
            .End => return Wire.End,
        }
    }
};

/// Used to look up level data
pub const LevelHeader = struct {
    x: i8,
    y: i8,
    offset: u16,

    pub fn write(header: LevelHeader, writer: anytype) !void {
        try writer.writeInt(i8, header.x, .Little);
        try writer.writeInt(i8, header.y, .Little);
        try writer.writeInt(u16, header.offset, .Little);
    }

    pub fn read(reader: anytype) !LevelHeader {
        return LevelHeader{
            .x = try reader.readInt(i8, .Little),
            .y = try reader.readInt(i8, .Little),
            .offset = try reader.readInt(u16, .Little),
        };
    }
};

pub fn write(
    writer: anytype,
    level_headers: []LevelHeader,
    entities: []Entity,
    wires: []Wire,
    circuit_nodes: []CircuitNode,
    levels: []Level,
) !void {
    // Write number of levels
    try writer.writeInt(u16, @intCast(u16, level_headers.len), .Little);
    // Write number of entities
    try writer.writeInt(u16, @intCast(u16, entities.len), .Little);
    // Write number of entities
    try writer.writeInt(u16, @intCast(u16, wires.len), .Little);
    // Write number of circuit nodes
    try writer.writeInt(u16, @intCast(u16, circuit_nodes.len), .Little);

    // Write headers
    for (level_headers) |lvl_header| {
        try lvl_header.write(writer);
    }

    // Write entity data
    for (entities) |entity| {
        try entity.write(writer);
    }

    // Write wire data
    for (wires) |wire| {
        try wire.write(writer);
    }

    // Write node data
    for (circuit_nodes) |node| {
        try node.write(writer);
    }

    // Write levels
    for (levels) |level| {
        try level.write(writer);
    }
}

const Cursor = std.io.FixedBufferStream([]const u8);
pub const Database = struct {
    cursor: Cursor,
    level_info: []LevelHeader,
    entities: []Entity,
    wires: []Wire,
    wire_count: usize,
    circuit_info: []CircuitNode,
    level_data_begin: usize,

    const world_data = @embedFile(@import("world_data").path);

    pub fn init(alloc: std.mem.Allocator) !Database {
        var cursor = Cursor{
            .pos = 0,
            .buffer = world_data,
        };

        var reader = cursor.reader();

        // read number of levels
        const level_count = try reader.readInt(u16, .Little);
        // read number of entities
        const entity_count = try reader.readInt(u16, .Little);
        // read number of wires
        const wire_count = try reader.readInt(u16, .Little);
        // read number of nodes
        const node_count = try reader.readInt(u16, .Little);

        var level_headers = try alloc.alloc(LevelHeader, level_count);

        // read headers
        for (level_headers) |_, i| {
            level_headers[i] = try LevelHeader.read(reader);
        }

        // read entities
        var entities = try alloc.alloc(Entity, entity_count);

        for (entities) |_, i| {
            entities[i] = try Entity.read(reader);
        }

        // read wires
        // Allocate a fixed amount of space since wires are likely to be shuffled around
        var wires = try alloc.alloc(Wire, 255);
        {
            var i: usize = 0;
            while (i < wire_count) : (i += 1) {
                wires[i] = try Wire.read(reader);
            }
        }

        // read circuits
        var circuit_nodes = try alloc.alloc(CircuitNode, node_count);

        for (circuit_nodes) |_, i| {
            circuit_nodes[i] = try CircuitNode.read(reader);
        }

        // Save where the rest of the data ended, and the level data begins
        var level_data_begin = @intCast(usize, try cursor.getPos());

        return Database{
            .cursor = cursor,
            .level_info = level_headers,
            .entities = entities,
            .wires = wires,
            .wire_count = wire_count,
            .circuit_info = circuit_nodes,
            .level_data_begin = level_data_begin,
        };
    }

    // Level functions

    pub fn levelInfo(db: *Database, level: usize) !Level {
        if (level > db.level_info.len) return error.InvalidLevel;
        try db.cursor.seekTo(db.level_data_begin + db.level_info[level].offset);
        const reader = db.cursor.reader();

        return try Level.read(reader);
    }

    pub fn levelLoad(db: *Database, alloc: std.mem.Allocator, level: usize) !Level {
        var level_info = try db.levelInfo(level);

        const reader = db.cursor.reader();

        var level_buf = try alloc.alloc(TileData, level_info.size);
        try level_info.readTiles(reader, level_buf);

        return level_info;
    }

    pub fn findLevel(db: *Database, x: i8, y: i8) ?usize {
        for (db.level_info) |level, i| {
            if (level.x == x and level.y == y) {
                return i;
            }
        }
        return null;
    }

    // Circuit functions

    fn getNodeID(db: *Database, coord: Coord) ?NodeID {
        for (db.circuit_info) |node, i| {
            if (!coord.eq(node.coord)) continue;
            return @intCast(NodeID, i);
        }
        return null;
    }

    pub fn connectPlugs(db: *Database, p1: Coord, p2: Coord) !void {
        const p1id = db.getNodeID(p1) orelse return;
        const p2id = db.getNodeID(p2) orelse return;

        if (db.circuit_info[p1id].kind == .Plug and db.circuit_info[p2id].kind == .Socket) {
            db.circuit_info[p2id].kind.Socket = p1id;
        } else if (db.circuit_info[p2id].kind == .Plug and db.circuit_info[p1id].kind == .Socket) {
            db.circuit_info[p1id].kind.Socket = p2id;
        } else if (db.circuit_info[p2id].kind == .Socket and db.circuit_info[p1id].kind == .Plug) {
            return error.Unimplemented;
        }
    }

    pub fn disconnectPlug(db: *Database, plug: Coord) void {
        for (db.circuit_info) |node, i| {
            if (!plug.eq(node.coord)) continue;
            db.circuit_info[i].energized = false;
        }
    }

    pub fn setSwitch(db: *Database, coord: Coord, new_state: u8) void {
        const _switch = db.getNodeID(coord) orelse return;
        db.circuit_info[_switch].kind.Switch.state = new_state;
    }

    pub fn isEnergized(db: *Database, coord: Coord) bool {
        for (db.circuit_info) |node, i| {
            if (!coord.eq(node.coord)) continue;
            return db.circuit_info[i].energized;
        }
        return false;
    }

    fn updateCircuitFragment(db: *Database, i: usize, visited: []bool) bool {
        if (visited[i]) return db.circuit_info[i].energized;
        visited[i] = true;
        const node = db.circuit_info[i];
        switch (node.kind) {
            .And => |And| {
                const input1 = db.updateCircuitFragment(And[0], visited);
                const input2 = db.updateCircuitFragment(And[1], visited);
                db.circuit_info[i].energized = (input1 and input2);
            },
            .Xor => |Xor| {
                const input1 = db.updateCircuitFragment(Xor[0], visited);
                const input2 = db.updateCircuitFragment(Xor[1], visited);
                db.circuit_info[i].energized = (input1 and !input2) or (input2 and !input1);
            },
            .Source => db.circuit_info[i].energized = true,
            .Conduit => |Conduit| {
                const input1 = db.updateCircuitFragment(Conduit[0], visited);
                const input2 = db.updateCircuitFragment(Conduit[1], visited);
                db.circuit_info[i].energized = (input1 or input2);
            },
            // TODO: Sockets may come before the plug they are connected to
            .Socket => |socket_opt| {
                if (socket_opt) |input| {
                    db.circuit_info[i].energized = db.updateCircuitFragment(input, visited);
                } else {
                    db.circuit_info[i].energized = false;
                }
            },
            .Plug => |Plug| {
                db.circuit_info[i].energized = db.updateCircuitFragment(Plug, visited);
            },
            .Switch => |_Switch| {
                db.circuit_info[i].energized = db.updateCircuitFragment(_Switch.source, visited);
            },
            .SwitchOutlet => |_Switch| {
                const is_energized = db.updateCircuitFragment(_Switch.source, visited);
                const _switch = db.circuit_info[_Switch.source].kind.Switch;
                const _outlet = db.circuit_info[i].kind.SwitchOutlet;
                // If the switch isn't energized, this outlet is not energized
                if (is_energized) db.circuit_info[i].energized = false;
                // If the switch is energized, check that it is outputting to this outlet
                db.circuit_info[i].energized = _outlet.which == _switch.state;
            },
            .Join => |Join| {
                db.circuit_info[i].energized = db.updateCircuitFragment(Join, visited);
            },
            .Outlet => |Outlet| {
                db.circuit_info[i].energized = db.updateCircuitFragment(Outlet, visited);
            },
        }
        return db.circuit_info[i].energized;
    }

    pub fn updateCircuit(db: *Database, alloc: std.mem.Allocator) !void {
        var visited = try alloc.alloc(bool, db.circuit_info.len);
        defer alloc.free(visited);
        std.mem.set(bool, visited, false);
        var i: usize = db.circuit_info.len - 1;
        while (i > 0) : (i -|= 1) {
            _ = db.updateCircuitFragment(i, visited);
            if (i == 0) break;
        }
    }

    // Entity functions
    pub fn getEntityID(database: *Database, coord: Coordinate) ?usize {
        for (database.entities) |entity, i| {
            if (!entity.coord.eq(coord)) continue;
            return i;
        }
        return null;
    }

    pub fn collectCoin(db: *Database, coord: Coordinate) void {
        const coin = db.getEntityID(coord) orelse return;
        db.entities[coin].kind = .Collected;
    }

    /// Remove a wire slice from the wires array. Invalidates handles returned from findWire
    pub fn deleteWire(database: *Database, wire: [2]usize) void {
        const w4 = @import("wasm4.zig");
        const wire_size = wire[1] - wire[0];
        if (wire[0] + wire_size == database.wire_count) {
            database.wire_count -= wire_size;
            return;
        }
        const wires_end = database.wires[wire[0] + wire_size .. database.wire_count];
        const new_end = database.wires[wire[0] .. database.wire_count - wire_size];
        w4.tracef("%d, %d, %d", wire_size, wires_end.len, new_end.len);
        std.mem.copy(Wire, new_end, wires_end);
        database.wire_count -= wire_size;
    }

    /// Retrieve the slice of the wire from findWire
    pub fn getWire(database: *Database, wire: [2]usize) []Wire {
        return database.wires[wire[0]..wire[1]];
    }

    /// Retrieve the slice of the wire from findWire
    pub fn addWire(database: *Database, wire: []Wire) void {
        const start = database.wire_count;
        const end = start + wire.len;
        std.mem.copy(Wire, database.wires[start..end], wire);
        database.wire_count += wire.len;
    }

    /// Find a wire within the limits of a given level
    pub fn findWire(database: *Database, level: Level, num: usize) ?[2]usize {
        const nw = Coord.fromWorld(level.world_x, level.world_y);
        const se = nw.add(.{ 20, 20 });
        var node_begin: ?usize = null;
        var wire_count: usize = 0;
        var i: usize = 0;
        while (i < database.wire_count) : (i += 1) {
            const wire = database.wires[i];
            switch (wire) {
                .Begin => |coord| {
                    if (!coord.within(nw, se)) continue;
                    node_begin = i;
                },
                .BeginPinned => |coord| {
                    if (!coord.within(nw, se)) continue;
                    node_begin = i;
                },
                .Point, .PointPinned => continue,
                .End => {
                    if (node_begin) |node| {
                        if (wire_count == num) {
                            return [2]usize{ node, i + 1 };
                        }
                        wire_count += 1;
                        node_begin = null;
                    }
                },
            }
        }
        return null;
    }

    pub fn getDoor(database: *Database, level: Level, num: usize) ?Entity {
        const nw = Coord.fromWorld(level.world_x, level.world_y);
        const se = nw.add(.{ 20, 20 });
        var count: usize = 0;
        for (database.entities) |entity| {
            if (!entity.coord.within(nw, se)) continue;
            if (entity.kind == .Door or entity.kind == .Trapdoor) {
                if (count == num) return entity;
                count += 1;
            }
        }
        return null;
    }

    pub fn getCoin(database: *Database, level: Level, num: usize) ?Entity {
        const nw = Coord.fromWorld(level.world_x, level.world_y);
        const se = nw.add(.{ 20, 20 });
        var count: usize = 0;
        for (database.entities) |entity| {
            if (!entity.coord.within(nw, se)) continue;
            if (entity.kind == .Coin) {
                if (count == num) return entity;
                count += 1;
            }
        }
        return null;
    }

    /// Returns the players spawn location.
    /// Assumes a spawn exists and that there is only one of them
    pub fn getSpawn(database: *Database) Entity {
        for (database.entities) |entity| {
            if (entity.kind == .Player) {
                return entity;
            }
        }
        @panic("No player spawn found! Invalid state");
    }
};

// All levels in the game. If two rooms are next to each other, they
// are assumed to be neighbors. Leaving the screen will load in the next
// level in that direction. The player is placed at the same position
// vertically, but on the opposite side of the screen horizontally. Vice versa
// for vertically moving between screens. The player will retain their momentum.
//
// When a wire crosses a screen boundary, it will coil up at the player's feet
// automatically. If one side of the wire is pinned, the wire will be let go of.
//
// Alternatively, the wire will be pinned outside of the level. If it isn't pinned,
// I will need to freeze it and move it in a snake like fashion. Or just leave the
// other level loaded.
// levels: []Level,
// An abstract representation of all circuits in game.
// abstract_circuit: []CircuitNode,

pub const NodeID = u8;

pub const CircuitNode = struct {
    energized: bool = false,
    kind: NodeKind,
    coord: Coordinate,

    pub fn read(reader: anytype) !CircuitNode {
        return CircuitNode{
            .coord = try Coordinate.read(reader),
            .kind = try NodeKind.read(reader),
        };
    }

    pub fn write(node: CircuitNode, writer: anytype) !void {
        try node.coord.write(writer);
        try node.kind.write(writer);
    }

    pub fn format(node: CircuitNode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        if (fmt.len != 0) @compileError("Unknown format character: '" ++ fmt ++ "'");
        return std.fmt.format(writer, "{} {c} {}", .{
            node.coord,
            if (node.energized) @as(u8, '1') else @as(u8, '0'),
            node.kind,
        });
    }
};

const NodeEnum = enum(u4) {
    And,
    Xor,
    Source,
    Conduit,
    Plug,
    Socket,
    Switch,
    SwitchOutlet,
    Join,
    Outlet,
};

pub const NodeKind = union(NodeEnum) {
    /// An And logic gate
    And: [2]NodeID,
    /// A Xor logic gate
    Xor: [2]NodeID,
    /// This node is a source of power
    Source,
    /// Connects multiple nodes
    Conduit: [2]NodeID,
    /// A "male" receptacle. Wires attached can provide power to
    /// a socket on the other end.
    Plug: NodeID,
    /// A "female" receptacle. Wires attached provide power from
    /// a plug on the other side.
    ///
    /// No visual difference from a plug.
    Socket: ?NodeID,
    /// A switch can be in one of five states, though only
    /// two apply to any one switch.
    /// Vertical = Off or Top/Bottom, depending on flow
    /// Horizontal =  Off or Left/Right, depending on flow
    /// Tee = Top/Bottom or Left/Right, depending on flow
    Switch: Switch,
    /// Interface between a switch and other components. Each one
    /// of these represents a possible outlet on a switch, and reads
    /// the state of the switch to determine if it is powered or not
    SwitchOutlet: SwitchOutlet,
    /// Connection between levels
    Join: NodeID,
    /// Used to identify entities that recieve power, like doors
    Outlet: NodeID,

    pub const Switch = struct {
        source: NodeID,
        state: u8,
    };
    pub const SwitchOutlet = struct {
        source: NodeID,
        which: u8,
    };

    pub fn read(reader: anytype) !NodeKind {
        var kind: NodeKind = undefined;
        const nodeEnum = @intToEnum(NodeEnum, try reader.readInt(u8, .Little));
        switch (nodeEnum) {
            .And => {
                kind = .{ .And = .{
                    try reader.readInt(NodeID, .Little),
                    try reader.readInt(NodeID, .Little),
                } };
            },
            .Xor => {
                kind = .{ .Xor = .{
                    try reader.readInt(NodeID, .Little),
                    try reader.readInt(NodeID, .Little),
                } };
            },
            .Source => kind = .Source,
            .Conduit => {
                kind = .{ .Conduit = .{
                    try reader.readInt(NodeID, .Little),
                    try reader.readInt(NodeID, .Little),
                } };
            },
            .Socket => {
                const socket = try reader.readInt(NodeID, .Little);
                if (socket == std.math.maxInt(NodeID)) {
                    kind = .{ .Socket = null };
                } else {
                    kind = .{ .Socket = socket };
                }
            },
            .Plug => {
                kind = .{ .Plug = try reader.readInt(NodeID, .Little) };
            },
            .Switch => {
                kind = .{ .Switch = .{
                    .source = try reader.readInt(NodeID, .Little),
                    .state = try reader.readInt(u8, .Little),
                } };
            },
            .SwitchOutlet => {
                kind = .{ .SwitchOutlet = .{
                    .source = try reader.readInt(NodeID, .Little),
                    .which = try reader.readInt(u8, .Little),
                } };
            },
            .Join => {
                kind = .{ .Join = try reader.readInt(NodeID, .Little) };
            },
            .Outlet => {
                kind = .{ .Outlet = try reader.readInt(NodeID, .Little) };
            },
        }
        return kind;
    }

    pub fn write(kind: NodeKind, writer: anytype) !void {
        try writer.writeInt(u8, @enumToInt(kind), .Little);
        switch (kind) {
            .And => |And| {
                try writer.writeInt(NodeID, And[0], .Little);
                try writer.writeInt(NodeID, And[1], .Little);
            },
            .Xor => |Xor| {
                try writer.writeInt(NodeID, Xor[0], .Little);
                try writer.writeInt(NodeID, Xor[1], .Little);
            },
            .Source => {},
            .Conduit => |Conduit| {
                try writer.writeInt(NodeID, Conduit[0], .Little);
                try writer.writeInt(NodeID, Conduit[1], .Little);
            },
            .Plug => |Plug| {
                try writer.writeInt(NodeID, Plug, .Little);
            },
            .Socket => |Socket| {
                const socket = Socket orelse std.math.maxInt(NodeID);
                try writer.writeInt(NodeID, socket, .Little);
            },
            .Switch => |_Switch| {
                try writer.writeInt(NodeID, _Switch.source, .Little);
                try writer.writeInt(u8, _Switch.state, .Little);
            },
            .SwitchOutlet => |_Switch| {
                try writer.writeInt(NodeID, _Switch.source, .Little);
                try writer.writeInt(u8, _Switch.which, .Little);
            },
            .Join => |Join| {
                try writer.writeInt(NodeID, Join, .Little);
            },
            .Outlet => |Outlet| {
                try writer.writeInt(NodeID, Outlet, .Little);
            },
        }
    }

    pub fn format(kind: NodeKind, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        if (fmt.len != 0) @compileError("Unknown format character: '" ++ fmt ++ "'");
        const name = @tagName(kind);
        return switch (kind) {
            .Conduit => |Conduit| std.fmt.format(writer, "{s} [{}, {}]", .{ name, Conduit[0], Conduit[1] }),
            .And => |And| std.fmt.format(writer, "{s} [{}, {}]", .{ name, And[0], And[1] }),
            .Xor => |Xor| std.fmt.format(writer, "{s} [{}, {}]", .{ name, Xor[0], Xor[1] }),
            .Source => std.fmt.format(writer, "{s}", .{name}),
            .Plug => |Plug| std.fmt.format(writer, "{s} [{}]", .{ name, Plug }),
            .Socket => |Socket| std.fmt.format(writer, "{s} [{?}]", .{ name, Socket }),
            .Switch => |_Switch| std.fmt.format(writer, "{s} <{}> [{}]", .{ name, _Switch.state, _Switch.source }),
            .SwitchOutlet => |_Switch| std.fmt.format(writer, "{s} <{}> [{}]", .{ name, _Switch.which, _Switch.source }),
            .Join => |Join| std.fmt.format(writer, "{s} [{}]", .{ name, Join }),
            .Outlet => |Outlet| std.fmt.format(writer, "{s} [{}]", .{ name, Outlet }),
        };
    }
};
