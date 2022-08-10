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
    db: world.Database,
};

fn is_solid(tile: u7) bool {
    return tile != 0 and tile != 1;
}

/// Extracts a compressed level into the map and circuit buffers
pub fn extractLevel(opt: Options) !void {
    w4.tracef("extract begin");
    const map = opt.map;
    const circuit = opt.circuit;
    const alloc = opt.alloc;
    const level = opt.level;
    const tileset = opt.tileset;
    const db = opt.db;

    const tiles = level.tiles orelse return error.NullTiles;

    const width = level.width;
    w4.tracef("div exact %d, %d", tiles.len, level.width);
    const height = @divExact(@intCast(u16, tiles.len), level.width);
    const size = tiles.len;

    map.map_size = .{ level.width, height };
    circuit.map_size = .{ level.width, height };

    w4.tracef("%d", @src().line);
    var auto_map = try alloc.alloc(world.SolidType, size);
    defer alloc.free(auto_map);

    var circuit_map = try alloc.alloc(CircuitType, size);
    defer alloc.free(circuit_map);

    w4.tracef("reading tiles");
    for (tiles) |data, i| {
        switch (data) {
            .tile => |tile| {
                auto_map[i] = .Empty;
                map.tiles[i] = tile;
                circuit_map[i] = .None;
            },
            .flags => |flags| {
                auto_map[i] = flags.solid;
                circuit_map[i] = flags.circuit;
            },
        }
    }

    var autotiles = try alloc.alloc(?AutoTile, size);
    defer alloc.free(autotiles);

    w4.tracef("autotile walls");
    // Auto generate walls
    {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (auto_map[i] == .Empty) {
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
                east = auto_map[i + 1] == .Solid;
            } else if (x == width - 1) {
                west = auto_map[i - 1] == .Solid;
                east = out_of_bounds;
            } else {
                west = auto_map[i - 1] == .Solid;
                east = auto_map[i + 1] == .Solid;
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
                south = auto_map[i + stride] == .Solid;
            } else if (y == height - 1) {
                north = auto_map[i - stride] == .Solid;
                south = out_of_bounds;
            } else {
                north = auto_map[i - stride] == .Solid;
                south = auto_map[i + stride] == .Solid;
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

    w4.tracef("autotile circuit");
    // Auto generate circuit
    // Re-use autotiles to save memory
    {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (circuit_map[i] == .Source) {
                const levelc = world.Coordinate.fromVec2(.{ @intCast(i32, x), @intCast(i32, y) });
                const coord = world.Coordinate.fromWorld(level.world_x, level.world_y).addC(levelc);
                w4.tracef("[extract] source (%d, %d)", coord.val[0], coord.val[1]);
                if (db.getNodeID(coord)) |node_id| {
                    circuit.addSource(.{
                        .coord = levelc,
                        .node_id = node_id,
                    });
                    w4.tracef("[extract] node id (%d)", node_id);
                }
            }

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
                .Conduit,
                .Conduit_Vertical,
                .Conduit_Horizontal,
                .Source,
                .Join,
                => opt.conduit.find(autotile),
                .Switch_On => opt.switch_on.find(autotile),
                .Switch_Off => opt.switch_off.find(autotile),
                .Plug, .Socket => opt.plug.find(autotile),
                .And => world.Tiles.LogicAnd,
                .Xor => world.Tiles.LogicXor,
                .Diode => world.Tiles.LogicDiode,
                .None, .Outlet => 0,
            };
            circuit.map[i] = tile;
        }
    }
    w4.tracef("extract end");
}
