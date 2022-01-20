//! Stolen from pfgithub's wasm4-zig repo
//! https://github.com/pfgithub/wasm4-zig

const w4 = @This();
const std = @import("std");

/// PLATFORM CONSTANTS
pub const CANVAS_SIZE = 160;

/// Helpers
pub const Vec2 = @import("std").meta.Vector(2, i32);
pub const x = 0;
pub const y = 1;

pub fn texLen(size: Vec2) usize {
    return @intCast(usize, std.math.divCeil(i32, size[x] * size[y] * 2, 8) catch unreachable);
}

pub const Mbl = enum { mut, cons };
pub fn Tex(comptime mbl: Mbl) type {
    return struct {
        // oh that's really annoying…
        // ideally there would be a way to have a readonly Tex and a mutable Tex
        // and the mutable should implicit cast to readonly
        data: switch (mbl) {
            .mut => [*]u8,
            .cons => [*]const u8,
        },
        size: Vec2,

        pub fn wrapSlice(slice: switch (mbl) {
            .mut => []u8,
            .cons => []const u8,
        }, size: Vec2) Tex(mbl) {
            if (slice.len != texLen(size)) {
                unreachable;
            }
            return .{
                .data = slice.ptr,
                .size = size,
            };
        }

        pub fn cons(tex: Tex(.mut)) Tex(.cons) {
            return .{
                .data = tex.data,
                .size = tex.size,
            };
        }

        pub fn blit(dest: Tex(.mut), dest_ul: Vec2, src: Tex(.cons), src_ul: Vec2, src_wh: Vec2, remap_colors: [4]u3, scale: Vec2) void {
            for (range(@intCast(usize, src_wh[y]))) |_, y_usz| {
                const yp = @intCast(i32, y_usz);
                for (range(@intCast(usize, src_wh[x]))) |_, x_usz| {
                    const xp = @intCast(i32, x_usz);
                    const pos = Vec2{ xp, yp };

                    const value = remap_colors[src.get(src_ul + pos)];
                    if (value <= std.math.maxInt(u2)) {
                        dest.rect(pos * scale + dest_ul, scale, @intCast(u2, value));
                    }
                }
            }
        }
        pub fn rect(dest: Tex(.mut), ul: Vec2, wh: Vec2, color: u2) void {
            for (range(std.math.lossyCast(usize, wh[y]))) |_, y_usz| {
                const yp = @intCast(i32, y_usz);
                for (range(std.math.lossyCast(usize, wh[x]))) |_, x_usz| {
                    const xp = @intCast(i32, x_usz);

                    dest.set(ul + Vec2{ xp, yp }, color);
                }
            }
        }
        pub fn get(tex: Tex(mbl), pos: Vec2) u2 {
            if (@reduce(.Or, pos < w4.Vec2{ 0, 0 })) return 0;
            if (@reduce(.Or, pos >= tex.size)) return 0;
            const index_unscaled = pos[w4.x] + (pos[w4.y] * tex.size[w4.x]);
            const index = @intCast(usize, @divFloor(index_unscaled, 4));
            const byte_idx = @intCast(u3, (@mod(index_unscaled, 4)) * 2);
            return @truncate(u2, tex.data[index] >> byte_idx);
        }
        pub fn set(tex: Tex(.mut), pos: Vec2, value: u2) void {
            if (@reduce(.Or, pos < w4.Vec2{ 0, 0 })) return;
            if (@reduce(.Or, pos >= tex.size)) return;
            const index_unscaled = pos[w4.x] + (pos[w4.y] * tex.size[w4.x]);
            const index = @intCast(usize, @divFloor(index_unscaled, 4));
            const byte_idx = @intCast(u3, (@mod(index_unscaled, 4)) * 2);
            tex.data[index] &= ~(@as(u8, 0b11) << byte_idx);
            tex.data[index] |= @as(u8, value) << byte_idx;
        }
    };
}

pub fn range(len: usize) []const void {
    return @as([*]const void, &[_]void{})[0..len];
}

// pub const Tex1BPP = struct {…};

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Memory Addresses                                                          │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

pub const PALETTE: *[4]u32 = @intToPtr(*[4]u32, 0x04);
pub const DRAW_COLORS: *u16 = @intToPtr(*u16, 0x14);
pub const GAMEPAD1: *const Gamepad = @intToPtr(*const Gamepad, 0x16);
pub const GAMEPAD2: *const Gamepad = @intToPtr(*const Gamepad, 0x17);
pub const GAMEPAD3: *const Gamepad = @intToPtr(*const Gamepad, 0x18);
pub const GAMEPAD4: *const Gamepad = @intToPtr(*const Gamepad, 0x19);

pub const MOUSE: *const Mouse = @intToPtr(*const Mouse, 0x1a);
pub const SYSTEM_FLAGS: *SystemFlags = @intToPtr(*SystemFlags, 0x1f);
pub const FRAMEBUFFER: *[CANVAS_SIZE * CANVAS_SIZE / 4]u8 = @intToPtr(*[6400]u8, 0xA0);
pub const ctx = Tex(.mut){
    .data = @intToPtr([*]u8, 0xA0), // apparently casting *[N]u8 to [*]u8 at comptime causes a compiler crash
    .size = .{ CANVAS_SIZE, CANVAS_SIZE },
};

pub const Gamepad = packed struct {
    button_1: bool,
    button_2: bool,
    _: u2 = 0,
    button_left: bool,
    button_right: bool,
    button_up: bool,
    button_down: bool,
    comptime {
        if (@sizeOf(@This()) != @sizeOf(u8)) unreachable;
    }

    pub fn diff(this: @This(), other: @This()) @This() {
        return @bitCast(@This(), @bitCast(u8, this) ^ @bitCast(u8, other));
    }

    pub fn justPressed(this: @This(), last: @This()) @This() {
        const thisbits = @bitCast(u8, this);
        const lastbits = @bitCast(u8, last);
        return @bitCast(@This(), (thisbits ^ lastbits) & thisbits);
    }

    pub fn format(value: @This(), comptime _: []const u8, _: @import("std").fmt.FormatOptions, writer: anytype) !void {
        if (value.button_1) try writer.writeAll("1");
        if (value.button_2) try writer.writeAll("2");
        if (value.button_left) try writer.writeAll("<"); //"←");
        if (value.button_right) try writer.writeAll(">");
        if (value.button_up) try writer.writeAll("^");
        if (value.button_down) try writer.writeAll("v");
    }
};

pub const Mouse = packed struct {
    x: i16,
    y: i16,
    buttons: MouseButtons,
    pub fn pos(mouse: Mouse) Vec2 {
        return .{ mouse.x, mouse.y };
    }
    comptime {
        if (@sizeOf(@This()) != 5) unreachable;
    }
};

pub const MouseButtons = packed struct {
    left: bool,
    right: bool,
    middle: bool,
    _: u5 = 0,
    pub fn diff(this: @This(), other: @This()) @This() {
        return @bitCast(@This(), @bitCast(u8, this) ^ @bitCast(u8, other));
    }
    pub fn justPressed(this: @This(), last: @This()) @This() {
        const thisbits = @bitCast(u8, this);
        const lastbits = @bitCast(u8, last);
        return @bitCast(@This(), (thisbits ^ lastbits) & thisbits);
    }
    comptime {
        if (@sizeOf(@This()) != @sizeOf(u8)) unreachable;
    }
};

pub const SystemFlags = packed struct {
    preserve_framebuffer: bool,
    hide_gamepad_overlay: bool,
    _: u6 = 0,
    comptime {
        if (@sizeOf(@This()) != @sizeOf(u8)) unreachable;
    }
};

pub const SYSTEM_PRESERVE_FRAMEBUFFER: u8 = 1;
pub const SYSTEM_HIDE_GAMEPAD_OVERLAY: u8 = 2;

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Drawing Functions                                                         │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

pub const externs = struct {
    pub extern fn blit(sprite: [*]const u8, x: i32, y: i32, width: i32, height: i32, flags: u32) void;
    pub extern fn blitSub(sprite: [*]const u8, x: i32, y: i32, width: i32, height: i32, src_x: u32, src_y: u32, strie: i32, flags: u32) void;
    pub extern fn line(x1: i32, y1: i32, x2: i32, y2: i32) void;
    pub extern fn oval(x: i32, y: i32, width: i32, height: i32) void;
    pub extern fn rect(x: i32, y: i32, width: i32, height: i32) void;
    pub extern fn textUtf8(strPtr: [*]const u8, strLen: usize, x: i32, y: i32) void;

    /// Draws a vertical line
    extern fn vline(x: i32, y: i32, len: u32) void;

    /// Draws a horizontal line
    extern fn hline(x: i32, y: i32, len: u32) void;

    pub extern fn tone(frequency: u32, duration: u32, volume: u32, flags: u32) void;
};

/// Copies pixels to the framebuffer.
pub fn blit(sprite: []const u8, pos: Vec2, size: Vec2, flags: BlitFlags) void {
    if (sprite.len * 8 < size[x] * size[y]) unreachable;
    externs.blit(sprite.ptr, pos[x], pos[y], size[x], size[y], @bitCast(u32, flags));
}

/// Copies a subregion within a larger sprite atlas to the framebuffer.
pub fn blitSub(sprite: []const u8, pos: Vec2, size: Vec2, src: Vec2, strie: i32, flags: BlitFlags) void {
    if (sprite.len * 8 < size[x] * size[y]) unreachable;
    externs.blitSub(sprite.ptr, pos[x], pos[y], size[x], size[y], @intCast(u32, src[x]), @intCast(u32, src[y]), strie, @bitCast(u32, flags));
}

pub const BlitFlags = packed struct {
    bpp: enum(u1) {
        b1,
        b2,
    },
    flip_x: bool = false,
    flip_y: bool = false,
    rotate: bool = false,
    _: u28 = 0,
    comptime {
        if (@sizeOf(@This()) != @sizeOf(u32)) unreachable;
    }
};

/// Draws a line between two points.
pub fn line(pos1: Vec2, pos2: Vec2) void {
    externs.line(pos1[x], pos1[y], pos2[x], pos2[y]);
}

/// Draws an oval (or circle).
pub fn oval(ul: Vec2, size: Vec2) void {
    externs.oval(ul[x], ul[y], size[x], size[y]);
}

/// Draws a rectangle.
pub fn rect(ul: Vec2, size: Vec2) void {
    externs.rect(ul[x], ul[y], size[x], size[y]);
}

/// Draws text using the built-in system font.
pub fn text(str: []const u8, pos: Vec2) void {
    externs.textUtf8(str.ptr, str.len, pos[x], pos[y]);
}

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Sound Functions                                                           │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

/// Plays a sound tone.
pub fn tone(frequency: ToneFrequency, duration: ToneDuration, volume: u32, flags: ToneFlags) void {
    return externs.tone(@bitCast(u32, frequency), @bitCast(u32, duration), volume, @bitCast(u8, flags));
}
pub const ToneFrequency = packed struct {
    start: u16,
    end: u16 = 0,

    comptime {
        if (@sizeOf(@This()) != @sizeOf(u32)) unreachable;
    }
};

pub const ToneDuration = packed struct {
    sustain: u8 = 0,
    release: u8 = 0,
    decay: u8 = 0,
    attack: u8 = 0,

    comptime {
        if (@sizeOf(@This()) != @sizeOf(u32)) unreachable;
    }
};

pub const ToneFlags = packed struct {
    pub const Channel = enum(u2) {
        pulse1,
        pulse2,
        triangle,
        noise,
    };
    pub const Mode = enum(u2) {
        p12_5,
        p25,
        p50,
        p75,
    };

    channel: Channel,
    mode: Mode = .p12_5,
    _: u4 = 0,

    comptime {
        if (@sizeOf(@This()) != @sizeOf(u8)) unreachable;
    }
};

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Storage Functions                                                         │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

/// Reads up to `size` bytes from persistent storage into the pointer `dest`.
pub extern fn diskr(dest: [*]u8, size: u32) u32;

/// Writes up to `size` bytes from the pointer `src` into persistent storage.
pub extern fn diskw(src: [*]const u8, size: u32) u32;

// ┌───────────────────────────────────────────────────────────────────────────┐
// │                                                                           │
// │ Other Functions                                                           │
// │                                                                           │
// └───────────────────────────────────────────────────────────────────────────┘

/// Prints a message to the debug console.
/// Disabled in release builds.
pub fn trace(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").mode == .Debug) {
        // stack size is [8192]u8
        var buffer: [100]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();
        writer.print(fmt, args) catch {
            const err_msg = switch (@import("builtin").mode) {
                .Debug => "[trace err] " ++ fmt,
                else => "[trace err]", // max 100 bytes in trace message.
            };
            return traceUtf8(err_msg, err_msg.len);
        };

        traceUtf8(&buffer, fbs.pos);
    }
}
extern fn traceUtf8(str_ptr: [*]const u8, str_len: usize) void;

/// Use with caution, as there's no compile-time type checking.
///
/// * %c, %d, and %x expect 32-bit integers.
/// * %f expects 64-bit floats.
/// * %s expects a *zero-terminated* string pointer.
///
/// See https://github.com/aduros/wasm4/issues/244 for discussion and type-safe
/// alternatives.
pub extern fn tracef(x: [*:0]const u8, ...) void;
