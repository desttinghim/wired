const std = @import("std");
const w4 = @import("wasm4.zig");
const assets = @import("assets");
const input = @import("input.zig");
const util = @import("util.zig");
const StackAllocator = @import("mem.zig").StackAllocator;

const game = @import("game.zig");
const Menu = @import("menu.zig");

pub const State = enum {
    Menu,
    Game,
};

fn showErr(msg: []const u8) noreturn {
    w4.traceNoF(msg);
    unreachable;
}

var heap: [4096]u8 = undefined;
var stack_allocator = StackAllocator.init(&heap);
var allocator: std.mem.Allocator = undefined;
var time: usize = 0;
var state: State = .Menu;

var menu: *Menu = undefined;

export fn start() void {
    allocator = stack_allocator.allocator();
    menu = allocator.create(Menu) catch {
        w4.trace("couldn't allocate", .{});
        @panic("couldn't allocate");
    };
    menu.* = Menu.init();
}

export fn update() void {
    const newState = switch (state) {
        .Menu => menu.update(),
        .Game => game.update(time) catch |e| switch (e) {
            error.Overflow => showErr(@errorName(e)),
            error.OutOfBounds => showErr(@errorName(e)),
            // error.IndexOutOfBounds => showErr(@errorName(e)),
        },
    };
    if (state != newState) {
        state = newState;
        switch (newState) {
            .Menu => {
                menu = allocator.create(Menu) catch @panic("couldn't allocate");
                menu.* = Menu.init();
            },
            .Game => game.start() catch |e| switch (e) {
                error.Overflow => showErr(@errorName(e)),
                error.OutOfBounds => showErr(@errorName(e)),
                // error.IndexOutOfBounds => showErr(@errorName(e)),
            },
        }
    }
    input.update();
    time += 1;
}
