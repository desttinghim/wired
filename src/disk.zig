const assets = @import("assets");
const std = @import("std");
const util = @import("util.zig");
const w4 = @import("wasm4.zig");
const game = @import("game.zig");
const comp = @import("component.zig");
const Anim = @import("anim.zig");

const Pos = comp.Pos;
const Vec2 = util.Vec2;

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

fn load_diff(mapBuf: []u8, stride: usize, diff: []const u8) void {
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

pub fn reset() void {
    // TODO: implement reset
    // This function should reset the game world without clearing the scores list,
    // so a player can see how well they've done with the game in the past.
}

pub fn load() !bool {
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

    game.score = reader.readByte() catch return false;

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
                game.player.pos = pos;
                // player.pos.pos += Vec2f{ 4, 6 };
            },
            .Coin => {
                try game.coins.append(.{
                    .pos = pos,
                    .sprite = .{ .offset = .{ 0, 0 }, .size = .{ 8, 8 }, .index = 4, .flags = .{ .bpp = .b2 } },
                    .anim = Anim{ .anim = &game.anim_store.coin },
                    .area = .{ .pos = .{ 0, 0 }, .size = .{ 8, 8 } },
                });
            },
            .WireBeginPinned => {
                var begin = game.wires.slice()[id].begin();
                begin.* = pos;
                begin.pinned = true;
                game.wires.slice()[id].straighten();
            },
            .WireBeginLoose => {
                var begin = game.wires.slice()[id].begin();
                begin.* = pos;
                begin.pinned = false;
                game.wires.slice()[id].straighten();
            },
            .WireEndPinned => {
                var end = game.wires.slice()[id].end();
                end.* = pos;
                end.pinned = true;
                game.wires.slice()[id].straighten();
            },
            .WireEndLoose => {
                var end = game.wires.slice()[id].end();
                end.* = pos;
                end.pinned = false;
                game.wires.slice()[id].straighten();
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
    load_diff(&game.conduit_mutable, assets.conduit_size[0], buf[0..bytes_conduit]);

    return true;
}

pub fn save() void {
    var save_buf: [1024]u8 = undefined;
    var save_stream = std.io.fixedBufferStream(&save_buf);
    var save_writer = save_stream.writer();
    save_writer.writeAll("wired") catch return w4.tracef("Couldn't write header");
    save_writer.writeByte(game.score) catch return w4.tracef("Couldn't save score");
    w4.tracef("score %d written", game.score);

    // Write temporary length values
    const lengths_start = save_stream.getPos() catch return w4.tracef("Couldn't get pos");
    save_writer.writeByte(0) catch return w4.tracef("Couldn't write obj length");
    // save_writer.writeByte(0) catch return w4.tracef("Couldn't write map length");
    save_writer.writeByte(0) catch return w4.tracef("Couldn't write conduit length");

    // Write player
    const playerPos = vec2u16(util.vec2fToVec2(game.player.pos.pos));
    save_writer.writeByte(@enumToInt(SaveObj.Player)) catch return w4.tracef("Player");
    save_writer.writeIntBig(u16, playerPos[0]) catch return;
    save_writer.writeIntBig(u16, playerPos[1]) catch return;
    // save_writer.writeAll(&[_]u8{ @enumToInt(SaveObj.Player), @intCast(u8, player
    var obj_len: u8 = 1;

    for (game.coins.slice()) |coin, i| {
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
    for (game.wires.slice()) |*wire, i| {
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
    const conduit_len = write_diff(save_writer, assets.conduit_size[0], &assets.conduit, &game.conduit_mutable) catch return w4.tracef("Couldn't save map diff");

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
