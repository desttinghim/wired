const w4 = @import("wasm4.zig");
const std = @import("std");
const Map = @import("map.zig");
const Circuit = @import("circuit.zig");

const world = @import("world.zig");
const Level = world.Level;
const AutoTile = world.AutoTile;
const CircuitType = world.CircuitType;

pub const Options = struct {
    map: *Map,
    circuit: *Circuit,
    alloc: std.mem.Allocator,
    level: world.Level,
    tileset: world.AutoTileset,
};

fn is_solid(tile: u7) bool {
    return tile != 0 and tile != 1;
}

/// Extracts a compressed level into the map and circuit buffers
pub fn extractLevel(opt: Options) !void {
    const map = opt.map;
    const circuit = opt.circuit;
    const alloc = opt.alloc;
    const level = opt.level;
    const tileset = opt.tileset;

    const width = level.width;
    const height = @divExact(@intCast(u16, level.tiles.len), level.width);
    const size = level.tiles.len;

    map.map_size = .{ level.width, height };
    circuit.map_size = .{ level.width, height };

    var solid_map = try alloc.alloc(bool, size);
    defer alloc.free(solid_map);

    var circuit_map = try alloc.alloc(CircuitType, size);
    defer alloc.free(circuit_map);

    for (level.tiles) |tile, i| {
        if (tile.is_tile) {
            // solid_map[i] = is_solid(tile.data.tile);
            map.tiles[i] = tile.data.tile;
            circuit_map[i] = .None;
        } else {
            solid_map[i] = tile.data.flags.solid;
            circuit_map[i] = @intToEnum(CircuitType, tile.data.flags.circuit);
        }
    }

    var autotiles = try alloc.alloc(?AutoTile, size);
    defer alloc.free(autotiles);

    {
        var i: usize = 0;
        while (i < level.tiles.len) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (!solid_map[i]) {
                autotiles[i] = null;
                continue;
            }

            const out_of_bounds = true;
            var north = false;
            var south = false;
            var west = false;
            var east = false;

            // Check horizontal neighbors
            if (x == 0) {
                west = out_of_bounds;
                east = solid_map[i + 1];
            } else if (x == width - 1) {
                west = solid_map[i - 1];
                east = out_of_bounds;
            } else {
                west = solid_map[i - 1];
                east = solid_map[i + 1];
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
                south = solid_map[i + stride];
            } else if (y == height - 1) {
                north = solid_map[i - stride];
                south = out_of_bounds;
            } else {
                north = solid_map[i - stride];
                south = solid_map[i + stride];
            }

            autotiles[i] = AutoTile{
                .North = north,
                .South = south,
                .West = west,
                .East = east,
            };
        }
    }

    for (autotiles) |autotile_opt, i| {
        if (autotile_opt) |autotile| {
            const li = autotile.to_u4();
            const tile = tileset.lookup[li];
            map.tiles[i] = tile;
        }
    }
}
