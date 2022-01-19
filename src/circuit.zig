const std = @import("std");
const assets = @import("assets");

fn is_circuit(tile: u8) bool {
    return is_plug(tile) or is_conduit(tile) or is_switch(tile);
}

fn is_plug(tile: u8) bool {
    return (tile >= 149 and tile <= 153) or tile == 147;
}

fn is_conduit(tile: u8) bool {
    return (tile >= 128 and tile < 132) or
        (tile >= 144 and tile < 148) or
        (tile >= 160 and tile < 164) or
        (tile >= 176 and tile < 180);
}

fn is_switch(tile: u8) bool {
    return tile >= 134 and tile < 136;
}

const Side = enum(u2) { up, right, down, left };
fn side(s: Side) u2 {
    return @enumToInt(s);
}

const Current = [4]bool;
/// Returns sides that can conduct current
fn get_inputs(tile: u8) Current {
    return switch (tile) {
        // Corners
        128 => .{ false, true, true, false },
        129 => .{ false, false, true, true },
        144 => .{ true, false, false, true },
        145 => .{ true, true, false, false },
        // Straight
        130 => .{ false, true, false, true },
        131 => .{ true, false, true, false },
        // Cross
        146 => .{ false, false, false, false },
        147 => .{ true, true, true, true },
        // Ends
        160 => .{ false, false, true, false },
        161 => .{ false, true, false, false },
        162 => .{ true, false, false, false },
        163 => .{ false, false, false, true },
        // Tees
        176 => .{ false, true, true, true },
        177 => .{ true, true, false, true },
        178 => .{ true, false, true, true },
        179 => .{ true, true, true, false },
        // Plugs
        149 => .{ false, false, true, false },
        150 => .{ true, false, false, false },
        151 => .{ false, false, false, true },
        152 => .{ false, true, false, false },
        // Closed switch
        134 => .{ true, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Plugs = [4]bool;
/// Returns sides where wires may be plugged
fn get_plugs(tile: u8) Plugs {
    return switch (tile) {
        // Plugs
        149 => .{ true, false, false, false },
        150 => .{ false, false, true, false },
        151 => .{ false, true, false, false },
        152 => .{ false, false, false, true },
        // Cross
        146 => .{ true, true, true, true },
        else => .{ false, false, false, false },
    };
}

const Signals = [4]bool;
/// Returns sides where a signal may be sent
fn get_signals(tile: u8) Signals {
    return switch (tile) {
        // Ends
        160 => .{ true, true, false, true },
        161 => .{ true, false, true, true },
        162 => .{ false, true, true, true },
        163 => .{ true, true, true, false },
        // Switches
        134 => .{ true, false, true, false },
        135 => .{ true, false, true, false },
        else => .{ false, false, false, false },
    };
}

const Vec2 = std.meta.Vector(2, i32);
const Cell = Vec2;
fn dir(s: Side) Cell {
    return switch (s) {
        .up => Vec2{ 0, -1 },
        .down => Vec2{ 0, 1 },
        .left => Vec2{ -1, 0 },
        .right => Vec2{ 1, 0 },
    };
}

fn get_cell(c: Cell) ?u8 {
    if (c[0] < 0 or c[0] >= 20 or c[1] >= 20 or c[1] < 0) return null;
    const i = @intCast(usize, (c[0] % 20) + (c[1] * 20));
    return assets.conduit[i];
}

fn index2cell(i: usize) Cell {
    return Vec2{ i % 20, @divTrunc(i, 20) };
}

pub const Circuit = struct {
    switches: std.BoundedArray(8, cell),
    plugs: std.BoundedArray(8, cell),
    enabled: bool = false,
};

pub fn createCircuitChunks() void {
    var items = std.BoundedArray(100, u8).init(0);
    for (assets.conduit) |tile, i| {
        if (is_circuit(tile)) items.append(index2cell(i));
    }
    for (items.slice()) |cell| {
        // TODO: iterate over the cells and create components
    }
}

var circuits = std.BoundedArray(20, Circuit).init(0);
pub fn toggleSwitch(cell: Cell) void {
    for (circuits) |circuit| {
        for (circuit.switches) |switchCell| {
            if (switchCell == cell) {
                // TODO: do a search and disable circuit if a source is not found
            }
        }
    }
}
