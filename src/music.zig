const w4 = @import("wasm4.zig");

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

pub const MusicCommand = struct {
    freq: ?u16 = null,
    drum: ?struct { freq: w4.ToneFrequency, duration: w4.ToneDuration } = null,
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

    intensity: Intensity = .calm,
    newIntensity: ?Intensity = null,

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

    pub fn getNext(this: *@This(), dt: u32) MusicCommand {
        var cmd = MusicCommand{};
        const beatProgress = this.tick % this.beat;
        const beatTotal = @divTrunc(this.tick, this.beat);
        const beat = beatTotal % this.beatsPerBar;
        const bar = @divTrunc(beat, this.beatsPerBar);
        this.tick += dt;
        if (beat == 0) this.intensity = this.newIntensity orelse this.intensity;
        if (this.intensity.atLeast(.active) and bar % 2 == 0 and beatProgress == 0) {
            cmd.freq = midiNote[this.root + this.scale[((this.seed * this.note) % 313) % 8]];
            this.note += 1;
        }
        if (this.intensity.atLeast(.calm) and beat == 0) cmd.drum = .{
            .freq = .{ .start = 100, .end = 1 },
            .duration = .{ .sustain = 1, .release = 4 },
        };
        if (this.intensity.atLeast(.danger) and beat % 3 == 1) cmd.drum = .{
            .freq = .{ .start = 1761 },
            .duration = .{ .release = 6 },
        };
        return cmd;
    }
};
