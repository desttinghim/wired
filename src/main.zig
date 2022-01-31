const std = @import("std");
const w4 = @import("wasm4.zig");
const assets = @import("assets");
const input = @import("input.zig");
const util = @import("util.zig");
const Circuit = @import("circuit.zig");
const Map = @import("map.zig");
const Music = @import("music.zig");

const Vec2 = util.Vec2;
const Vec2f = util.Vec2f;
const AABB = util.AABB;
const Anim = @import("anim.zig");

// Components
const Pos = struct {
    pos: Vec2f,
    last: Vec2f,
    pinned: bool = false,
    pub fn init(pos: Vec2f) @This() {
        return @This(){ .pos = pos, .last = pos };
    }
    pub fn initVel(pos: Vec2f, vel: Vec2f) @This() {
        return @This(){ .pos = pos, .last = pos - vel };
    }
};
const Control = struct {
    controller: enum { player },
    state: enum { stand, walk, jump, fall, wallSlide },
    facing: enum { left, right, up, down } = .right,
    grabbing: ?struct { id: usize, which: usize } = null,
};
const Sprite = struct {
    offset: Vec2 = Vec2{ 0, 0 },
    size: w4.Vec2,
    index: usize,
    flags: w4.BlitFlags,
};
const StaticAnim = Anim;
const ControlAnim = struct { anims: []AnimData, state: Anim };
const Kinematic = struct {
    col: AABB,
    move: Vec2f = Vec2f{ 0, 0 },
    lastCol: Vec2f = Vec2f{ 0, 0 },

    pub fn inAir(this: @This()) bool {
        return approxEqAbs(f32, this.lastCol[1], 0, 0.01);
    }

    pub fn onFloor(this: @This()) bool {
        return approxEqAbs(f32, this.move[1], 0, 0.01) and this.lastCol[1] > 0;
    }

    pub fn isFalling(this: @This()) bool {
        return this.move[1] > 0 and approxEqAbs(f32, this.lastCol[1], 0, 0.01);
    }

    pub fn onWall(this: @This()) bool {
        return this.isFalling() and !approxEqAbs(f32, this.lastCol[0], 0, 0.01);
    }
};
const Wire = struct {
    nodes: std.BoundedArray(Pos, 32),
    enabled: bool = false,

    pub fn begin(this: *@This()) *Pos {
        return &this.nodes.slice()[0];
    }

    pub fn end(this: *@This()) *Pos {
        return &this.nodes.slice()[this.nodes.len - 1];
    }
};
const Physics = struct { gravity: Vec2f, friction: Vec2f };
const Player = struct {
    pos: Pos,
    control: Control,
    sprite: Sprite,
    controlAnim: ControlAnim,
    kinematic: Kinematic,
    physics: Physics,
};
// const World = ecs.World(Component);

const Particle = struct {
    pos: Pos,
    life: i32,
    pub fn init(pos: Pos, life: i32) @This() {
        return @This(){
            .pos = pos,
            .life = life,
        };
    }
};

const ParticleSystem = struct {
    const MAXPARTICLES = 32;
    particles: std.BoundedArray(Particle, MAXPARTICLES),
    pub fn init() @This() {
        return @This(){
            .particles = std.BoundedArray(Particle, MAXPARTICLES).init(0) catch unreachable,
        };
    }

    pub fn update(this: *@This()) void {
        var physics = .{ .gravity = Vec2f{ 0, 0.1 }, .friction = Vec2f{ 0.1, 0.1 } };
        var remove = std.BoundedArray(usize, MAXPARTICLES).init(0) catch unreachable;
        for (this.particles.slice()) |*part, i| {
            if (!inView(part.pos.pos)) {
                remove.append(i) catch unreachable;
                continue;
            }
            velocityProcess(1, &part.pos);
            physicsProcess(1, &part.pos, &physics);
            part.life -= 1;
            if (part.life == 0) remove.append(i) catch unreachable;
        }
        while (remove.popOrNull()) |i| {
            _ = this.particles.swapRemove(i);
        }
    }

    pub fn draw(this: @This()) void {
        for (this.particles.constSlice()) |*part| {
            w4.DRAW_COLORS.* = 0x0002;
            w4.oval(util.vec2fToVec2(part.pos.pos) - camera * Map.tile_size, Vec2{ 2, 2 });
        }
    }

    pub fn createRandom(this: *@This(), pos: Vec2f) void {
        if (this.particles.len == this.particles.capacity()) return;
        const vel = Vec2f{ randRangeF(-1, 1), randRangeF(-2, 0) };
        const posComp = Pos.initVel(pos, vel);
        const life = randRange(10, 50);
        const part = Particle.init(posComp, life);
        this.particles.append(part) catch unreachable;
    }

    pub fn createNRandom(this: *@This(), pos: Vec2f, n: usize) void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            this.createRandom(pos);
        }
    }
};

fn inView(vec: Vec2f) bool {
    return @reduce(
        .And,
        @divTrunc(util.world2cell(vec), @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20)) == camera,
    );
}

fn randRange(min: i32, max: i32) i32 {
    return random.intRangeLessThanBiased(i32, min, max);
}

fn randRangeF(min: f32, max: f32) f32 {
    return min + (random.float(f32) * (max - min));
}

// Global vars
var map: Map = undefined;
var circuit: Circuit = undefined;
var particles: ParticleSystem = undefined;
var prng = std.rand.DefaultPrng.init(0);
var random = prng.random();
var player: Player = undefined;
var music = Music.Procedural.init(.C3, &Music.Minor, 83);
var wires = std.BoundedArray(Wire, 10).init(0) catch unreachable;
var camera = Vec2{ 0, 0 };

const Coin = struct { pos: Pos, sprite: Sprite, anim: Anim, area: AABB };
var coins = std.BoundedArray(Coin, 20).init(0) catch unreachable;
var score: u8 = 0;
var ScoreCoin = Sprite{
    .size = Map.tile_size,
    .index = 4,
    .flags = .{ .bpp = .b2 },
};

var solids_mutable = assets.solid;
var conduit_mutable = assets.conduit;
var conduitLevels_mutable: [conduit_mutable.len]u8 = undefined;

const anim_store = struct {
    const stand = Anim.frame(8);
    const walk = Anim.simple(4, &[_]usize{ 9, 10, 11, 12 });
    const jump = Anim.frame(13);
    const fall = Anim.frame(14);
    const wallSlide = Anim.frame(15);
    const coin = Anim.simple(15, &[_]usize{ 4, 5, 6 });
};

const AnimData = []const Anim.Ops;

const playerAnim = pac: {
    var animArr = std.BoundedArray(AnimData, 100).init(0) catch unreachable;
    animArr.append(&anim_store.stand) catch unreachable;
    animArr.append(&anim_store.walk) catch unreachable;
    animArr.append(&anim_store.jump) catch unreachable;
    animArr.append(&anim_store.fall) catch unreachable;
    animArr.append(&anim_store.wallSlide) catch unreachable;
    break :pac animArr.slice();
};

fn showErr(msg: []const u8) noreturn {
    w4.traceNoF(msg);
    unreachable;
}

export fn start() void {
    particles = ParticleSystem.init();

    std.mem.set(u8, &conduitLevels_mutable, 0);
    circuit = Circuit.init(&conduit_mutable, &conduitLevels_mutable, assets.conduit_size);
    map = Map.init(&solids_mutable, assets.solid_size);

    camera = @divTrunc(assets.spawn, @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20));

    const tile_size = Vec2{ 8, 8 };
    const offset = Vec2{ 4, 8 };

    player = .{
        .pos = Pos.init(util.vec2ToVec2f(assets.spawn * tile_size + offset)),
        .control = .{ .controller = .player, .state = .stand },
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 8, .flags = .{ .bpp = .b2 } },
        .physics = .{ .friction = Vec2f{ 0.15, 0.1 }, .gravity = Vec2f{ 0, 0.25 } },
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
        .kinematic = .{ .col = .{ .pos = .{ -3, -6 }, .size = .{ 5, 5 } } },
    };

    for (assets.wire) |wire| {
        const begin = vec2tovec2f(wire.p1);
        const end = vec2tovec2f(wire.p2);
        const size = end - begin;

        var nodes = std.BoundedArray(Pos, 32).init(0) catch showErr("Nodes");
        var i: usize = 0;
        const divisions = @floatToInt(usize, util.lengthf(size) / 6);
        while (i <= divisions) : (i += 1) {
            const pos = begin + @splat(2, @intToFloat(f32, i)) * size / @splat(2, @intToFloat(f32, divisions));
            nodes.append(Pos.init(pos)) catch showErr("Appending nodes");
        }
        if (wire.a1) nodes.slice()[0].pinned = true;
        if (wire.a2) nodes.slice()[nodes.len - 1].pinned = true;
        const w = Wire{ .nodes = nodes };
        wires.append(w) catch showErr("Appending wire");
    }

    for (assets.sources) |source| {
        circuit.addSource(source);
    }

    for (assets.doors) |door| {
        circuit.addDoor(door);
    }

    if (!load()) {
        for (assets.coins) |coin| {
            coins.append(.{
                .pos = Pos.init(util.vec2ToVec2f(coin * tile_size)),
                .sprite = .{ .offset = .{ 0, 0 }, .size = .{ 8, 8 }, .index = 4, .flags = .{ .bpp = .b2 } },
                .anim = Anim{ .anim = &anim_store.coin },
                .area = .{ .pos = .{ 0, 0 }, .size = .{ 8, 8 } },
            }) catch showErr("Appending coin");
        }
    }

    updateCircuit();
}

var indicator: ?Interaction = null;
var time: usize = 0;

export fn update() void {
    for (wires.slice()) |*wire| {
        wirePhysicsProcess(1, wire);
        if (wire.enabled) {
            if (music.isDrumBeat()) {
                if (!wire.begin().pinned) particles.createNRandom(wire.begin().pos, 8);
                if (!wire.end().pinned) particles.createNRandom(wire.end().pos, 8);
            }
        }
    }

    velocityProcess(1, &player.pos);
    physicsProcess(1, &player.pos, &player.physics);
    manipulationProcess(&player.pos, &player.control);
    controlProcess(1, &player.pos, &player.control, &player.physics, &player.kinematic);
    kinematicProcess(1, &player.pos, &player.kinematic);
    controlAnimProcess(1, &player.sprite, &player.controlAnim, &player.control);
    particles.update();

    // Drawing
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });
    drawProcess(1, &player.pos, &player.sprite);

    {
        var shouldSave = false;
        var remove = std.BoundedArray(usize, 10).init(0) catch unreachable;
        for (coins.slice()) |*coin, i| {
            staticAnimProcess(1, &coin.sprite, &coin.anim);
            drawProcess(1, &coin.pos, &coin.sprite);
            if (coin.area.addv(coin.pos.pos).overlaps(player.kinematic.col.addv(player.pos.pos))) {
                score += 1;
                remove.append(i) catch unreachable;
                music.playCollect(score);
                shouldSave = true;
            }
        }
        while (remove.popOrNull()) |i| {
            _ = coins.swapRemove(i);
        }
        // We save here to prevent duplicate coins
        if (shouldSave) save();
    }

    camera = @divTrunc(util.world2cell(player.pos.pos), @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20));

    map.draw(camera);
    circuit.draw(camera);

    for (wires.slice()) |*wire| {
        wireDrawProcess(1, wire);
    }

    particles.draw();

    {
        const pos = util.world2cell(player.pos.pos);
        const shouldHum = circuit.isEnabled(pos) or
            circuit.isEnabled(pos + util.Dir.up) or
            circuit.isEnabled(pos + util.Dir.down) or
            circuit.isEnabled(pos + util.Dir.left) or
            circuit.isEnabled(pos + util.Dir.right);
        if (shouldHum) {
            w4.tone(.{ .start = 60 }, .{ .release = 255, .sustain = 0 }, 1, .{ .channel = .pulse1, .mode = .p50 });
        }
    }

    if (indicator) |details| {
        const pos = details.pos - (camera * Map.tile_size);
        const stage = @divTrunc((time % 60), 30);
        var size = Vec2{ 0, 0 };
        switch (stage) {
            0 => size = Vec2{ 6, 6 },
            else => size = Vec2{ 8, 8 },
        }

        if (details.active) {
            // w4.tone(.{ .start = 60 }, .{ .release = 255, .sustain = 0 }, 10, .{ .channel = .pulse1, .mode = .p50 });
            // music.newIntensity = .danger;
            w4.DRAW_COLORS.* = 0x0020;
        } else {
            w4.DRAW_COLORS.* = 0x0030;
        }
        var half = Vec2{ @divTrunc(size[0], 2), @divTrunc(size[1], 2) };
        switch (details.details) {
            .wire => w4.oval(pos - half, size),
            .plug => w4.rect(pos - half, size),
            .lever => w4.rect(pos - half, size),
        }
    }

    // Score UI
    {
        const playerPos = util.vec2fToVec2(player.pos.pos) - camera * Map.tile_size;
        const textOffset = Vec2{ 9, 1 };
        const textChars = 3;
        const size = Vec2{ 8 * textChars, 8 } + textOffset;
        const scorePos = Vec2{
            if (playerPos[0] > 80) 0 else 160 - size[0],
            if (playerPos[1] > 80) 0 else 160 - size[1],
        };

        // Manually convert score to text
        var scoreDigits = [textChars]u8{ 'x', '0', '0' };
        scoreDigits[1] = '0' + @divTrunc(score, 10);
        scoreDigits[2] = '0' + score % 10;

        // Clear background of score
        w4.DRAW_COLORS.* = 0x0004;
        w4.rect(scorePos, size);

        // Draw coin
        draw_sprite(scorePos, ScoreCoin);

        w4.DRAW_COLORS.* = 0x0042;
        w4.text(&scoreDigits, scorePos + Vec2{ 9, 1 });
    }

    // Music
    const musicCommand = music.getNext(1);
    for (musicCommand.constSlice()) |sfx| {
        w4.tone(sfx.freq, sfx.duration, sfx.volume, sfx.flags);
    }

    indicator = null;
    input.update();
    time += 1;
}

fn write_diff(writer: anytype, stride: usize, initial: []const u8, mapBuf: []const u8) !u8 {
    var written: u8 = 0;
    for (initial) |init_tile, i| {
        if (mapBuf[i] != init_tile) {
            const x = @intCast(u8, i % @intCast(usize, stride));
            const y = @intCast(u8, @divTrunc(i, @intCast(usize, stride)));
            const temp = [3]u8{ x, y, mapBuf[i] };
            try writer.writeAll(&temp);
            written += 1;
        }
    }
    return written;
}

pub fn load_diff(mapBuf: []u8, stride: usize, diff: []const u8) void {
    var i: usize = 0;
    while (i < diff.len) : (i += 3) {
        const x = diff[i];
        const y = diff[i + 1];
        const tile = diff[i + 2];
        const a = x + y * stride;
        mapBuf[a] = tile;
        // this.set_cell(Cell{ x, y }, tile);
    }
}

fn load() bool {
    var load_buf: [1024]u8 = undefined;
    const read = w4.diskr(&load_buf, 1024);
    w4.tracef("%d bytes read", read);

    // if (true) return false;
    if (read <= 0) return false;
    // for (load_buf[0 .. read - 1]) |byte| w4.tracef("%d", byte);

    var stream = std.io.fixedBufferStream(load_buf[0..read]);
    var reader = stream.reader();

    var header: [5]u8 = undefined;
    _ = reader.read(&header) catch w4.tracef("couldn't load header");
    w4.tracef("%s", &header);
    if (!std.mem.eql(u8, "wired", &header)) return false; // w4.tracef("did not load, incorrect header bytes");

    score = reader.readByte() catch return false;

    const obj_len = reader.readByte() catch return false;
    // const map_len = reader.readByte() catch return false;
    const conduit_len = reader.readByte() catch return false;

    var i: usize = 0;
    while (i < obj_len) : (i += 1) {
        const b = reader.readByte() catch return false;
        const obj = @intToEnum(SaveObj, @truncate(u4, b));
        const id = @truncate(u4, b >> 4);
        const x = reader.readIntBig(u16) catch return false;
        const y = reader.readIntBig(u16) catch return false;
        var pos = Pos.init(util.vec2ToVec2f(Vec2{ x, y }));
        switch (obj) {
            .Player => {
                w4.tracef("player at %d, %d", x, y);
                player.pos = pos;
                // player.pos.pos += Vec2f{ 4, 6 };
            },
            .Coin => {
                coins.append(.{
                    .pos = pos,
                    .sprite = .{ .offset = .{ 0, 0 }, .size = .{ 8, 8 }, .index = 4, .flags = .{ .bpp = .b2 } },
                    .anim = Anim{ .anim = &anim_store.coin },
                    .area = .{ .pos = .{ 0, 0 }, .size = .{ 8, 8 } },
                }) catch unreachable;
            },
            .WireBeginPinned => {
                var begin = wires.slice()[id].begin();
                begin.* = pos;
                begin.pinned = true;
            },
            .WireBeginLoose => {
                var begin = wires.slice()[id].begin();
                begin.* = pos;
                begin.pinned = false;
            },
            .WireEndPinned => {
                var end = wires.slice()[id].end();
                end.* = pos;
                end.pinned = true;
            },
            .WireEndLoose => {
                var end = wires.slice()[id].end();
                end.* = pos;
                end.pinned = false;
            },
        }
    }

    // Load map
    var buf: [256]u8 = undefined;
    // const len = reader.readByte() catch return;
    // const bytes_map = reader.read(buf[0 .. map_len * 3]) catch return false;
    // w4.tracef("loading %d map diffs... %d bytes", map_len, bytes_map);
    // load_diff(&solids_mutable, assets.solid_size[0], buf[0..bytes_map]);

    // Load conduit
    // const conduit_len = reader.readByte() catch return;
    const bytes_conduit = reader.read(buf[0 .. conduit_len * 3]) catch return false;
    w4.tracef("loading %d conduit diffs... %d bytes", conduit_len, bytes_conduit);
    for (buf[0..bytes_conduit]) |byte| w4.tracef("%d", byte);
    load_diff(&conduit_mutable, assets.conduit_size[0], buf[0..bytes_conduit]);

    return true;
}

const SaveObj = enum(u4) {
    Player,
    Coin,
    WireBeginPinned,
    WireBeginLoose,
    WireEndPinned,
    WireEndLoose,
};

fn cell2u8(cell: util.Cell) [2]u8 {
    return [_]u8{ @intCast(u8, cell[0]), @intCast(u8, cell[1]) };
}

fn vec2u16(vec2: util.Vec2) [2]u16 {
    return [_]u16{ @intCast(u16, vec2[0]), @intCast(u16, vec2[1]) };
}

fn save() void {
    var save_buf: [1024]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);
    var save_writer = save_stream.writer();
    save_writer.writeAll("wired") catch return w4.tracef("Couldn't write header");
    save_writer.writeByte(score) catch return w4.tracef("Couldn't save score");
    w4.tracef("score %d written", score);

    // Write temporary length values
    const lengths_start = save_stream.getPos() catch return w4.tracef("Couldn't get pos");
    save_writer.writeByte(0) catch return w4.tracef("Couldn't write obj length");
    // save_writer.writeByte(0) catch return w4.tracef("Couldn't write map length");
    save_writer.writeByte(0) catch return w4.tracef("Couldn't write conduit length");

    // Write player
    const playerPos = vec2u16(util.vec2fToVec2(player.pos.pos));
    save_writer.writeByte(@enumToInt(SaveObj.Player)) catch return w4.tracef("Player");
    save_writer.writeIntBig(u16, playerPos[0]) catch return;
    save_writer.writeIntBig(u16, playerPos[1]) catch return;
    // save_writer.writeAll(&[_]u8{ @enumToInt(SaveObj.Player), @intCast(u8, player
    var obj_len: u8 = 1;

    for (coins.slice()) |coin, i| {
        obj_len += 1;
        const id = @intCast(u8, @truncate(u4, i)) << 4;
        // const cell = util.world2cell(coin.pos.pos);
        save_writer.writeByte(@enumToInt(SaveObj.Coin) | id) catch return w4.tracef("Couldn't save coin");
        const pos = vec2u16(util.vec2fToVec2(coin.pos.pos));
        save_writer.writeIntBig(u16, pos[0]) catch return;
        save_writer.writeIntBig(u16, pos[1]) catch return;
        // save_writer.writeInt(&) catch return;
    }

    // Write wires
    for (wires.slice()) |*wire, i| {
        const id = @intCast(u8, @truncate(u4, i)) << 4;
        const begin = wire.begin();
        const end = wire.end();
        obj_len += 1;
        if (begin.pinned) {
            // const cell = util.world2cell(begin.pos);
            save_writer.writeByte(@enumToInt(SaveObj.WireBeginPinned) | id) catch return w4.tracef("Couldn't save wire");
            // const pos = cell2u16(cell);
            const pos = vec2u16(util.vec2fToVec2(begin.pos));
            save_writer.writeIntBig(u16, pos[0]) catch return;
            save_writer.writeIntBig(u16, pos[1]) catch return;
            // save_writer.writeAll(&cell2u8(cell)) catch return;
        } else {
            // const cell = util.world2cell(begin.pos);
            save_writer.writeByte(@enumToInt(SaveObj.WireBeginLoose) | id) catch return w4.tracef("Couldn't save wire");
            // const pos = cell2u16(cell);
            const pos = vec2u16(util.vec2fToVec2(begin.pos));
            save_writer.writeIntBig(u16, pos[0]) catch return;
            save_writer.writeIntBig(u16, pos[1]) catch return;
            // save_writer.writeAll(&cell2u8(cell)) catch return;
        }
        obj_len += 1;
        if (end.pinned) {
            // const cell = util.world2cell(end.pos);
            save_writer.writeByte(@enumToInt(SaveObj.WireEndPinned) | id) catch return w4.tracef("Couldn't save wire");
            // const pos = cell2u16(cell);
            const pos = vec2u16(util.vec2fToVec2(end.pos));
            save_writer.writeIntBig(u16, pos[0]) catch return;
            save_writer.writeIntBig(u16, pos[1]) catch return;
            // save_writer.writeAll(&cell2u8(cell)) catch return;
        } else {
            // const cell = util.world2cell(end.pos);
            save_writer.writeByte(@enumToInt(SaveObj.WireEndLoose) | id) catch return w4.tracef("Couldn't save wire");
            // const pos = cell2u16(cell);
            const pos = vec2u16(util.vec2fToVec2(end.pos));
            save_writer.writeIntBig(u16, pos[0]) catch return;
            save_writer.writeIntBig(u16, pos[1]) catch return;
            // save_writer.writeAll(&cell2u8(cell)) catch return;
        }
    }

    // Write map
    // const map_len =  write_diff(save_writer, assets.solid_size[0], &assets.solid, &solids_mutable) catch return w4.tracef("Couldn't save map diff");

    // Write conduit
    const conduit_len = write_diff(save_writer, assets.conduit_size[0], &assets.conduit, &conduit_mutable) catch return w4.tracef("Couldn't save map diff");

    const endPos = save_stream.getPos() catch return;
    save_stream.seekTo(lengths_start) catch w4.tracef("Couldn't seek");
    save_writer.writeByte(obj_len) catch return w4.tracef("Couldn't write obj length");
    // save_writer.writeByte(map_len) catch return w4.tracef("Couldn't write map length");
    save_writer.writeByte(conduit_len) catch return w4.tracef("Couldn't write conduit length");

    save_stream.seekTo(endPos) catch return;
    const save_slice = save_stream.getWritten();
    const written = w4.diskw(save_slice.ptr, save_slice.len);
    w4.tracef("%d bytes written", written);
    for (save_buf[0..written]) |byte| w4.tracef("%d", byte);
}

const Interaction = struct {
    pos: Vec2,
    details: union(enum) {
        wire: struct { id: usize, which: usize },
        plug: struct { wireID: usize, which: usize },
        lever,
    },
    active: bool = false,
};

fn getNearestCircuitInteraction(pos: Vec2f) ?Interaction {
    const cell = util.world2cell(pos);
    if (circuit.get_cell(cell)) |tile| {
        if (Circuit.is_switch(tile)) {
            return Interaction{ .details = .lever, .pos = cell * Map.tile_size + Vec2{ 4, 4 } };
        }
    }
    return null;
}

fn getNearestWireInteraction(pos: Vec2f, range: f32) ?Interaction {
    var newIndicator: ?Interaction = null;
    var minDistance: f32 = range;
    for (wires.slice()) |*wire, wireID| {
        const begin = wire.begin().pos;
        const end = wire.end().pos;
        var dist = util.distancef(begin, pos);
        if (dist < minDistance) {
            minDistance = dist;
            newIndicator = Interaction{
                .details = .{ .wire = .{ .id = wireID, .which = 0 } },
                .pos = vec2ftovec2(begin),
                .active = wire.enabled,
            };
        }
        dist = util.distancef(end, pos);
        if (dist < minDistance) {
            minDistance = dist;
            newIndicator = .{
                .details = .{ .wire = .{ .id = wireID, .which = wire.nodes.len - 1 } },
                .pos = vec2ftovec2(end),
                .active = wire.enabled,
            };
        }
    }
    return newIndicator;
}

fn manipulationProcess(pos: *Pos, control: *Control) void {
    var offset = switch (control.facing) {
        .left => Vec2f{ -6, 0 },
        .right => Vec2f{ 6, 0 },
        .up => Vec2f{ 0, -8 },
        .down => Vec2f{ 0, 8 },
    };
    // TODO: add centered property
    const centeredPos = pos.pos + Vec2f{ 0, -4 };
    const offsetPos = centeredPos + offset;

    if (control.grabbing == null) {
        if (getNearestWireInteraction(offsetPos, 8)) |i| {
            indicator = i;
        } else if (getNearestWireInteraction(centeredPos - offset, 8)) |i| {
            indicator = i;
        } else if (getNearestCircuitInteraction(offsetPos)) |i| {
            indicator = i;
        } else if (getNearestCircuitInteraction(centeredPos)) |i| {
            indicator = i;
        } else if (getNearestCircuitInteraction(centeredPos - offset)) |i| {
            indicator = i;
        }
    } else if (control.grabbing) |details| {
        const cell = util.world2cell(offsetPos);
        var wire = &wires.slice()[details.id];
        var nodes = wire.nodes.slice();

        var maxLength = wireMaxLength(wire);
        var length = wireLength(wire);

        if (length > maxLength * 1.5) {
            nodes[details.which].pinned = false;
            control.grabbing = null;
        } else {
            nodes[details.which].pos = pos.pos + Vec2f{ 0, -4 };
        }

        if (Circuit.is_plug(circuit.get_cell(cell) orelse 0)) {
            const active = circuit.isEnabled(cell);
            indicator = .{
                .details = .{ .plug = .{ .wireID = details.id, .which = details.which } },
                .pos = cell * Map.tile_size + Vec2{ 4, 4 },
                .active = active,
            };
        } else if (input.btnp(.one, .two)) {
            nodes[details.which].pinned = false;
            control.grabbing = null;
        }
    }
    if (input.btnp(.one, .two)) {
        if (indicator) |i| {
            switch (i.details) {
                .wire => |wire| {
                    control.grabbing = .{ .id = wire.id, .which = wire.which };
                    wires.slice()[wire.id].nodes.slice()[wire.which].pos = pos.pos + Vec2f{ 0, -4 };
                    wires.slice()[wire.id].nodes.slice()[wire.which].pinned = false;
                    updateCircuit();
                },
                .plug => |plug| {
                    wires.slice()[plug.wireID].nodes.slice()[plug.which].pos = vec2tovec2f(indicator.?.pos);
                    wires.slice()[plug.wireID].nodes.slice()[plug.which].pinned = true;
                    control.grabbing = null;
                    updateCircuit();
                },
                .lever => {
                    const cell = @divTrunc(i.pos, Map.tile_size);
                    circuit.toggle(cell);
                    updateCircuit();
                },
            }
        }
    }
}

fn updateCircuit() void {
    circuit.clear();
    for (wires.slice()) |*wire, wireID| {
        wire.enabled = false;
        if (!wire.begin().pinned or !wire.end().pinned) continue;
        const nodes = wire.nodes.constSlice();
        const cellBegin = util.world2cell(nodes[0].pos);
        const cellEnd = util.world2cell(nodes[nodes.len - 1].pos);

        circuit.bridge(.{ cellBegin, cellEnd }, wireID);
    }
    _ = circuit.fill();
    for (wires.slice()) |*wire| {
        const begin = wire.begin();
        const end = wire.end();
        const cellBegin = util.world2cell(begin.pos);
        const cellEnd = util.world2cell(end.pos);
        if ((circuit.isEnabled(cellBegin) and begin.pinned) or
            (circuit.isEnabled(cellEnd) and end.pinned)) wire.enabled = true;
    }
    map.reset(&assets.solid);
    const enabledDoors = circuit.enabledDoors();
    for (enabledDoors.constSlice()) |door| {
        map.set_cell(door, 0);
    }
}

fn wirePhysicsProcess(dt: f32, wire: *Wire) void {
    var nodes = wire.nodes.slice();
    if (nodes.len == 0) return;
    if (!inView(wire.begin().pos) and !inView(wire.end().pos)) return;
    var physics = Physics{ .gravity = Vec2f{ 0, 0.25 }, .friction = Vec2f{ 0.1, 0.1 } };
    var kinematic = Kinematic{ .col = AABB{ .pos = Vec2f{ -1, -1 }, .size = Vec2f{ 1, 1 } } };

    for (nodes) |*node| {
        velocityProcess(dt, node);
        physicsProcess(dt, node, &physics);
        kinematicProcess(dt, node, &kinematic);
    }

    var iterations: usize = 0;
    while (iterations < 4) : (iterations += 1) {
        var left: usize = 1;
        while (left < nodes.len) : (left += 1) {
            // Left side
            constrainNodes(&nodes[left - 1], &nodes[left]);
            kinematicProcess(dt, &nodes[left - 1], &kinematic);
            kinematicProcess(dt, &nodes[left], &kinematic);
        }
    }
}

const wireSegmentMaxLength = 4;

fn wireMaxLength(wire: *Wire) f32 {
    return @intToFloat(f32, wire.nodes.len) * wireSegmentMaxLength;
}

fn wireLength(wire: *Wire) f32 {
    var nodes = wire.nodes.slice();
    var length: f32 = 0;
    var i: usize = 1;
    while (i < nodes.len) : (i += 1) {
        length += util.distancef(nodes[i - 1].pos, nodes[i].pos);
    }
    return length;
}

fn constrainNodes(prevNode: *Pos, node: *Pos) void {
    var diff = prevNode.pos - node.pos;
    var dist = util.distancef(node.pos, prevNode.pos);
    var difference: f32 = 0;
    if (dist > 0) {
        difference = (wireSegmentMaxLength - dist) / dist;
    }
    var translate = diff * @splat(2, 0.5 * difference);
    if (!prevNode.pinned) prevNode.pos += translate;
    if (!node.pinned) node.pos -= translate;
}

fn wireDrawProcess(_: f32, wire: *Wire) void {
    var nodes = wire.nodes.slice();
    if (nodes.len == 0) return;
    if (!inView(wire.begin().pos) and !inView(wire.end().pos)) return;

    w4.DRAW_COLORS.* = if (wire.enabled) 0x0002 else 0x0003;
    for (nodes) |node, i| {
        if (i == 0) continue;
        const offset = (camera * Map.tile_size);
        w4.line(vec2ftovec2(nodes[i - 1].pos) - offset, vec2ftovec2(node.pos) - offset);
    }
}

fn vec2tovec2f(vec2: w4.Vec2) Vec2f {
    return Vec2f{ @intToFloat(f32, vec2[0]), @intToFloat(f32, vec2[1]) };
}

fn vec2ftovec2(vec2f: Vec2f) w4.Vec2 {
    return w4.Vec2{ @floatToInt(i32, vec2f[0]), @floatToInt(i32, vec2f[1]) };
}

fn drawProcess(_: f32, pos: *Pos, sprite: *Sprite) void {
    if (!inView(pos.pos)) return;
    const ipos = (util.vec2fToVec2(pos.pos) + sprite.offset) - camera * Map.tile_size;
    draw_sprite(ipos, sprite.*);
}

fn draw_sprite(pos: Vec2, sprite: Sprite) void {
    w4.DRAW_COLORS.* = 0x2210;
    const index = sprite.index;
    const t = w4.Vec2{ @intCast(i32, (index * 8) % 128), @intCast(i32, (index * 8) / 128) };
    w4.blitSub(&assets.tiles, pos, sprite.size, t, 128, sprite.flags);
}

fn staticAnimProcess(_: f32, sprite: *Sprite, anim: *StaticAnim) void {
    anim.update(&sprite.index);
}

fn controlAnimProcess(_: f32, sprite: *Sprite, anim: *ControlAnim, control: *Control) void {
    const a: usize = switch (control.state) {
        .stand => 0,
        .walk => 1,
        .jump => 2,
        .fall => 3,
        .wallSlide => 4,
    };
    if (a != 0) music.walking = true else music.walking = false;
    sprite.flags.flip_x = (control.facing == .left);
    anim.state.play(anim.anims[a]);
    anim.state.update(&sprite.index);
}

const approxEqAbs = std.math.approxEqAbs;

fn controlProcess(_: f32, pos: *Pos, control: *Control, physics: *Physics, kinematic: *Kinematic) void {
    var delta = Vec2f{ 0, 0 };
    if (approxEqAbs(f32, kinematic.move[1], 0, 0.01) and kinematic.lastCol[1] > 0) {
        if (input.btnp(.one, .one)) delta[1] -= 23;
        if (input.btn(.one, .left)) delta[0] -= 1;
        if (input.btn(.one, .right)) delta[0] += 1;
        if (delta[0] != 0 or delta[1] != 0) {
            control.state = .walk;
        } else {
            control.state = .stand;
        }
    } else if (kinematic.move[1] > 0 and !approxEqAbs(f32, kinematic.lastCol[0], 0, 0.01) and approxEqAbs(f32, kinematic.lastCol[1], 0, 0.01)) {
        // w4.trace("{}, {}", .{ kinematic.move, kinematic.lastCol });
        if (kinematic.lastCol[0] > 0 and input.btnp(.one, .one)) delta = Vec2f{ -10, -15 };
        if (kinematic.lastCol[0] < 0 and input.btnp(.one, .one)) delta = Vec2f{ 10, -15 };
        physics.gravity = Vec2f{ 0, 0.05 };
        control.state = .wallSlide;
    } else {
        if (input.btn(.one, .left)) delta[0] -= 1;
        if (input.btn(.one, .right)) delta[0] += 1;
        physics.gravity = Vec2f{ 0, 0.25 };
        if (kinematic.move[1] < 0) control.state = .jump else control.state = .fall;
    }
    if (delta[0] > 0) control.facing = .right;
    if (delta[0] < 0) control.facing = .left;
    if (input.btn(.one, .up)) control.facing = .up;
    if (input.btn(.one, .down)) control.facing = .down;
    var move = delta * @splat(2, @as(f32, 0.2));
    pos.pos += move;
}

fn kinematicProcess(_: f32, pos: *Pos, kinematic: *Kinematic) void {
    var next = pos.last;
    next[0] = pos.pos[0];
    var hcol = map.collide(kinematic.col.addv(next));
    if (hcol.len > 0) {
        kinematic.lastCol[0] = next[0] - pos.last[0];
        next[0] = pos.last[0];
    } else if (!approxEqAbs(f32, next[0] - pos.last[0], 0, 0.01)) {
        kinematic.lastCol[0] = 0;
    }

    next[1] = pos.pos[1];
    var vcol = map.collide(kinematic.col.addv(next));
    if (vcol.len > 0) {
        kinematic.lastCol[1] = next[1] - pos.last[1];
        next[1] = pos.last[1];
    } else if (!approxEqAbs(f32, next[1] - pos.last[1], 0, 0.01)) {
        kinematic.lastCol[1] = 0;
    }

    var colPosAbs = next + kinematic.lastCol;
    var lastCol = map.collide(kinematic.col.addv(colPosAbs));
    if (lastCol.len == 0) {
        kinematic.lastCol = Vec2f{ 0, 0 };
    }

    kinematic.move = next - pos.last;

    pos.pos = next;
}

fn velocityProcess(_: f32, pos: *Pos) void {
    if (pos.pinned) return;
    var vel = pos.pos - pos.last;

    vel = @minimum(Vec2f{ 8, 8 }, @maximum(Vec2f{ -8, -8 }, vel));

    pos.last = pos.pos;
    pos.pos += vel;
}

fn physicsProcess(_: f32, pos: *Pos, physics: *Physics) void {
    if (pos.pinned) return;
    var friction = @splat(2, @as(f32, 1)) - physics.friction;
    pos.pos = pos.last + (pos.pos - pos.last) * friction;
    pos.pos += physics.gravity;
}
