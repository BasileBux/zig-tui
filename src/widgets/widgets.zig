const std = @import("std");
const u = @import("../utils.zig");
// This file cannot have any other dependencies. Might create
// circular dependencies. This should only have simple basic
// functions

const VERTICAL_LINE = "\u{2502}";
const HORIZONTAL_LINE = "\u{2500}";

const SQUARE_TOP_LEFT_COR = "\u{250C}";
const SQUARE_TOP_RIGHT_COR = "\u{2510}";
const SQUARE_BOT_LEFT_COR = "\u{2514}";
const SQUARE_BOT_RIGHT_COR = "\u{2518}";

const ROUND_TOP_LEFT_COR = "\u{256D}";
const ROUND_TOP_RIGHT_COR = "\u{256E}";
const ROUND_BOT_LEFT_COR = "\u{2570}";
const ROUND_BOT_RIGHT_COR = "\u{256F}";

pub fn draw_box(stdout: std.fs.File.Writer, rounded: bool, pos: u.Vec2, size: u.Vec2) !void {
    if (size.y < 2 or size.x < 2) {
        return error.sizeTooSmall;
    }
    const offset_x: i32 = if (pos.x > 0) @intCast(pos.x - 1) else -1;
    const offset_y: i32 = if (pos.y > 0) @intCast(pos.y - 1) else -1;
    const width: i32 = if (size.x > 2) @intCast(size.x - 2) else -1;

    try stdout.print("\x1b[H\x1b[{d}B\x1b[{d}C{s}", .{ offset_y, offset_x, if (!rounded) SQUARE_TOP_LEFT_COR else ROUND_TOP_LEFT_COR });

    for (0..size.x - 2) |_| {
        try stdout.print("{s}", .{HORIZONTAL_LINE});
    }
    try stdout.print("{s}", .{if (!rounded) SQUARE_TOP_RIGHT_COR else ROUND_TOP_RIGHT_COR});
    for (0..size.y - 2) |_| {
        try stdout.print("\x1b[G\x1b[B\x1b[{d}C{s}\x1b[{d}C{s}", .{ offset_x, VERTICAL_LINE, width, VERTICAL_LINE });
    }
    try stdout.print("\x1b[G\x1b[B\x1b[{d}C{s}", .{ offset_x, if (!rounded) SQUARE_BOT_LEFT_COR else ROUND_BOT_LEFT_COR });
    for (0..size.x - 2) |_| {
        try stdout.print("{s}", .{HORIZONTAL_LINE});
    }
    try stdout.print("{s}\n", .{if (!rounded) SQUARE_BOT_RIGHT_COR else ROUND_BOT_RIGHT_COR});
}

pub fn draw_text(stdout: std.fs.File.Writer, pos: u.Vec2, text: []const u8) !void {
    const offset_x: i32 = if (pos.x > 0) @intCast(pos.x) else -1;
    const offset_y: i32 = if (pos.y > 0) @intCast(pos.y) else -1;

    try stdout.print("\x1b[H\x1b[{d}B\x1b[{d}C{s}", .{ offset_y, offset_x, text });
}
