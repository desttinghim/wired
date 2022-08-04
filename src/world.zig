//! Data types used for storing world info

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

pub const TileData = packed union {
    tile: u7,
    flags: packed struct {
        solid: bool,
        circuit: u4,
    },
};

pub const TileStore = packed struct {
    is_tile: bool,
    data: TileData,
};

pub const LevelHeader = struct {
    world_x: u8,
    world_y: u8,
    width: u16,
    size:  u16,
};

pub const Level = struct {
    world_x: u8,
    world_y: u8,
    width: u16,
    tiles: []TileStore,
};

// AutoTile algorithm datatypes
pub const AutoTile = packed struct {
    North: bool,
    West: bool,
    South: bool,
    East: bool,

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
