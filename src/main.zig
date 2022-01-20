const std = @import("std");
const w4 = @import("wasm4.zig");
const ecs = @import("ecs.zig");
const assets = @import("assets");
const input = @import("input.zig");
const Circuit = @import("circuit.zig");

const Vec2 = std.meta.Vector(2, i32);
const Vec2f = std.meta.Vector(2, f32);
const AABB = struct {
    pos: Vec2f,
    size: Vec2f,

    pub fn addv(this: @This(), vec2f: Vec2f) @This() {
        return @This(){ .pos = this.pos + vec2f, .size = this.size };
    }
};
const Anim = struct {
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
        inline for (arr) |item, i| {
            anim[i * 2] = Ops{ .Index = item };
            anim[i * 2 + 1] = Ops{ .Wait = rate };
        }
        return anim;
    }

    pub fn frame(comptime index: usize) [2]Ops {
        return [_]Ops{ .{ .Index = index }, .Stop };
    }
};

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
const Wire = struct { nodes: std.BoundedArray(Pos, 32) };
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
var heap: [8 * KB]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&heap);
var world: World = World.init(fba.allocator());
var circuit = Circuit.init(Vec2{ 0, 0 }, &assets.conduit);

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
    _ = world.create(.{
        .pos = Pos.init(Vec2f{ 100, 80 }),
        .control = .{ .controller = .player, .state = .stand },
        .sprite = .{ .offset = .{ -4, -8 }, .size = .{ 8, 8 }, .index = 0, .flags = .{ .bpp = .b1 } },
        .physics = .{ .friction = Vec2f{ 0.05, 0.01 }, .gravity = Vec2f{ 0, 0.25 } },
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
        const divisions = @floatToInt(usize, vec_length(size) / 6);
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

    for (assets.sources) |source| {
        circuit.fill(source);
    }
}

var indicator: ?struct { pos: Vec2, t: enum { wire, plug } } = null;
var time: usize = 0;

export fn update() void {
    w4.DRAW_COLORS.* = 0x0004;
    w4.rect(.{ 0, 0 }, .{ 160, 160 });

    world.process(1, &.{.pos}, velocityProcess);
    world.process(1, &.{ .pos, .physics }, physicsProcess);
    world.processWithID(1, &.{ .pos, .control }, wireManipulationProcess);
    world.processWithID(1, &.{ .pos, .control }, circuitManipulationProcess);
    world.process(1, &.{.wire}, wirePhysicsProcess);
    world.process(1, &.{ .pos, .control, .physics, .kinematic }, controlProcess);
    world.process(1, &.{ .pos, .kinematic }, kinematicProcess);
    world.process(1, &.{ .sprite, .staticAnim }, staticAnimProcess);
    world.process(1, &.{ .sprite, .controlAnim, .control }, controlAnimProcess);
    world.process(1, &.{ .pos, .sprite }, drawProcess);

    {
        circuit.clear();
        const q = World.Query.require(&.{.wire});
        var wireIter = world.iter(q);
        while (wireIter.next()) |wireID| {
            const e = world.get(wireID);
            const nodes = e.wire.?.nodes.constSlice();
            const cellBegin = world2cell(nodes[0].pos);
            const cellEnd = world2cell(nodes[nodes.len - 1].pos);

            circuit.bridge(.{ cellBegin, cellEnd });
        }
        for (assets.sources) |source| {
            circuit.fill(source);
        }
    }

    w4.DRAW_COLORS.* = 0x0210;
    for (assets.solid) |tilePlus, i| {
        const tile = tilePlus - 1;
        const t = w4.Vec2{ @intCast(i32, (tile % 16) * 8), @intCast(i32, (tile / 16) * 8) };
        const pos = w4.Vec2{ @intCast(i32, (i % 20) * 8), @intCast(i32, (i / 20) * 8) };
        w4.blitSub(&assets.tiles, pos, .{ 8, 8 }, t, 128, .{ .bpp = .b2 });
    }

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
            // 1 => size = Vec2{ 5, 5 },
            else => size = Vec2{ 8, 8 },
        }

        w4.DRAW_COLORS.* = 0x0020;
        var half = Vec2{ @divTrunc(size[0], 2), @divTrunc(size[1], 2) };
        // w4.trace("{}", .{half});
        switch (details.t) {
            .wire => w4.oval(pos - half, size),
            .plug => w4.rect(pos - half, size),
        }
    }

    indicator = null;
    input.update();
    time += 1;
}

fn world2cell(vec: Vec2f) Vec2 {
    return vec2ftovec2(vec / @splat(2, @as(f32, 8)));
}

/// pos should be in tile coordinates, not world coordinates
fn get_conduit(vec: Vec2) ?u8 {
    const x = vec[0];
    const y = vec[1];
    if (x < 0 or x > 19 or y < 0 or y > 19) return null;
    const i = x + y * 20;
    return assets.conduit[@intCast(u32, i)];
}

fn circuitManipulationProcess(_: f32, id: usize, pos: *Pos, control: *Control) void {
    _ = id;
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
                indicator = .{ .t = .plug, .pos = cell * @splat(2, @as(i32, 8)) + Vec2{ 4, 4 } };
                if (input.btnp(.one, .two)) {
                    circuit.toggle(cell);
                }
            }
        }
    }
}

fn wireManipulationProcess(_: f32, id: usize, pos: *Pos, control: *Control) void {
    var offset = switch (control.facing) {
        .left => Vec2f{ -6, -4 },
        .right => Vec2f{ 6, -4 },
        .up => Vec2f{ 0, -12 },
        .down => Vec2f{ 0, 4 },
    };
    if (control.grabbing) |details| {
        _ = details;
        _ = id;
        var e = world.get(details.id);
        var wire = &e.wire.?;
        var nodes = wire.nodes.slice();

        var maxLength = wireMaxLength(wire);
        var length = wireLength(wire);

        if (length > maxLength * 1.5) {
            nodes[details.which].pinned = false;
            control.grabbing = null;
            world.set(details.id, e);
            return;
        } else {
            nodes[details.which].pos = pos.pos + Vec2f{ 0, -4 };
        }

        var mapPos = vec2ftovec2((pos.pos + offset) / @splat(2, @as(f32, 8)));
        if (Circuit.is_plug(circuit.get_cell(mapPos) orelse 0)) {
            indicator = .{ .t = .plug, .pos = mapPos * @splat(2, @as(i32, 8)) + Vec2{ 4, 4 } };
            if (input.btnp(.one, .two)) {
                e.wire.?.nodes.slice()[details.which].pinned = true;
                e.wire.?.nodes.slice()[details.which].pos = vec2tovec2f(indicator.?.pos);
                e.wire.?.nodes.slice()[details.which].last = vec2tovec2f(indicator.?.pos);
                control.grabbing = null;
            }
        } else if (input.btnp(.one, .two)) {
            e.wire.?.nodes.slice()[details.which].pinned = false;
            control.grabbing = null;
        }
        world.set(details.id, e);
    } else {
        const interactDistance = 4;
        var minDistance: f32 = interactDistance;
        var wireIter = world.iter(World.Query.require(&.{.wire}));
        var interactWireID: ?usize = null;
        var which: usize = 0;
        while (wireIter.next()) |entityID| {
            const entity = world.get(entityID);
            const wire = entity.wire.?;
            const nodes = wire.nodes.constSlice();
            const begin = nodes[0].pos;
            const end = nodes[wire.nodes.len - 1].pos;
            var beginDist = distancef(begin, pos.pos + offset);
            var endDist = distancef(end, pos.pos + offset);
            if (beginDist < minDistance) {
                minDistance = beginDist;
                indicator = .{ .t = .wire, .pos = vec2ftovec2(begin) };
                interactWireID = entityID;
                which = 0;
            } else if (endDist < minDistance) {
                minDistance = endDist;
                indicator = .{ .t = .wire, .pos = vec2ftovec2(end) };
                interactWireID = entityID;
                which = wire.nodes.len - 1;
            }
        }
        if (interactWireID) |wireID| {
            _ = wireID;
            var entity = world.get(wireID);
            if (input.btnp(.one, .two)) {
                control.grabbing = .{ .id = wireID, .which = which };
                // entity.wire.?.nodes.slice()[which].pinned = true;
            }
            world.set(wireID, entity);
        }
    }
}

fn distance(a: w4.Vec2, b: w4.Vec2) i32 {
    var subbed = a - b;
    subbed[0] = std.math.absInt(subbed[0]) catch unreachable;
    subbed[1] = std.math.absInt(subbed[1]) catch unreachable;
    return @reduce(.Max, subbed);
}

fn distancef(a: Vec2f, b: Vec2f) f32 {
    var subbed = @fabs(a - b);
    return @reduce(.Max, subbed);
}

fn is_solid(pos: Vec2) bool {
    if (get_tile(pos[0], pos[1])) |tile| {
        return tile != 1;
    }
    return true;
}

fn vec_length(vec: Vec2f) f32 {
    var squared = vec * vec;
    return @sqrt(@reduce(.Add, squared));
}

fn normalize(vec: Vec2f) Vec2f {
    return vec / @splat(2, vec_length(vec));
}

fn wirePhysicsProcess(dt: f32, wire: *Wire) void {
    var nodes = wire.nodes.slice();
    if (nodes.len == 0) return;

    for (nodes) |*node| {
        var physics = Physics{ .gravity = Vec2f{ 0, 0.25 }, .friction = Vec2f{ 0.05, 0.05 } };
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
    if (is_solid(mapPos)) {
        const velNorm = normalize(node.pos - node.last);
        var collideVec = node.last;
        while (!is_solid(vec2ftovec2((collideVec + velNorm) / tileSizef))) {
            collideVec += velNorm;
        }
        node.pos = collideVec;
    }
}

const Hit = struct {
    delta: Vec2f,
    normal: Vec2f,
    pos: Vec2f,
};
const mapTileVecf = Vec2f{ 8, 8 };
const mapTileVec = Vec2{ 8, 8 };
/// Returns delta
fn collidePointMap(point: Vec2f) ?Hit {
    const cell = vec2ftovec2(point / mapTileVecf);
    const mapPos = vec2tovec2f(cell * mapTileVec);
    const half = (mapTileVecf / @splat(2, @as(f32, 2)));
    if (is_solid(cell)) {
        const diff = mapPos - point;
        const p = half - @fabs(diff);
        var delta = Vec2f{ 0, 0 };
        var normal = Vec2f{ 0, 0 };
        var pos = Vec2f{ 0, 0 };
        if (p[0] > p[1]) {
            const sx = std.math.copysign(f32, 1, delta[0]);
            delta[0] = p[0] * sx;
            normal[0] = sx;
            pos = Vec2f{ point[0] + (half[0] * sx), point[1] };
        } else {
            const sy = std.math.copysign(f32, 1, delta[1]);
            delta[1] = p[1] * sy;
            normal[1] = sy;
            pos = Vec2f{ point[0], point[1] + (half[1] * sy) };
        }
        return Hit{
            .delta = delta,
            .normal = normal,
            .pos = pos,
        };
    }
    return null;
}

const wireSegmentMaxLength = 4;
const wireSegmentMaxLengthV = @splat(2, @as(f32, wireSegmentMaxLength));

// fn constrainToAnchor(anchor: *Pos, node: *Pos) void {
//     var diff = anchor.pos - node.pos;
//     var dist = distancef(node.pos, anchor.pos);
//     var wireLength = @maximum(wireSegmentMaxLength, dist);
//     node.pos = anchor.pos - (normalize(diff) * @splat(2, @as(f32, wireLength)));
// }

fn wireMaxLength(wire: *Wire) f32 {
    return @intToFloat(f32, wire.nodes.len) * wireSegmentMaxLength;
}

fn wireLength(wire: *Wire) f32 {
    var nodes = wire.nodes.slice();
    var length: f32 = 0;
    var i: usize = 1;
    while (i < nodes.len) : (i += 1) {
        length += distancef(nodes[i - 1].pos, nodes[i].pos);
    }
    return length;
}

fn tension(prevNode: *Pos, node: *Pos) f32 {
    var dist = distancef(node.pos, prevNode.pos);
    var difference: f32 = 0;
    if (dist > 0) {
        difference = (@minimum(dist, wireSegmentMaxLength) - dist) / dist;
    }
    return difference;
}

fn constrainNodes(prevNode: *Pos, node: *Pos) void {
    var diff = prevNode.pos - node.pos;
    var dist = distancef(node.pos, prevNode.pos);
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

    w4.DRAW_COLORS.* = 0x0002;
    for (nodes) |node, i| {
        if (i == 0) continue;
        w4.line(vec2ftovec2(nodes[i - 1].pos), vec2ftovec2(node.pos));
    }
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

/// pos should be in tile coordinates, not world coordinates
fn get_tile(x: i32, y: i32) ?u8 {
    if (x < 0 or x > 19 or y < 0 or y > 19) return null;
    const i = x + y * 20;
    return assets.solid[@intCast(u32, i)];
}

fn getTile(cell: Vec2) ?u8 {
    const x = cell[0];
    const y = cell[1];
    if (x < 0 or x > 19 or y < 0 or y > 19) return null;
    const i = x + y * 20;
    return assets.solid[@intCast(u32, i)];
}

fn cellCollider(cell: Vec2) AABB {
    const tileSize = 8;
    return AABB{
        .pos = vec2tovec2f(cell * tileSize),
        .size = @splat(2, @as(f32, tileSize)),
    };
}

/// rect should be absolutely positioned. Add pos to kinematic.collider
fn level_collide(rect: AABB) std.BoundedArray(AABB, 9) {
    const tileSize = 8;
    const top_left = rect.pos / @splat(2, @as(f32, tileSize));
    const bot_right = (rect.pos + rect.size) / @splat(2, @as(f32, tileSize));
    var collisions = std.BoundedArray(AABB, 9).init(0) catch unreachable;

    var i: isize = @floatToInt(i32, top_left[0]);
    while (i <= @floatToInt(i32, bot_right[0])) : (i += 1) {
        var a: isize = @floatToInt(i32, top_left[1]);
        while (a <= @floatToInt(i32, bot_right[1])) : (a += 1) {
            var tile = get_tile(i, a);
            if (tile == null or tile.? != 1) {
                collisions.append(AABB{
                    .pos = Vec2f{
                        @intToFloat(f32, i * tileSize),
                        @intToFloat(f32, a * tileSize),
                    },
                    .size = Vec2f{ tileSize, tileSize },
                }) catch unreachable;
            }
        }
    }

    return collisions;
}

fn kinematicProcess(_: f32, pos: *Pos, kinematic: *Kinematic) void {
    var next = pos.last;
    next[0] = pos.pos[0];
    var hcol = level_collide(kinematic.col.addv(next));
    if (hcol.len > 0) {
        kinematic.lastCol[0] = next[0] - pos.last[0];
        next[0] = pos.last[0];
    } else if (!approxEqAbs(f32, next[0] - pos.last[0], 0, 0.01)) {
        kinematic.lastCol[0] = 0;
    }

    next[1] = pos.pos[1];
    var vcol = level_collide(kinematic.col.addv(next));
    if (vcol.len > 0) {
        kinematic.lastCol[1] = next[1] - pos.last[1];
        next[1] = pos.last[1];
    } else if (!approxEqAbs(f32, next[1] - pos.last[1], 0, 0.01)) {
        kinematic.lastCol[1] = 0;
    }

    var colPosAbs = next + kinematic.lastCol;
    var lastCol = level_collide(kinematic.col.addv(colPosAbs));
    if (lastCol.len == 0) {
        kinematic.lastCol = Vec2f{ 0, 0 };
    }

    kinematic.move = next - pos.last;

    pos.pos = next;
}

fn velocityProcess(_: f32, pos: *Pos) void {
    if (pos.pinned) return;
    var vel = pos.pos - pos.last;

    vel *= @splat(2, @as(f32, 0.9));
    vel = @minimum(Vec2f{ 8, 8 }, @maximum(Vec2f{ -8, -8 }, vel));

    pos.last = pos.pos;
    pos.pos += vel;
}

fn physicsProcess(dt: f32, pos: *Pos, physics: *Physics) void {
    if (pos.pinned) return;
    _ = dt;
    var friction = @splat(2, @as(f32, 1)) - physics.friction;
    pos.pos = pos.last + (pos.pos - pos.last) * friction;
    pos.pos += physics.gravity;
}
