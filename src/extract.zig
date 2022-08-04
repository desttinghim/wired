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
    conduit: world.AutoTileset,
    plug: world.AutoTileset,
    switch_on: world.AutoTileset,
    switch_off: world.AutoTileset,
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

    const tiles = level.tiles orelse return error.NullTiles;

    const width = level.width;
    const height = @divExact(@intCast(u16, tiles.len), level.width);
    const size = tiles.len;

    map.map_size = .{ level.width, height };
    circuit.map_size = .{ level.width, height };

    var auto_map = try alloc.alloc(bool, size);
    defer alloc.free(auto_map);

    var circuit_map = try alloc.alloc(CircuitType, size);
    defer alloc.free(circuit_map);

    for (tiles) |data, i| {
        switch (data) {
            .tile => |tile| {
                auto_map[i] = false;
                map.tiles[i] = tile;
                circuit_map[i] = .None;
            },
            .flags => |flags| {
                auto_map[i] = flags.solid;
                circuit_map[i] = @intToEnum(CircuitType, flags.circuit);
            },
        }
    }

    var autotiles = try alloc.alloc(?AutoTile, size);
    defer alloc.free(autotiles);

    // Auto generate walls
    {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (!auto_map[i]) {
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
                east = auto_map[i + 1];
            } else if (x == width - 1) {
                west = auto_map[i - 1];
                east = out_of_bounds;
            } else {
                west = auto_map[i - 1];
                east = auto_map[i + 1];
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
                south = auto_map[i + stride];
            } else if (y == height - 1) {
                north = auto_map[i - stride];
                south = out_of_bounds;
            } else {
                north = auto_map[i - stride];
                south = auto_map[i + stride];
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
            const tile = tileset.find(autotile);
            map.tiles[i] = tile;
        }
    }

    // Auto generate circuit
    // Re-use autotiles to save memory
    {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (circuit_map[i] == .None) {
                autotiles[i] = null;
                continue;
            }

            const out_of_bounds = switch (circuit_map[i]) {
                .Join, .Source => true,
                else => false,
            };
            var north = false;
            var south = false;
            var west = false;
            var east = false;

            // Check horizontal neighbors
            if (x == 0) {
                west = out_of_bounds;
                east = circuit_map[i + 1] != .None;
            } else if (x == width - 1) {
                west = circuit_map[i - 1] != .None;
                east = out_of_bounds;
            } else {
                west = circuit_map[i - 1] != .None;
                east = circuit_map[i + 1] != .None;
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
                south = circuit_map[i + stride] != .None;
            } else if (y == height - 1) {
                north = circuit_map[i - stride] != .None;
                south = out_of_bounds;
            } else {
                north = circuit_map[i - stride] != .None;
                south = circuit_map[i + stride] != .None;
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
            const tile = switch (circuit_map[i]) {
                .Conduit, .Source, .Join => opt.conduit.find(autotile),
                .Switch_On => opt.switch_on.find(autotile),
                .Switch_Off => opt.switch_off.find(autotile),
                .Plug => opt.plug.find(autotile),
                .And => 60,
                .Xor => 62,
                else => 0,
            };
            circuit.map[i] = tile;
        }
    }
}
