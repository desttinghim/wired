//! Data types used for storing world info

const std = @import("std");

// Tile Storage Types
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

    pub fn write(level: Level, writer: anytype) !void {
        var tiles = level.tiles orelse return error.NullTiles;
        try writer.writeInt(u8, level.world_x, .Big);
        try writer.writeInt(u8, level.world_y, .Big);
        try writer.writeInt(u16, level.width, .Big);
        try writer.writeInt(u16, level.size, .Big);
        for (tiles) |tile| {
            try writer.writeByte(tile.toByte());
        }
    }

    pub fn read(reader: anytype) !Level {
        return Level{
            .world_x = try reader.readInt(u8, .Big),
            .world_y = try reader.readInt(u8, .Big),
            .width = try reader.readInt(u16, .Big),
            .size = try reader.readInt(u16, .Big),
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
    lookup: []const u8,
    kind: enum {
        Cardinal,
        Switches,
        Full,
    },
    default: u8,

    pub fn initFull(table: []const u8) AutoTileset {
        std.debug.assert(table.len == 16);
        return AutoTileset{
            .lookup = table,
            .kind = .Full,
            .default = 0,
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

    pub fn find(tileset: AutoTileset, autotile: AutoTile) u8 {
        const autoint = autotile.to_u4();
        switch (tileset.kind) {
            .Full => return tileset.lookup[autoint],
            .Cardinal => switch (autoint) {
                0b0001 => return tileset.lookup[0],
                0b0010 => return tileset.lookup[1],
                0b0100 => return tileset.lookup[2],
                0b1000 => return tileset.lookup[3],
                else => return tileset.default,
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
