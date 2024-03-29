const std = @import("std");
const w4 = @import("wasm4.zig");
const assets = @import("assets");
const input = @import("input.zig");
const util = @import("util.zig");

const game = @import("game.zig");
const menu = @import("menu.zig");

pub const State = enum {
    Menu,
    Game,
};

fn showErr(msg: []const u8) noreturn {
    w4.traceNoF(msg);
    unreachable;
}

var time: usize = 0;
var state: State = .Menu;

export fn start() void {
    menu.start();
}

export fn update() void {
    const newState = switch (state) {
        .Menu => menu.update(),
        .Game => game.update(time) catch |e| switch (e) {
            error.Overflow => showErr(@errorName(e)),
            error.OutOfBounds => showErr(@errorName(e)),
            error.EndOfStream => showErr(@errorName(e)),
            error.OutOfMemory => showErr(@errorName(e)),
            error.InvalidLevel => showErr(@errorName(e)),
            error.NullTiles => showErr(@errorName(e)),
            error.NoLevelDown => showErr(@errorName(e)),
            error.NoLevelUp => showErr(@errorName(e)),
            error.NoLevelLeft => showErr(@errorName(e)),
            error.NoLevelRight => showErr(@errorName(e)),
            error.MissingEnds => showErr(@errorName(e)),
        },
    };
    if (state != newState) {
        state = newState;
        switch (newState) {
            .Menu => menu.start(),
            .Game => game.start() catch |e| switch (e) {
                error.Overflow => showErr(@errorName(e)),
                error.OutOfBounds => showErr(@errorName(e)),
                error.EndOfStream => showErr(@errorName(e)),
                error.OutOfMemory => showErr(@errorName(e)),
                error.NullTiles => showErr(@errorName(e)),
                error.SpawnOutOfBounds => showErr(@errorName(e)),
                error.InvalidLevel => showErr(@errorName(e)),
                error.MissingEnds => showErr(@errorName(e)),
            },
        }
    }
    input.update();
    time += 1;
}
