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

pub const TileData = union {
    tile: u7,
    flags: struct {
        solid: bool,
        circuit: u4,
    },
};

pub const TileStore = struct {
    is_tile: bool,
    data: TileData,

    pub fn toByte(store: TileStore) u8 {
        if (store.is_tile) {
            return 1 | (store.data.tile << 1);
        } else {
            return (@intCast(u7, @boolToInt(store.data.flags.solid)) << 1) | (@intCast(u7, store.data.flags.circuit) << 2);
        }
    }

    pub fn fromByte(byte: u8) TileStore {
        const is_tile = (1 & byte) > 0;
        if (is_tile) {
            const tile = @intCast(u7, (~@as(u7, 1) & byte) >> 1);
            return TileStore{
                .is_tile = true,
                .data = .{ .tile = tile },
            };
        } else {
            const is_solid = (0b0000_0010 & byte) > 0;
            const circuit = @intCast(u4, (0b0011_1100 & byte) >> 2);
            return TileStore{
                .is_tile = false,
                .data = .{ .flags = .{
                    .solid = is_solid,
                    .circuit = circuit,
                } },
            };
        }
    }
};

pub const LevelHeader = struct {
    world_x: u8,
    world_y: u8,
    width: u16,
    size: u16,

    pub fn write(header: LevelHeader, writer: anytype) !void {
        try writer.writeInt(u8, header.world_x, .Big);
        try writer.writeInt(u8, header.world_y, .Big);
        try writer.writeInt(u16, header.width, .Big);
        try writer.writeInt(u16, header.size, .Big);
    }

    pub fn read(reader: anytype) !LevelHeader {
        return LevelHeader{
            .world_x = try reader.readInt(u8, .Big),
            .world_y = try reader.readInt(u8, .Big),
            .width = try reader.readInt(u16, .Big),
            .size = try reader.readInt(u16, .Big),
        };
    }

    pub fn readTiles(header: LevelHeader, reader: anytype, buf: []TileStore) !void {
        std.debug.assert(buf.len > header.size);
        var i: usize = 0;
        while (i < header.size) : (i += 1) {
            buf[i] = TileStore.fromByte(try reader.readByte());
        }
    }
};

pub const Level = struct {
    world_x: u8,
    world_y: u8,
    width: u16,
    tiles: []TileStore,

    pub fn init(header: LevelHeader, buf: []TileStore) Level {
        return Level {
            .world_x = header.world_x,
            .world_y = header.world_y,
            .width = header.width,
            .tiles = buf[0..header.size],
        };
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
    lookup: [16]u8,
};
