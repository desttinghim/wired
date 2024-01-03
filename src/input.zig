const w4 = @import("wasm4.zig");

const clearMouse = w4.Mouse{ .x = 0, .y = 0, .buttons = .{ .left = false, .right = false, .middle = false } };
const clear: u8 = 0x00;
pub var mouseLast: w4.Mouse = clearMouse;
pub var gamepad1Last: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad2Last: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad3Last: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad4Last: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));

pub var mouseJustPressed: w4.Mouse = clearMouse;
pub var gamepad1JustPressed: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad2JustPressed: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad3JustPressed: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));
pub var gamepad4JustPressed: w4.Gamepad = @as(w4.Gamepad, @bitCast(clear));

pub const Gamepad = enum { one, two, three, four };
pub const Button = enum { up, down, left, right, one, two };

pub fn btn(gamepad: Gamepad, button: Button) bool {
    const g = switch (gamepad) {
        .one => w4.GAMEPAD1.*,
        .two => w4.GAMEPAD2.*,
        .three => w4.GAMEPAD3.*,
        .four => w4.GAMEPAD4.*,
    };
    return switch (button) {
        .up => g.button_up,
        .down => g.button_down,
        .left => g.button_left,
        .right => g.button_right,
        .one => g.button_1,
        .two => g.button_2,
    };
}

pub fn btnp(gamepad: Gamepad, button: Button) bool {
    const g = switch (gamepad) {
        .one => gamepad1JustPressed,
        .two => gamepad2JustPressed,
        .three => gamepad3JustPressed,
        .four => gamepad4JustPressed,
    };
    return switch (button) {
        .up => g.button_up,
        .down => g.button_down,
        .left => g.button_left,
        .right => g.button_right,
        .one => g.button_1,
        .two => g.button_2,
    };
}

pub fn update() void {
    mouseJustPressed.buttons = w4.MOUSE.*.buttons.justPressed(mouseLast.buttons);
    gamepad1JustPressed = w4.GAMEPAD1.*.justPressed(gamepad1Last);
    gamepad2JustPressed = w4.GAMEPAD2.*.justPressed(gamepad2Last);
    gamepad3JustPressed = w4.GAMEPAD3.*.justPressed(gamepad3Last);
    gamepad4JustPressed = w4.GAMEPAD4.*.justPressed(gamepad4Last);

    mouseLast = w4.MOUSE.*;
    gamepad1Last = w4.GAMEPAD1.*;
    gamepad2Last = w4.GAMEPAD2.*;
    gamepad3Last = w4.GAMEPAD3.*;
    gamepad4Last = w4.GAMEPAD4.*;
}
