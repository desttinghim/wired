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

pub const Level = struct {
    world_x: i8,
    world_y: i8,
    width: u16,
    size: u16,
    entity_count: u16,
    tiles: ?[]TileData,
    entities: ?[]Entity = null,

    pub fn init(x: u8, y: u8, width: u16, buf: []TileData, entities: []Entity) Level {
        return Level{
            .world_x = x,
            .world_y = y,
            .width = width,
            .size = buf.len,
            .entity_count = entities.len,
            .tiles = buf,
            .entities = entities,
        };
    }

    pub fn calculateSize(level: Level) !usize {
        const tiles = level.tiles orelse return error.NullTiles;
        const entities = level.entities orelse return error.NullEntities;
        return @sizeOf(i8) + // world_x
            @sizeOf(i8) + // world_y
            @sizeOf(u16) + // width
            @sizeOf(u16) + // size
            @sizeOf(u16) + // entity_count
            tiles.len + //
            entities.len * 5;
    }

    pub fn write(level: Level, writer: anytype) !void {
        var tiles = level.tiles orelse return error.NullTiles;
        var entities = level.entities orelse return error.NullEntities;
        try writer.writeInt(i8, level.world_x, .Little);
        try writer.writeInt(i8, level.world_y, .Little);
        try writer.writeInt(u16, level.width, .Little);
        try writer.writeInt(u16, level.size, .Little);
        try writer.writeInt(u16, level.entity_count, .Little);

        for (tiles) |tile| {
            try writer.writeByte(tile.toByte());
        }

        for (entities) |entity| {
            try entity.write(writer);
        }
    }

    pub fn read(reader: anytype) !Level {
        return Level{
            .world_x = try reader.readInt(i8, .Little),
            .world_y = try reader.readInt(i8, .Little),
            .width = try reader.readInt(u16, .Little),
            .size = try reader.readInt(u16, .Little),
            .entity_count = try reader.readInt(u16, .Little),
            .tiles = null,
            .entities = null,
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

    pub fn readEntities(level: *Level, reader: anytype, buf: []Entity) !void {
        std.debug.assert(buf.len >= level.entity_count);
        level.entities = buf;
        var i: usize = 0;
        while (i < level.entity_count) : (i += 1) {
            buf[i] = try Entity.read(reader);
        }
    }

    pub fn getSpawn(level: *Level) ?[2]i16 {
        std.debug.assert(level.entities != null);
        for (level.entities.?) |entity| {
            if (entity.kind == .Player) {
                return [2]i16{ entity.x, entity.y };
            }
        }
        return null;
    }

    pub fn getWire(level: *Level, num: usize) ?[2]Entity {
        std.debug.assert(level.entities != null);
        var node_begin: ?Entity = null;
        var wire_count: usize = 0;
        for (level.entities.?) |entity| {
            if (entity.kind == .WireNode or entity.kind == .WireAnchor) {
                node_begin = entity;
            } else if (entity.kind == .WireEndNode or entity.kind == .WireEndAnchor) {
                if (node_begin) |begin| {
                    if (wire_count == num) return [2]Entity{ begin, entity };
                }
                wire_count += 1;
            }
        }
        return null;
    }

    pub fn getDoor(level: *Level, num: usize) ?Entity {
        std.debug.assert(level.entities != null);
        var count: usize = 0;
        for (level.entities.?) |entity| {
            if (entity.kind == .Door or entity.kind == .Trapdoor) {
                if (count == num) return entity;
                count += 1;
            }
        }
        return null;
    }

    pub fn getCoin(level: *Level, num: usize) ?Entity {
        std.debug.assert(level.entities != null);
        var count: usize = 0;
        for (level.entities.?) |entity| {
            if (entity.kind == .Coin) {
                if (count == num) return entity;
                count += 1;
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
    WireNode,
    WireAnchor,
    WireEndNode,
    WireEndAnchor,
    Door,
    Trapdoor,
};

pub const Entity = struct {
    kind: EntityKind,
    x: i16,
    y: i16,

    pub fn calculateSize() usize {
        return @sizeOf(u8) + // kind
            @sizeOf(i16) + // x
            @sizeOf(i16); // y
    }

    pub fn write(entity: Entity, writer: anytype) !void {
        try writer.writeInt(u8, @enumToInt(entity.kind), .Little);
        try writer.writeInt(i16, entity.x, .Little);
        try writer.writeInt(i16, entity.y, .Little);
    }

    pub fn read(reader: anytype) !Entity {
        return Entity{
            .kind = @intToEnum(EntityKind, try reader.readInt(u8, .Little)),
            .x = try reader.readInt(i16, .Little),
            .y = try reader.readInt(i16, .Little),
        };
    }
};

// Data format:
// | node count | level count |
// | node headers...          |
// | level headers...         |
// | node data...             |
// | level data...            |

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

pub fn write(level_headers: []LevelHeader, writer: anytype) !void {
    // Write number of levels
    try writer.writeInt(u16, @intCast(u16, level_headers.len), .Little);

    // Write headers
    for (level_headers) |lvl_header| {
        try lvl_header.write(writer);
    }
}

pub fn read(alloc: std.mem.Allocator, reader: anytype) ![]LevelHeader {
    // read number of levels
    const level_count = try reader.readInt(u16, .Little);

    var level_headers = try alloc.alloc(LevelHeader, level_count);
    // read headers
    for (level_headers) |_, i| {
        level_headers[i] = try LevelHeader.read(reader);
    }

    return level_headers;
}

const Cursor = std.io.FixedBufferStream([]const u8);
pub const Database = struct {
    cursor: Cursor,
    level_info: []LevelHeader,
    level_data_begin: usize,

    const world_data = @embedFile(@import("world_data").path);

    pub fn init(alloc: std.mem.Allocator) !Database {
        var cursor = Cursor{
            .pos = 0,
            .buffer = world_data,
        };

        var reader = cursor.reader();

        var levels = try read(alloc, reader);
        var level_data_begin = @intCast(usize, try cursor.getPos());

        return Database{
            .cursor = cursor,
            .level_info = levels,
            .level_data_begin = level_data_begin,
        };
    }

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

        var entity_buf = try alloc.alloc(Entity, level_info.entity_count);
        try level_info.readEntities(reader, entity_buf);

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

const NodeID = u16;

pub const CircuitNode = struct {
    energized: bool = false,
    kind: NodeKind,
};

pub const NodeKind = union(enum) {
    /// An And logic gate
    And: [2]NodeID,
    /// A Xor logic gate
    Xor: [2]NodeID,
    /// This node is a source of power
    Source,
    /// Connects multiple nodes
    Conduit: [2]NodeID,
    /// This node represents a physical plug in the game world. The
    /// NodeID points to another plug, if connected
    Plug: ?NodeID,
    /// A switch can be in one of five states, though only
    /// two apply to any one switch.
    /// Vertical = Off or Top/Bottom, depending on flow
    /// Horizontal =  Off or Left/Right, depending on flow
    /// Tee = Top/Bottom or Left/Right, depending on flow
    Switch: enum { Off, Bottom, Top, Left, Right },
    Join: NodeID,
    Outlet: NodeID,
};
