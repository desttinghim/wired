const std = @import("std");
const w4 = @import("wasm4.zig");
const assets = @import("assets");
const input = @import("input.zig");
const util = @import("util.zig");
const StackAllocator = @import("mem.zig").StackAllocator;
const scene = @import("scene.zig");

const Game = @import("game.zig");
const Menu = @import("menu.zig");
const SceneManager = scene.Manager(Context, &.{Menu, Game});

pub const Context = struct {
    scenes: SceneManager,
    alloc: std.mem.Allocator,
    time: usize,
};

fn showErr(msg: []const u8) noreturn {
    w4.traceNoF(msg);
    w4.traceNoF("ERROR. Aborting...");
    unreachable;
}

var sceneptr_heap: [64]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&sceneptr_heap);

var frameheap: [4096]u8 = undefined;
var ffba = std.heap.FixedBufferAllocator.init(&frameheap);

var heap: [4096]u8 = undefined;
var stack_allocator = StackAllocator.init(&heap);

var ctx : Context = undefined;

export fn start() void {
    ctx = Context {
        .scenes = SceneManager.init(&ctx, &stack_allocator, fba.allocator()),
        .alloc = ffba.allocator(),
        .time = 0,
    };
    // inline for (@typeInfo(SceneManager.Scene).Enum.fields) |field| {
    //     @compileLog(field.name);
    // }
    _ = ctx.scenes.push(.menu) catch |e| showErr(@errorName(e));
}

export fn update() void {
    ctx.scenes.tick() catch |e| showErr(@errorName(e));
    input.update();
    ctx.time += 1;
}
