const input = @import("input.zig");
const w4 = @import("wasm4.zig");
const Context = @import("main.zig").Context;

const Vec2 = w4.Vec2;

const MenuOptions = enum(usize) {
    Continue,
    NewGame,
};

selected: i32 = 0,
ctx: *Context,

pub fn init(ctx: *Context) !@This() {
    return @This(){
        .selected = 0,
        .ctx = ctx,
    };
}

pub fn deinit(_: *@This()) void {
    w4.trace("goodbye", .{});
}

pub fn update(this: *@This()) !void {
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(Vec2{ 0, 0 }, Vec2{ 160, 160 });
    w4.DRAW_COLORS.* = 0x0001;
    var i: i32 = 1;
    w4.text("WIRED", Vec2{ 16, i * 16 });
    i += 1;
    w4.text("Continue", Vec2{ 16, i * 16 });
    i += 1;
    w4.text("New Game", Vec2{ 16, i * 16 });
    i += 1;
    w4.text(">", Vec2{ 8, 32 + this.selected * 16 });

    if (input.btnp(.one, .down)) this.selected += 1;
    if (input.btnp(.one, .up)) this.selected -= 1;

    this.selected = if (this.selected < 0) 1 else @mod(this.selected, 2);

    if (input.btnp(.one, .one) or input.btnp(.one, .two)) {
        switch (@intToEnum(MenuOptions, this.selected)) {
            .Continue => _ = try this.ctx.scenes.replace(.game),
            .NewGame => {
                _ = w4.diskw("", 0);
                _ = try this.ctx.scenes.replace(.game);
            },
        }
    }
}
