const std = @import("std");
const w4 = @import("wasm4.zig");

// Adapted from https://gist.github.com/YuxiUx/c3a8787209e32fc29fb48e8454f0009c
const midiNote = [_]u16{
    8,    9,    9,    10,    10,    11,    12,    12,   13,   14,   15,
    15,   16,   17,   18,    19,    21,    22,    23,   24,   26,   28,
    29,   31,   33,   35,    37,    39,    41,    44,   46,   49,   52,
    55,   58,   62,   65,    69,    73,    78,    82,   87,   92,   98,
    104,  110,  117,  123,   131,   139,   147,   156,  165,  175,  185,
    196,  208,  220,  233,   247,   262,   277,   294,  311,  330,  349,
    370,  392,  415,  440,   466,   494,   523,   554,  587,  622,  659,
    698,  740,  784,  831,   880,   932,   988,   1047, 1109, 1175, 1245,
    1319, 1397, 1480, 1568,  1661,  1760,  1865,  1976, 2093, 2217, 2349,
    2489, 2637, 2794, 2960,  3136,  3322,  3520,  3729, 3951, 4186, 4435,
    4699, 4978, 5274, 5588,  5920,  6272,  6645,  7040, 7459, 7902, 8372,
    8870, 9397, 9956, 10548, 11175, 11840, 12544,
};

pub const Note = enum(usize) { C3 = 57, C4 = 69 };

// Defines steps along a musical scale
pub const Major = [8]usize{ 0, 2, 4, 5, 7, 9, 11, 12 };
pub const Minor = [8]usize{ 0, 2, 3, 5, 7, 8, 11, 12 };

pub const Sfx = struct {
    freq: w4.ToneFrequency,
    duration: w4.ToneDuration,
    volume: u8,
    flags: w4.ToneFlags,
};

pub const Intensity = enum(u8) {
    calm = 0,
    active = 1,
    danger = 2,
    pub fn atLeast(lhs: @This(), rhs: @This()) bool {
        return @enumToInt(lhs) >= @enumToInt(rhs);
    }
};

pub const Procedural = struct {
    tick: usize,
    note: usize,
    beat: usize,
    beatsPerBar: usize,
    seed: usize,
    root: usize,
    scale: []const usize,

    walking: bool = false,
    intensity: Intensity = .calm,
    newIntensity: ?Intensity = null,
    collect: ?struct { score: u8, start: usize, end: usize } = null,

    pub fn init(root: Note, scale: []const usize, seed: usize) @This() {
        return @This(){
            .tick = 0,
            .beat = 15,
            .beatsPerBar = 6,
            .seed = seed,
            .root = @enumToInt(root),
            .scale = scale,
            .note = 0,
        };
    }

    fn nextNote(this: @This(), t: usize) u16 {
        return midiNote[this.root + this.scale[((this.seed * t) % 313) % 8]];
    }

    pub fn isBeat(this: *@This(), beat: usize) bool {
        const beatProgress = this.tick % this.beat;
        const beatTotal = @divTrunc(this.tick, this.beat);
        const currentBeat = beatTotal % this.beatsPerBar;
        return (beatProgress == 0 and currentBeat == beat);
    }

    pub fn isDrumBeat(this: *@This()) bool {
        return switch (this.intensity) {
            .calm => this.isBeat(0),
            .active, .danger => this.isBeat(0) or this.isBeat(this.beatsPerBar / 2),
        };
    }

    pub fn playCollect(this: *@This(), score: u8) void {
        const beatTotal = @divTrunc(this.tick, this.beat);
        const length: u8 = if (score > 3) 2 else 1;
        this.collect = .{ .score = score, .start = beatTotal + 1, .end = beatTotal + (this.beatsPerBar * length) + 1 };
    }

    pub fn getNext(this: *@This(), dt: u32) MusicCommand {
        var i = 0;
        var cmd: [4]Sfx = undefined;
        const beatProgress = this.tick % this.beat;
        const beatTotal = @divTrunc(this.tick, this.beat);
        const beat = beatTotal % this.beatsPerBar;
        const bar = @divTrunc(beatTotal, this.beatsPerBar);
        this.tick += dt;
        if (beat == 0) this.intensity = this.newIntensity orelse this.intensity;
        if (this.collect) |collect| {
            const playNote = if (collect.score < 6) beat % 2 == 0 else beat % 4 != 3;
            if (beatTotal >= collect.start and beatTotal < collect.end and playNote and beatProgress == 0) {
                // const notelen = @intCast(u8, this.beat * this.beatsPerBar);
                cmd[i] = (Sfx{
                    .freq = .{ .start = this.nextNote(this.note) },
                    .duration = .{ .sustain = 5, .release = 5 },
                    .volume = 25,
                    .flags = .{ .channel = .pulse2, .mode = .p25 },
                });
                i += 1;
                this.note += 1;
            }
            if (bar > collect.end) {
                w4.tracef("end collect");
                this.collect = null;
            }
        }
        if (this.intensity.atLeast(.calm) and beat == 0 and beatProgress == 0) {
            cmd[i] = (.{
                .freq = .{ .start = 220, .end = 110 },
                .duration = .{ .release = 3 },
                .volume = 100,
                .flags = .{ .channel = .triangle },
            });
            i += 1;
        }
        if (this.intensity.atLeast(.active) and beat == this.beatsPerBar / 2 and beatProgress == 0) {
            cmd[i] = (.{
                .freq = .{ .start = 110, .end = 55 },
                .duration = .{ .release = 3 },
                .volume = 100,
                .flags = .{ .channel = .triangle },
            });
            i += 1;
        }
        if (this.walking and beat % 3 == 1 and beatProgress == 7) {
            cmd[i] = (.{
                .freq = .{ .start = 1761, .end = 1 },
                .duration = .{ .release = 5 },
                .volume = 25,
                .flags = .{ .channel = .noise },
            });
            i += 1;
        }
        return cmd;
    }
};
