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
    const height = @divExact(@as(u16, @intCast(tiles.len)), level.width);
    const size = tiles.len;

    map.map_size = .{ level.width, height };
    circuit.map_size = .{ level.width, height };

    w4.tracef("%d", @src().line);
    var auto_map = try alloc.alloc(world.SolidType, size);
    defer alloc.free(auto_map);

    var circuit_map = try alloc.alloc(CircuitType, size);
    defer alloc.free(circuit_map);

    w4.tracef("reading tiles");
    for (tiles, 0..) |data, i| {
        switch (data) {
            .tile => |tile| {
                w4.tracef("[extract tile] [%d] %d", i, tile);
                const is_solid = world.Tiles.is_solid(tile);
                const is_oneway = world.Tiles.is_solid(tile);
                auto_map[i] = solid_type: {
                    if (is_solid) break :solid_type .Solid;
                    if (is_oneway) break :solid_type .Oneway;
                    break :solid_type .Empty;
                };
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

            w4.tracef("[extract] %d (%d, %d)", @intFromEnum(auto_map[i]), x, y);
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

    for (autotiles, 0..) |autotile_opt, i| {
        if (autotile_opt) |autotile| {
            const tile = switch (auto_map[i]) {
                .Solid => tileset.find(autotile),
                .Oneway => world.Tiles.OneWayMiddle,
                .Empty => 0,
            };
            map.tiles[i] = tile;
        }
    }

    var autocircuit = try alloc.alloc(?AutoTile, size);
    defer alloc.free(autocircuit);

    w4.tracef("autotile circuit");
    // Auto generate circuit
    {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            const x = @mod(i, width);
            const y = @divTrunc(i, width);
            const stride = width;

            if (circuit_map[i] == .Source) {
                const levelc = world.Coordinate.fromVec2(.{ @as(i32, @intCast(x)), @as(i32, @intCast(y)) });
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
                autocircuit[i] = null;
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
                east = circuit_map[i + 1] != .None and circuit_map[i + 1] != .Conduit_Vertical;
            } else if (x == width - 1) {
                west = circuit_map[i - 1] != .None and circuit_map[i - 1] != .Conduit_Vertical;
                east = out_of_bounds;
            } else {
                west = circuit_map[i - 1] != .None and circuit_map[i - 1] != .Conduit_Vertical;
                east = circuit_map[i + 1] != .None and circuit_map[i + 1] != .Conduit_Vertical;
            }

            // Check vertical neighbours
            if (y == 0) {
                north = out_of_bounds;
                south = circuit_map[i + stride] != .None and circuit_map[i + stride] != .Conduit_Horizontal;
            } else if (y == height - 1) {
                north = circuit_map[i - stride] != .None and circuit_map[i - stride] != .Conduit_Horizontal;
                south = out_of_bounds;
            } else {
                north = circuit_map[i - stride] != .None and circuit_map[i - stride] != .Conduit_Horizontal;
                south = circuit_map[i + stride] != .None and circuit_map[i + stride] != .Conduit_Horizontal;
            }

            autocircuit[i] = AutoTile{
                .North = north,
                .South = south,
                .West = west,
                .East = east,
            };
        }
    }

    for (autocircuit, 0..) |autotile_opt, i| {
        if (autotile_opt) |autotile| {
            const tile = switch (circuit_map[i]) {
                .Conduit,
                .Source,
                .Join,
                => opt.conduit.find(autotile),
                .Conduit_Vertical => opt.conduit.find(.{ .North = true, .South = true, .West = false, .East = false }),
                .Conduit_Horizontal => opt.conduit.find(.{ .North = false, .South = false, .West = true, .East = true }),
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
