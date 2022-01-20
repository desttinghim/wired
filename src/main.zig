const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");
const input = @import("input.zig");
const util = @import("util.zig");
const Circuit = @import("circuit.zig");
const Map = @import("map.zig");

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
};
const Control = struct {
    controller: enum { player },
    state: enum { stand, walk, jump, fall, wallSlide },
    facing: enum { left, right, up, down } = .right,
    grabbing: ?struct { id: usize, which: usize } = null,
};
const Sprite = struct { offset: Vec2f = Vec2f{ 0, 0 }, size: w4.Vec2, index: usize, flags: w4.BlitFlags };
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
const Wire = struct { nodes: std.BoundedArray(Pos, 32), enabled: bool = false };
const Physics = struct { gravity: Vec2f, friction: Vec2f };
const Component = struct {
    pos: Pos,
    control: Control,
    sprite: Sprite,
    staticAnim: StaticAnim,
    controlAnim: ControlAnim,
    kinematic: Kinematic,
    wire: Wire,
    physics: Physics,
};
const World = ecs.World(Component);

// Global vars
const KB = 1024;
var heap: [16 * KB]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap);
var world: World = World.init(fba.allocator());
var map: Map = undefined;
var circuit: Circuit = undefined;

const anim_store = struct {
    const stand = Anim.frame(0);
    const walk = Anim.simple(4, &[_]usize{ 1, 2, 3, 4 });
    const jump = Anim.frame(5);
    const fall = Anim.frame(6);
    const wallSlide = Anim.frame(7);
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
    w4.trace("{s}", .{msg});
    unreachable;
}

export fn start() void {
    circuit = Circuit.init();
    map = Map.init(fba.allocator()) catch showErr("Init map");

    const mapPos = @divTrunc(assets.spawn, @splat(2, @as(i32, 20))) * @splat(2, @as(i32, 20));
    circuit.load(mapPos, &assets.conduit, assets.conduit_size);
    map.load(mapPos, &assets.solid, assets.solid_size);

    w4.trace("{}, {}, {}", .{ assets.spawn, mapPos, assets.spawn - mapPos });

    _ = world.create(.{
        .pos = Pos.init(util.vec2ToVec2f((assets.spawn - mapPos) * Map.tile_size) + Vec2f{ 4, 8 }),
        .control = .{ .controller = .player, .state = .stand },
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 0, .flags = .{ .bpp = .b1 } },
        .physics = .{ .friction = Vec2f{ 0.15, 0.1 }, .gravity = Vec2f{ 0, 0.25 } },
        .controlAnim = ControlAnim{
            .anims = playerAnim,
            .state = Anim{ .anim = &.{} },
        },
        .kinematic = .{ .col = .{ .pos = .{ -3, -6 }, .size = .{ 5, 5 } } },
    }) catch showErr("Creating player");

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
        _ = world.create(.{
            .wire = w,
        }) catch showErr("Adding wire entity");
    }
}

var indicator: ?struct { pos: Vec2, t: enum { wire, plug, lever }, active: bool = false } = null;
var time: usize = 0;

export fn update() void {
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });

    {
        circuit.clear();
        const q = World.Query.require(&.{.wire});
        var wireIter = world.iter(q);
        while (wireIter.next()) |wireID| {
            const e = world.get(wireID);
            const nodes = e.wire.?.nodes.constSlice();
            const cellBegin = util.world2cell(nodes[0].pos);
            const cellEnd = util.world2cell(nodes[nodes.len - 1].pos);

            circuit.bridge(.{ cellBegin, cellEnd }, wireID);
        }
        for (assets.sources) |source| {
            circuit.fill(source);
        }
        var wireComponents = world.components.items(.wire);
        var enabledWires = circuit.enabledBridges();
        for (enabledWires.slice()) |wireID| {
            wireComponents[wireID].?.enabled = true;
        }
    }

    world.process(1, &.{.pos}, velocityProcess);
    world.process(1, &.{ .pos, .physics }, physicsProcess);
    world.process(1, &.{ .pos, .control }, wireManipulationProcess);
    world.process(1, &.{ .pos, .control }, circuitManipulationProcess);
    world.process(1, &.{.wire}, wirePhysicsProcess);
    world.process(1, &.{ .pos, .control, .physics, .kinematic }, controlProcess);
    world.process(1, &.{ .pos, .kinematic }, kinematicProcess);
    world.process(1, &.{ .sprite, .staticAnim }, staticAnimProcess);
    world.process(1, &.{ .sprite, .controlAnim, .control }, controlAnimProcess);
    world.process(1, &.{ .pos, .sprite }, drawProcess);

    map.draw();

    for (circuit.cells) |cell, i| {
        const tilePlus = cell.tile;
        if (tilePlus == 0) continue;
        if (circuit.cells[i].enabled) w4.DRAW_COLORS.* = 0x0210 else w4.DRAW_COLORS.* = 0x0310;
        const tile = tilePlus - 1;
        const t = w4.Vec2{ @intCast(i32, (tile % 16) * 8), @intCast(i32, (tile / 16) * 8) };
        const pos = w4.Vec2{ @intCast(i32, (i % 20) * 8), @intCast(i32, (i / 20) * 8) };
        w4.blitSub(&assets.tiles, pos, .{ 8, 8 }, t, 128, .{ .bpp = .b2 });
    }

    world.process(1, &.{.wire}, wireDrawProcess);

    if (indicator) |details| {
        const pos = details.pos;
        const stage = @divTrunc((time % 60), 30);
        var size = Vec2{ 0, 0 };
        switch (stage) {
            0 => size = Vec2{ 6, 6 },
            else => size = Vec2{ 8, 8 },
        }

        if (details.active) {
            w4.tone(.{ .start = 60, .end = 1 }, .{ .release = 30, .sustain = 0 }, 10, .{ .channel = .triangle });
            w4.DRAW_COLORS.* = 0x0020;
        } else {
            w4.DRAW_COLORS.* = 0x0030;
        }
        var half = Vec2{ @divTrunc(size[0], 2), @divTrunc(size[1], 2) };
        switch (details.t) {
            .wire => w4.oval(pos - half, size),
            .plug => w4.rect(pos - half, size),
            .lever => w4.rect(pos - half, size),
        }
    }

    indicator = null;
    input.update();
    time += 1;
}

fn circuitManipulationProcess(_: f32, pos: *Pos, control: *Control) void {
    var offset = switch (control.facing) {
        .left => Vec2f{ -6, -4 },
        .right => Vec2f{ 6, -4 },
        .up => Vec2f{ 0, -12 },
        .down => Vec2f{ 0, 4 },
    };
    if (control.grabbing == null) {
        const mapPos = vec2ftovec2(pos.pos + offset);
        const cell = @divTrunc(mapPos, @splat(2, @as(i32, 8)));
        if (circuit.get_cell(cell)) |tile| {
            if (Circuit.is_switch(tile)) {
                indicator = .{ .t = .lever, .pos = cell * @splat(2, @as(i32, 8)) + Vec2{ 4, 4 } };
                if (input.btnp(.one, .two)) {
                    circuit.toggle(cell);
                }
            }
        }
    }
}

fn wireManipulationProcess(_: f32, pos: *Pos, control: *Control) void {
    var offset = switch (control.facing) {
        .left => Vec2f{ -6, -4 },
        .right => Vec2f{ 6, -4 },
        .up => Vec2f{ 0, -12 },
        .down => Vec2f{ 0, 4 },
    };
    var offsetPos = pos.pos + offset;
    var entity: World.Component = undefined;
    var mapPos = util.world2cell(offsetPos);

    if (control.grabbing) |details| {
        entity = world.get(details.id);
        var wire = &entity.wire.?;
        var nodes = wire.nodes.slice();

        var maxLength = wireMaxLength(wire);
        var length = wireLength(wire);

        if (length > maxLength * 1.5) {
            nodes[details.which].pinned = false;
            control.grabbing = null;
            world.set(details.id, entity);
            return;
        } else {
            nodes[details.which].pos = pos.pos + Vec2f{ 0, -4 };
        }

        if (Circuit.is_plug(circuit.get_cell(mapPos) orelse 0)) {
            const active = circuit.isEnabled(mapPos);
            indicator = .{ .t = .plug, .pos = mapPos * @splat(2, @as(i32, 8)) + Vec2{ 4, 4 }, .active = active };
            if (input.btnp(.one, .two)) {
                nodes[details.which].pinned = true;
                nodes[details.which].pos = vec2tovec2f(indicator.?.pos);
                nodes[details.which].last = vec2tovec2f(indicator.?.pos);
                control.grabbing = null;
            }
        } else if (input.btnp(.one, .two)) {
            nodes[details.which].pinned = false;
            control.grabbing = null;
        }
        world.set(details.id, entity);
    } else {
        const interactDistance = 4;
        var minDistance: f32 = interactDistance;
        const q = World.Query.require(&.{.wire});
        var wireIter = world.iter(q);
        var interactWireID: ?usize = null;
        var which: usize = 0;
        while (wireIter.next()) |entityID| {
            entity = world.get(entityID);
            const wire = entity.wire.?;
            const nodes = wire.nodes.constSlice();
            const begin = nodes[0].pos;
            const end = nodes[wire.nodes.len - 1].pos;
            var dist = util.distancef(begin, offsetPos);
            if (dist < minDistance) {
                minDistance = dist;
                indicator = .{ .t = .wire, .pos = vec2ftovec2(begin), .active = wire.enabled };
                interactWireID = entityID;
                which = 0;
            }
            dist = util.distancef(end, offsetPos);
            if (dist < minDistance) {
                minDistance = dist;
                indicator = .{ .t = .wire, .pos = vec2ftovec2(end), .active = wire.enabled };
                interactWireID = entityID;
                which = wire.nodes.len - 1;
            }
        }
        if (interactWireID) |wireID| {
            entity = world.get(wireID);
            if (input.btnp(.one, .two)) {
                control.grabbing = .{ .id = wireID, .which = which };
            }
            world.set(wireID, entity);
        }
    }
}

fn wirePhysicsProcess(dt: f32, wire: *Wire) void {
    var nodes = wire.nodes.slice();
    if (nodes.len == 0) return;

    for (nodes) |*node| {
        var physics = Physics{ .gravity = Vec2f{ 0, 0.25 }, .friction = Vec2f{ 0.1, 0.1 } };
        velocityProcess(dt, node);
        physicsProcess(dt, node, &physics);
        collideNode(node);
    }

    var iterations: usize = 0;
    while (iterations < 4) : (iterations += 1) {
        var left: usize = 1;
        while (left < nodes.len) : (left += 1) {
            // Left side
            constrainNodes(&nodes[left - 1], &nodes[left]);
            collideNode(&nodes[left - 1]);
            collideNode(&nodes[left]);
        }
    }
}

/// Returns normal of collision
fn collideNode(node: *Pos) void {
    if (node.pinned) return;
    const tileSize = Vec2{ 8, 8 };
    const tileSizef = vec2tovec2f(tileSize);
    const iPos = vec2ftovec2(node.pos);
    const mapPos = @divTrunc(iPos, tileSize);
    if (map.isSolid(mapPos)) {
        const velNorm = util.normalizef(node.pos - node.last);
        var collideVec = node.last;
        while (!map.isSolid(vec2ftovec2((collideVec + velNorm) / tileSizef))) {
            collideVec += velNorm;
        }
        node.pos = collideVec;
    }
}

const wireSegmentMaxLength = 4;
const wireSegmentMaxLengthV = @splat(2, @as(f32, wireSegmentMaxLength));

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

    w4.DRAW_COLORS.* = if (wire.enabled) 0x0002 else 0x0003;
    for (nodes) |node, i| {
        if (i == 0) continue;
        w4.line(vec2ftovec2(nodes[i - 1].pos), vec2ftovec2(node.pos));
    }
    wire.enabled = false;
}

fn vec2tovec2f(vec2: w4.Vec2) Vec2f {
    return Vec2f{ @intToFloat(f32, vec2[0]), @intToFloat(f32, vec2[1]) };
}

fn vec2ftovec2(vec2f: Vec2f) w4.Vec2 {
    return w4.Vec2{ @floatToInt(i32, vec2f[0]), @floatToInt(i32, vec2f[1]) };
}

fn drawProcess(_: f32, pos: *Pos, sprite: *Sprite) void {
    w4.DRAW_COLORS.* = 0x0010;
    const fpos = pos.pos + sprite.offset;
    const ipos = w4.Vec2{ @floatToInt(i32, fpos[0]), @floatToInt(i32, fpos[1]) };
    const t = w4.Vec2{ @intCast(i32, (sprite.index * 8) % 128), @intCast(i32, (sprite.index * 8) / 128) };
    w4.blitSub(&assets.sprites, ipos, sprite.size, t, 128, sprite.flags);
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
