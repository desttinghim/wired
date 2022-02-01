const input = @import("input.zig");
const w4 = @import("wasm4.zig");
const State = @import("main.zig").State;

const Vec2 = w4.Vec2;

var selected: i32 = 0;
const MenuOptions = enum(usize) {
    Continue,
    NewGame,
};

pub fn start() void {
    selected = 0;
}

pub fn update() State {
    w4.DRAW_COLORS.* = 0x0002;
    var i: i32 = 1;
    w4.text("WIRED", Vec2{ 16, i * 16 });
    i += 1;
    w4.text("Continue", Vec2{ 16, i * 16 });
    i += 1;
    w4.text("New Game", Vec2{ 16, i * 16 });
    i += 1;
    w4.text(">", Vec2{ 8, 32 + selected * 16 });

    if (input.btnp(.one, .down)) selected += 1;
    if (input.btnp(.one, .up)) selected -= 1;

    selected = if (selected < 0) 1 else @mod(selected, 2);

    if (input.btnp(.one, .one) or input.btnp(.one, .two)) {
        switch (@intToEnum(MenuOptions, selected)) {
            .Continue => return .Game,
            .NewGame => {
                _ = w4.diskw("", 0);
                return .Game;
            },
        }
    }

    return .Menu;
}
