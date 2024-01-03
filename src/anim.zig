time: usize = 0,
currentOp: usize = 0,
delayUntil: usize = 0,
anim: []const Ops,
stopped: bool = false,

pub const Ops = union(enum) { Index: usize, Wait: usize, Stop };

pub fn play(this: *@This(), anim: []const Ops) void {
    if (this.anim.ptr == anim.ptr) return;
    this.anim = anim;
    this.stopped = false;
    this.currentOp = 0;
}

pub fn update(this: *@This(), out: *usize) void {
    this.time += 1;
    while (!this.stopped and this.anim.len > 0 and this.time >= this.delayUntil) {
        switch (this.anim[this.currentOp]) {
            .Index => |index| out.* = index,
            .Wait => |wait| this.delayUntil = this.time + wait,
            .Stop => this.stopped = true,
        }
        this.currentOp = (this.currentOp + 1) % this.anim.len;
    }
}

pub fn simple(rate: usize, comptime arr: []const usize) [arr.len * 2]Ops {
    var anim: [arr.len * 2]Ops = undefined;
    inline for (arr, 0..) |item, i| {
        anim[i * 2] = Ops{ .Index = item };
        anim[i * 2 + 1] = Ops{ .Wait = rate };
    }
    return anim;
}

pub fn frame(comptime index: usize) [2]Ops {
    return [_]Ops{ .{ .Index = index }, .Stop };
}
