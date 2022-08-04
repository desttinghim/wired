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

pub const TileData = union(enum) {
    tile: u7,
    flags: struct {
        solid: bool,
        circuit: u4,
    },

    pub fn toByte(data: TileData) u8 {
        switch (data) {
            .tile => |int| return 1 | (int << 1),
            .flags => |flags| return (@intCast(u7, @boolToInt(flags.solid)) << 1) | (@intCast(u7, flags.circuit) << 2),
        }
    }

    pub fn fromByte(byte: u8) TileData {
        const is_tile = (1 & byte) > 0;
        if (is_tile) {
            const tile = @intCast(u7, (~@as(u7, 1) & byte) >> 1);
            return TileData{ .tile = tile };
        } else {
            const is_solid = (0b0000_0010 & byte) > 0;
            const circuit = @intCast(u4, (0b0011_1100 & byte) >> 2);
            return TileData{ .flags = .{
                .solid = is_solid,
                .circuit = circuit,
            } };
        }
    }
};

pub const Level = struct {
    world_x: u8,
    world_y: u8,
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

    pub fn write(level: Level, writer: anytype) !void {
        var tiles = level.tiles orelse return error.NullTiles;
        var entities = level.entities orelse return error.NullEntities;
        try writer.writeInt(u8, level.world_x, .Little);
        try writer.writeInt(u8, level.world_y, .Little);
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
            .world_x = try reader.readInt(u8, .Little),
            .world_y = try reader.readInt(u8, .Little),
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
