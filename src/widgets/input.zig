const std = @import("std");
const u = @import("../utils.zig");
const w = @import("widgets.zig");
const term = @import("../term.zig");

const BufferSize = usize;
const BUFFER_SIZE = 256;

/// This widget is a text input field. It does not handle overflow. If you give values which
/// make the box outside of the screen, it will break the rendering.
pub const InputField = struct {
    update_flag: bool,
    stdout: std.fs.File.Writer,
    pos: u.Vec2,
    size: u.Vec2,
    input_buffer: [BUFFER_SIZE]u8,
    input_len: u8,

    // Stores size of each char in the buffer
    buffer_char_size: [BUFFER_SIZE]u8,
    char_size_len: BufferSize,
    cursor_pos: u.Vec2,

    pub fn init(stdout: std.fs.File.Writer, pos: u.Vec2, size: u.Vec2) InputField {
        return .{
            .update_flag = true,
            .stdout = stdout,
            .pos = pos,
            .size = size,
            .input_buffer = undefined,
            .input_len = 0,
            .buffer_char_size = undefined,
            .char_size_len = 0,
            .cursor_pos = .{
                .x = 0,
                .y = 0,
            },
        };
    }

    pub fn update(self: *InputField, input: term.Input) void {
        switch (input) {
            .utf8 => |in| {
                if (in[0] == 0x7f or in[0] == 0x08) { // Backspace
                    if (self.input_len > 0 and self.cursor_pos.x > 0) {
                        const delete_pos = blk: {
                            var pos: usize = 0;
                            var x: u32 = 0;
                            while (x < self.cursor_pos.x - 1) : (x += 1) {
                                pos += self.buffer_char_size[x];
                            }
                            break :blk pos;
                        };
                        const char_size = self.buffer_char_size[self.cursor_pos.x - 1];

                        u.shift_left(self.input_buffer[delete_pos..], 0, self.input_len - delete_pos, char_size);
                        u.shift_left(self.buffer_char_size[self.cursor_pos.x - 1 ..], 0, self.char_size_len - self.cursor_pos.x + 1, 1);

                        self.input_len -= char_size;
                        self.char_size_len -= 1;
                        self.cursor_pos.x -= 1;
                        self.update_flag = true;
                    }
                    return;
                }
                if (self.input_len < BUFFER_SIZE) {
                    const insert_pos = blk: {
                        var pos: usize = 0;
                        var x: u32 = 0;
                        while (x < self.cursor_pos.x) : (x += 1) {
                            pos += self.buffer_char_size[x];
                        }
                        break :blk pos;
                    };
                    const char_size = term.utf8_byte_size(in);

                    u.shift_right(self.input_buffer[insert_pos..], 0, self.input_len - insert_pos, char_size);
                    u.shift_right(self.buffer_char_size[self.cursor_pos.x..], 0, self.char_size_len - self.cursor_pos.x, 1);

                    self.buffer_char_size[self.cursor_pos.x] = char_size;
                    for (0..char_size) |i| {
                        self.input_buffer[insert_pos + i] = in[i];
                    }
                    self.input_len += char_size;
                    self.char_size_len += 1;
                    self.cursor_pos.x += 1;
                    self.update_flag = true;
                }
            },
            .mouse => |mouse| {
                const button = mouse.b & 0x3;
                const is_drag = mouse.b & 32;
                const modifiers = mouse.b & 12;

                if (mouse.x >= self.pos.x + 2 and mouse.x <= self.pos.x + self.char_size_len + 3 and
                    mouse.y > self.pos.y + 1 and mouse.y <= self.pos.y + self.size.y - 1)
                {
                    if (button == 0 and is_drag == 0 and modifiers == 0) {
                        self.cursor_pos = .{
                            .x = mouse.x - self.pos.x - 3,
                            .y = mouse.y - self.pos.y - 2,
                        };
                    }
                }
                self.update_flag = true;
            },
            .control => |control| {
                const unwrapped_ctrl = control orelse term.ControlKeys.None;
                switch (unwrapped_ctrl) {
                    .Left => {
                        if (self.cursor_pos.x > 0) {
                            self.cursor_pos.x -= 1;
                        }
                        self.update_flag = true;
                    },
                    .Right => {
                        if (self.cursor_pos.x < self.char_size_len) {
                            self.cursor_pos.x += 1;
                        }
                        self.update_flag = true;
                    },
                    .Delete => {
                        if (self.input_len > 0 and self.cursor_pos.x < self.char_size_len) {
                            const delete_pos = blk: {
                                var pos: usize = 0;
                                var x: u32 = 0;
                                while (x < self.cursor_pos.x) : (x += 1) {
                                    pos += self.buffer_char_size[x];
                                }
                                break :blk pos;
                            };
                            const char_size = self.buffer_char_size[self.cursor_pos.x];

                            u.shift_left(self.input_buffer[delete_pos..], 0, self.input_len - delete_pos, char_size);
                            u.shift_left(self.buffer_char_size[self.cursor_pos.x..], 0, self.char_size_len - self.cursor_pos.x, 1);

                            self.input_len -= char_size;
                            self.char_size_len -= 1;
                            self.update_flag = true;
                        }
                    },
                    else => {},
                }
            },
        }
    }

    pub fn render(self: *InputField) !void {
        if (!self.update_flag) return;
        try w.draw_box(self.stdout, false, .{ .x = self.pos.x, .y = self.pos.y }, .{ .x = self.size.x, .y = self.size.y });
        try w.draw_text(self.stdout, .{ .x = self.pos.x + 2, .y = self.pos.y + 1 }, self.input_buffer[0..self.input_len]);
        try self.stdout.print("\x1b[{d};{d}H", .{ self.cursor_pos.y + self.pos.y + 2, self.cursor_pos.x + self.pos.x + 3 });
        self.update_flag = false;
    }

    pub fn getValue(self: *InputField) []u8 {
        return self.input_buffer[0..self.input_len];
    }
};
