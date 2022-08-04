const TileValue = union(enum) {
    Tile,
    Size,
};

// 2 Modes
// Tile:
//      0b0TTT_TTTT
// 2 layer:
//      0b1XXS_CCCC
// T = Tile number, 0-127
// X = Reserved
// S = Solid
// C = Circuit

/// 0bDCBA
/// +---+---+
/// | A | B |
/// +---+---+
/// | C | D |
/// +---+---+
/// NE 0b0001
/// NW 0b0010
/// SW 0b0100
/// SE 0b1000
/// 0 -
const AutoTileRule = struct {
    A: u8,
    B: u8,
    lookup: [16]u8,
};

/// Reference enum mapping numbers to names
/// X = Exclude (only one side present)
/// N = North
/// W = West
/// E = East
/// S = South
/// H = Horizontal
/// V = Vertical
pub const Side = enum(u4) {
    X_ALL = 0,
    N = 1,
    W = 2,
    NW = 3,
    E = 4,
    NE = 5,
    H_BEAM = 6,
    X_S = 7,
    S = 8,
    V_BEAM = 9,
    SW = 10,
    X_E = 11,
    SE = 12,
    X_W = 13,
    X_N = 14,
    ALL =  15,
};

const AutoTiling = struct {
    /// Bitmask to tile mapping
    const AutoTileLookup = [16]u8;

    tables: []AutoTileLookup,
    /// Use value A for out of bounds
    outOfBounds: u8,
    values: []u8,
};
