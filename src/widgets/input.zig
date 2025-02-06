const std = @import("std");
const u = @import("../utils.zig");
const w = @import("widgets.zig");
const term = @import("../term.zig");

const BufferSize = u8;
const BUFFER_SIZE: BufferSize = 255;

pub const InputField = struct {
    stdout: std.fs.File.Writer,
    pos: u.Vec2,
    size: u.Vec2,
    input_buffer: [BUFFER_SIZE]u8,
    input_len: BufferSize,

    buffer_char_size: [BUFFER_SIZE]u8,
    char_size_len: BufferSize,

    cursor_pos: u.Vec2,

    pub fn init(stdout: std.fs.File.Writer, pos: u.Vec2, size: u.Vec2) InputField {
        return .{
            .stdout = stdout,
            .pos = pos,
            .size = size,
            .input_buffer = undefined,
            .input_len = 0,
            .buffer_char_size = undefined,
            .char_size_len = 0,
            .cursor_pos = .{
                .x = pos.x + 3,
                .y = pos.y + 2,
            },
        };
    }

    pub fn update(self: *InputField, input: [4]u8) void {
        if (input[0] == 0x7f or input[0] == 0x08) { // Delete or Backspace
            if (self.input_len > 0) {
                self.input_len -= self.buffer_char_size[self.char_size_len - 1];
                self.char_size_len -= 1;
                if (self.cursor_pos.x > 2) self.cursor_pos.x -= 1;
            }
        } else if (self.input_len < BUFFER_SIZE) {
            const char_size = term.utf8_byte_size(input);
            self.buffer_char_size[self.char_size_len] = char_size;
            self.char_size_len += 1;
            for (0..char_size) |i| {
                self.input_buffer[self.input_len] = input[i];
                self.input_len += 1;
            }
            self.cursor_pos.x += 1;
        }
    }

    pub fn render(self: InputField) !void {
        try w.draw_box(self.stdout, false, .{ .x = self.pos.x, .y = self.pos.y }, .{ .x = self.size.x, .y = self.size.y });
        try w.draw_text(self.stdout, .{ .x = self.pos.x + 2, .y = self.pos.y + 1 }, self.input_buffer[0..self.input_len]);
        try self.stdout.print("\x1b[{d};{d}H", .{ self.cursor_pos.y, self.cursor_pos.x });
    }

    pub fn getValue(self: *InputField) []u8 {
        return self.input_buffer[0..self.input_len];
    }
};
