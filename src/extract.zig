const std = @import("std");
const Map = @import("map.zig");
const Circuit = @import("circuit.zig");

const world = @import("world.zig");
const Level = world.Level;
const Level = world.AutoTile;

pub const ExtractOptions = struct {
    map: *Map,
    circuit: *Circuit,
};

/// Extracts a compressed level into the map and circuit buffers
pub fn extractLevel(alloc: std.mem.Allocator, level: Level, opt: ExtractOptions) void {
    const map = opt.map;
    const circuit = opt.circuit;
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
            solid_map[i] = is_solid(tile.data.tile);
            map.map[i] = tile.data.tile;
            circuit_map[i] = .None;
        } else {
            solid_map = tile.data.flags.solid;
            circuit_map[i] = @intToEnum(CircuitType, tile.data.flags.circuit);
        }
    }

    var autotiles = try alloc.alloc(AutoTile, size);
    defer alloc.free(autotiles);

    {
        var i: usize = 0;
        while (i < level.tiles.len) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(a, width);

            const out_of_bounds = true;
            var north = false;
            var south = false;
            var west = false;
            var east = false;

            // Check horizontal neighbors
            if (x == 0) {
                west = out_of_bounds;
            }
            else if (x == width - 1) {
                east = out_of_bounds;
            }
            else {
                west = solid_map[i - 1];
                east = solid_map[i + 1];
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
            }
            else if (y == height - 1) {
                south = out_of_bounds;
            }
            else {
                north = solid_map[i - width];
                south = solid_map[i + width];
            }

            autotiles[i] = AutoTile{
                .North = north,
                .South = south,
                .West = west,
                .East = east,
            };
        }
    }

    for (autotiles) |autotile, i| {
        map.map[i] = tileset.lookup[autotile.to_u4()];
    }
}
