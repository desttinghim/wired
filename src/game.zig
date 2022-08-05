const assets = @import("assets");
const std = @import("std");
const w4 = @import("wasm4.zig");
const input = @import("input.zig");
const util = @import("util.zig");
const Circuit = @import("circuit.zig");
const Map = @import("map.zig");
const Music = @import("music.zig");
const State = @import("main.zig").State;
// const Disk = @import("disk.zig");
const extract = @import("extract.zig");
const world = @import("world.zig");
const world_data = @embedFile(@import("world_data").path);

const Vec2 = util.Vec2;
const Vec2f = util.Vec2f;
const AABB = util.AABB;
const Anim = @import("anim.zig");

const comp = @import("component.zig");

const Pos = comp.Pos;
const Control = comp.Control;
const Sprite = comp.Sprite;
const ControlAnim = comp.ControlAnim;
const StaticAnim = comp.StaticAnim;
const Kinematic = comp.Kinematic;
const Physics = comp.Physics;
const AnimData = []const Anim.Ops;

const Wire = struct {
    nodes: std.BoundedArray(Pos, 32) = std.BoundedArray(Pos, 32).init(0),
    enabled: bool = false,

    pub fn begin(this: *@This()) *Pos {
        return &this.nodes.slice()[0];
    }

    pub fn end(this: *@This()) *Pos {
        return &this.nodes.slice()[this.nodes.len - 1];
    }

    pub fn straighten(this: *@This()) void {
        const b = this.begin().pos;
        const e = this.end().pos;
        const size = e - b;
        for (this.nodes.slice()) |*node, i| {
            if (i == 0 or i == this.nodes.len - 1) continue;
            node.pos = b + @splat(2, @intToFloat(f32, i)) * size / @splat(2, @intToFloat(f32, this.nodes.len));
        }
    }
};

const Player = struct {
    pos: Pos,
    control: Control,
    sprite: Sprite,
    controlAnim: ControlAnim,
    kinematic: Kinematic,
    physics: Physics,
};

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
    pub fn init() !@This() {
        return @This(){
            .particles = try std.BoundedArray(Particle, MAXPARTICLES).init(0),
        };
    }

    pub fn update(this: *@This()) !void {
        var physics = .{ .gravity = Vec2f{ 0, 0.1 }, .friction = Vec2f{ 0.1, 0.1 } };
        var remove = try std.BoundedArray(usize, MAXPARTICLES).init(0);
        for (this.particles.slice()) |*part, i| {
            if (!inView(part.pos.pos)) {
                try remove.append(i);
                continue;
            }
            velocityProcess(1, &part.pos);
            physicsProcess(1, &part.pos, &physics);
            part.life -= 1;
            if (part.life == 0) try remove.append(i);
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
        // Do nothing on error, we don't care if a particle
        // is dropped
        this.particles.append(part) catch {};
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

// Allocators
var fba_buf: [4096]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&fba_buf);
var alloc = fba.allocator();

var frame_fba_buf: [8192]u8 = undefined;
var frame_fba = std.heap.FixedBufferAllocator.init(&frame_fba_buf);
var frame_alloc = frame_fba.allocator();

// Global vars
var map: Map = undefined;
var circuit: Circuit = undefined;
var particles: ParticleSystem = undefined;
var prng = std.rand.DefaultPrng.init(0);
var random = prng.random();
pub var player: Player = undefined;
var music = Music.Procedural.init(.C3, &Music.Minor, 83);
pub var wires = std.BoundedArray(Wire, 10).init(0) catch unreachable;
var camera = Vec2{ 0, 0 };

const Coin = struct { pos: Pos, sprite: Sprite, anim: Anim, area: AABB };
pub var coins = std.BoundedArray(Coin, 20).init(0) catch unreachable;
pub var score: u8 = 0;
var ScoreCoin = Sprite{
    .size = Map.tile_size,
    .index = 4,
    .flags = .{ .bpp = .b2 },
};

var map_buf: [400]u8 = undefined;

var circuit_lvl_buf: [400]u8 = undefined;
var circuit_buf: [400]u8 = undefined;

var circuit_options: Circuit.Options = undefined;

pub const anim_store = struct {
    const stand = Anim.frame(8);
    const walk = Anim.simple(4, &[_]usize{ 9, 10, 11, 12 });
    const jump = Anim.frame(13);
    const fall = Anim.frame(14);
    const wallSlide = Anim.frame(15);
    pub const coin = Anim.simple(15, &[_]usize{ 4, 5, 6 });
};

const playerAnim = pac: {
    var animArr = std.BoundedArray(AnimData, 100).init(0) catch unreachable;
    animArr.append(&anim_store.stand) catch unreachable;
    animArr.append(&anim_store.walk) catch unreachable;
    animArr.append(&anim_store.jump) catch unreachable;
    animArr.append(&anim_store.fall) catch unreachable;
    animArr.append(&anim_store.wallSlide) catch unreachable;
    break :pac animArr.slice();
};

pub fn start() !void {
    particles = try ParticleSystem.init();

    var level_size = Vec2{ 20, 20 };

    circuit_options = .{
        .map = &circuit_buf,
        .levels = &circuit_lvl_buf,
        .map_size = level_size,
        .bridges = try alloc.alloc(Circuit.BridgeState, 5),
        .sources = try alloc.alloc(util.Cell, 5),
        .doors = try alloc.alloc(Circuit.DoorState, 5),
    };
    circuit = Circuit.init(circuit_options);

    map = Map.init(&map_buf, level_size);

    var stream = std.io.FixedBufferStream([]const u8){
        .pos = 0,
        .buffer = world_data,
    };
    const world_reader = stream.reader();

    var level = try world.Level.read(world_reader);
    var level_buf = try alloc.alloc(world.TileData, level.size);
    try level.readTiles(world_reader, level_buf);

    try extract.extractLevel(.{
        .alloc = frame_alloc,
        .level = level,
        .map = &map,
        .circuit = &circuit,
        .tileset = world.AutoTileset.initOffsetFull(113),
        .conduit = world.AutoTileset.initOffsetFull(97),
        .plug = world.AutoTileset.initOffsetCardinal(17),
        .switch_off = world.AutoTileset.initSwitches(&.{
            29, // South-North
            25, // South-West-North
            27, // South-East-North
        }, 2),
        .switch_on = world.AutoTileset.initSwitches(&.{
            30, // South-North
            26, // South-West-North
            28, // South-East-West
        }, 2),
    });

    var entity_buf = try alloc.alloc(world.Entity, level.entity_count);
    try level.readEntities(world_reader, entity_buf);

    const spawnArr = level.getSpawn().?;
    const spawn = Vec2{ spawnArr[0], spawnArr[1] };

    camera = @divTrunc(spawn, @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20));

    const tile_size = Vec2{ 8, 8 };
    const offset = Vec2{ 4, 8 };

    player = .{
        .pos = Pos.init(util.vec2ToVec2f(spawn * tile_size + offset)),
        .control = .{ .controller = .player, .state = .stand },
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 8, .flags = .{ .bpp = .b2 } },
        .physics = .{ .friction = Vec2f{ 0.15, 0.1 }, .gravity = Vec2f{ 0, 0.25 } },
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
        .kinematic = .{ .col = .{ .pos = .{ -3, -6 }, .size = .{ 5, 5 } } },
    };

    {
        _ = try wires.resize(0);
        var a: usize = 0;
        while (level.getWire(a)) |wire| : (a += 1) {
            const p1 = util.vec2ToVec2f(Vec2{ wire[0].x, wire[0].y } * tile_size + Vec2{ 4, 4 });
            const p2 = util.vec2ToVec2f(Vec2{ wire[1].x, wire[1].y } * tile_size + Vec2{ 4, 4 });

            var w = try wires.addOne();
            _ = try w.nodes.resize(0);
            // const divisions = wire.divisions;
            const divisions = 10;
            var i: usize = 0;
            while (i <= divisions) : (i += 1) {
                try w.nodes.append(Pos.init(p1));
            }
            w.begin().pos = p1;
            w.end().pos = p2;

            w.begin().pinned = wire[0].kind == world.EntityKind.WireAnchor;
            w.end().pinned = wire[1].kind == world.EntityKind.WireEndAnchor;

            w.straighten();
        }
    }

    {
        var i: usize = 0;
        while (level.getDoor(i)) |door| : (i += 1) {
            try circuit.addDoor(Vec2{ door.x, door.y });
        }
    }

    try coins.resize(0);
    // if (!try Disk.load()) {
    var i: usize = 0;
    while (level.getCoin(i)) |coin| : (i += 1) {
        try coins.append(.{
            .pos = Pos.init(util.vec2ToVec2f(Vec2{ coin.x, coin.y } * tile_size)),
            .sprite = .{ .offset = .{ 0, 0 }, .size = .{ 8, 8 }, .index = 4, .flags = .{ .bpp = .b2 } },
            .anim = Anim{ .anim = &anim_store.coin },
            .area = .{ .pos = .{ 0, 0 }, .size = .{ 8, 8 } },
        });
    }
    // }

    try updateCircuit();
}

var indicator: ?Interaction = null;

pub fn update(time: usize) !State {
    // Clear the frame buffer
    frame_fba.reset();

    for (wires.slice()) |*wire| {
        try wirePhysicsProcess(1, wire);
        if (wire.enabled) {
            if (music.isDrumBeat()) {
                if (!wire.begin().pinned) particles.createNRandom(wire.begin().pos, 8);
                if (!wire.end().pinned) particles.createNRandom(wire.end().pos, 8);
            }
        }
    }

    velocityProcess(1, &player.pos);
    physicsProcess(1, &player.pos, &player.physics);
    try manipulationProcess(&player.pos, &player.control);
    controlProcess(time, &player.pos, &player.control, &player.physics, &player.kinematic);
    try kinematicProcess(1, &player.pos, &player.kinematic);
    controlAnimProcess(1, &player.sprite, &player.controlAnim, &player.control);
    try particles.update();

    // Drawing
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });
    drawProcess(1, &player.pos, &player.sprite);

    {
        var shouldSave = false;
        var remove = try std.BoundedArray(usize, 10).init(0);
        for (coins.slice()) |*coin, i| {
            staticAnimProcess(1, &coin.sprite, &coin.anim);
            drawProcess(1, &coin.pos, &coin.sprite);
            if (coin.area.addv(coin.pos.pos).overlaps(player.kinematic.col.addv(player.pos.pos))) {
                score += 1;
                try remove.append(i);
                music.playCollect(score);
                shouldSave = true;
            }
        }
        while (remove.popOrNull()) |i| {
            _ = coins.swapRemove(i);
        }
        // We save here to prevent duplicate coins
        // if (shouldSave) Disk.save();
    }

    const newCamera = @divTrunc(util.world2cell(player.pos.pos), @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20));
    if (!@reduce(.And, newCamera == camera)) {
        // Disk.save();
    }
    camera = newCamera;

    map.draw(camera);
    circuit.draw(camera);

    for (wires.slice()) |*wire| {
        wireDrawProcess(1, wire);
    }

    particles.draw();

    {
        const pos = player.pos.pos;
        if (getNearestWireInteraction(pos, 8)) |i| {
            _ = i;
            // Uncomment for death
            // const wire = wires.get(i.details.wire.id);
            // const node = wire.nodes.get(i.details.wire.which);
            // if (i.active and !node.pinned) {
            //     try start();
            // }
        }
    }

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
    const musicCommand = try music.getNext(1, frame_alloc);
    for (musicCommand.items) |sfx| {
        w4.tone(sfx.freq, sfx.duration, sfx.volume, sfx.flags);
    }

    indicator = null;
    return .Game;
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

fn getNearestPlugInteraction(pos: Vec2f, wireID: usize, which: usize) ?Interaction {
    const cell = util.world2cell(pos);
    if (circuit.get_cell(cell)) |tile| {
        if (Circuit.is_plug(tile)) {
            const active = circuit.isEnabled(cell);
            return Interaction{
                .details = .{ .plug = .{ .wireID = wireID, .which = which } },
                .pos = cell * Map.tile_size + Vec2{ 4, 4 },
                .active = active,
            };
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

fn manipulationProcess(pos: *Pos, control: *Control) !void {
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

        if (getNearestPlugInteraction(offsetPos, details.id, details.which)) |i| {
            indicator = i;
        } else if (getNearestPlugInteraction(centeredPos, details.id, details.which)) |i| {
            indicator = i;
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
                    try updateCircuit();
                },
                .plug => |plug| {
                    wires.slice()[plug.wireID].nodes.slice()[plug.which].pos = vec2tovec2f(indicator.?.pos);
                    wires.slice()[plug.wireID].nodes.slice()[plug.which].pinned = true;
                    control.grabbing = null;
                    try updateCircuit();
                },
                .lever => {
                    const cell = @divTrunc(i.pos, Map.tile_size);
                    circuit.toggle(cell);
                    try updateCircuit();
                },
            }
        }
    }
}

fn updateCircuit() !void {
    circuit.clear();
    for (wires.slice()) |*wire, wireID| {
        wire.enabled = false;
        if (!wire.begin().pinned or !wire.end().pinned) continue;
        const nodes = wire.nodes.constSlice();
        const cellBegin = util.world2cell(nodes[0].pos);
        const cellEnd = util.world2cell(nodes[nodes.len - 1].pos);

        circuit.bridge(.{ cellBegin, cellEnd }, wireID);
    }
    _ = try circuit.fill(frame_alloc);
    for (wires.slice()) |*wire| {
        const begin = wire.begin();
        const end = wire.end();
        const cellBegin = util.world2cell(begin.pos);
        const cellEnd = util.world2cell(end.pos);
        if ((circuit.isEnabled(cellBegin) and begin.pinned) or
            (circuit.isEnabled(cellEnd) and end.pinned)) wire.enabled = true;
    }
    // map.reset(&assets.solid);
    // const enabledDoors = try circuit.enabledDoors(frame_alloc);
    // for (enabledDoors.items) |door| {
    //     try map.set_cell(door, 0);
    // }
}

fn wirePhysicsProcess(dt: f32, wire: *Wire) !void {
    var nodes = wire.nodes.slice();
    if (nodes.len == 0) return;
    if (!inView(wire.begin().pos) and !inView(wire.end().pos)) return;
    var physics = Physics{ .gravity = Vec2f{ 0, 0.25 }, .friction = Vec2f{ 0.1, 0.1 } };
    var kinematic = Kinematic{ .col = AABB{ .pos = Vec2f{ -1, -1 }, .size = Vec2f{ 1, 1 } } };

    for (nodes) |*node| {
        velocityProcess(dt, node);
        physicsProcess(dt, node, &physics);
        try kinematicProcess(dt, node, &kinematic);
    }

    var iterations: usize = 0;
    while (iterations < 4) : (iterations += 1) {
        var left: usize = 1;
        while (left < nodes.len) : (left += 1) {
            // Left side
            constrainNodes(&nodes[left - 1], &nodes[left]);
            try kinematicProcess(dt, &nodes[left - 1], &kinematic);
            try kinematicProcess(dt, &nodes[left], &kinematic);
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

fn controlProcess(time: usize, pos: *Pos, control: *Control, physics: *Physics, kinematic: *Kinematic) void {
    var delta = Vec2f{ 0, 0 };
    if (kinematic.pass_start) |pass_start| {
        if (time - pass_start > 10) {
            kinematic.pass_start = null;
        }
    }
    if (approxEqAbs(f32, kinematic.move[1], 0, 0.01) and kinematic.lastCol[1] > 0) {
        if (input.btnp(.one, .one)) delta[1] -= 23;
        if (input.btn(.one, .left)) delta[0] -= 1;
        if (input.btn(.one, .right)) delta[0] += 1;
        if (input.btn(.one, .down)) kinematic.pass_start = time;
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

fn kinematicProcess(_: f32, pos: *Pos, kinematic: *Kinematic) !void {
    const is_passing = kinematic.pass_start != null;
    var next = pos.last;
    next[0] = pos.pos[0];
    var hcol = map.collide(.{
        .rect = kinematic.col.addv(next),
        .last = pos.last,
        .next = next,
        .is_passing = is_passing,
    });
    if (hcol.len > 0) {
        kinematic.lastCol[0] = next[0] - pos.last[0];
        next[0] = pos.last[0];
    } else if (!approxEqAbs(f32, next[0] - pos.last[0], 0, 0.01)) {
        kinematic.lastCol[0] = 0;
    }

    next[1] = pos.pos[1];
    var vcol = map.collide(.{
        .rect = kinematic.col.addv(next),
        .last = pos.last,
        .next = next,
        .is_passing = is_passing,
    });
    if (vcol.len > 0) {
        kinematic.lastCol[1] = next[1] - pos.last[1];
        next[1] = pos.last[1];
    } else if (!approxEqAbs(f32, next[1] - pos.last[1], 0, 0.01)) {
        kinematic.lastCol[1] = 0;
    }

    var colPosAbs = next + kinematic.lastCol;
    var lastCol = map.collide(.{
        .rect = kinematic.col.addv(colPosAbs),
        .last = pos.last,
        .next = next,
        .is_passing = is_passing,
    });
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
