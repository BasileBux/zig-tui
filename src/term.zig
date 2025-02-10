const std = @import("std");
const linux = std.os.linux;
const termios = linux.termios;

// Raw mode solution from: https://blog.fabrb.com/2024/capturing-input-in-real-time-zig-0-14/

const INPUT_BUFFER_SIZE = 32;

pub const TermContext = struct {
    stdout: std.fs.File.Writer,
    stdin: std.fs.File.Reader,
    original_state: termios,
    tty_file: std.fs.File,
    input_buffer: [INPUT_BUFFER_SIZE]u8 = undefined,
    input_len: usize = 0,
    win_size: WinSize,

    pub const WinSize = struct {
        rows: u32,
        cols: u32,
    };

    pub fn init() !TermContext {
        const tty_file = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
        const tty_fd = tty_file.handle;

        // Save original terminal settings
        var old_termios: linux.termios = undefined;
        _ = linux.tcgetattr(tty_fd, &old_termios);

        // Configure raw mode
        var new_termios = old_termios;
        new_termios.lflag.ICANON = false; // Disable canonical (line-based) input
        new_termios.lflag.ECHO = false; // Disable automatic echoing of typed chars
        new_termios.iflag.IGNBRK = true; // Ignore BREAK condition on input

        // non-blocking reads
        new_termios.cc[@intFromEnum(linux.V.MIN)] = 0;
        new_termios.cc[@intFromEnum(linux.V.TIME)] = 0;

        _ = linux.tcsetattr(tty_fd, linux.TCSA.NOW, &new_termios);

        const stdout = std.io.getStdOut().writer();

        try stdout.print("\x1B[?1049h", .{}); // Set alternative screen
        // try stdout.print("\x1B[?25l", .{}); // Hide cursor

        try stdout.print("\x1B[?1000h", .{}); // Basic mouse reporting
        try stdout.print("\x1B[?1001h", .{}); // Highlight mouse reporting
        try stdout.print("\x1B[?1002h", .{}); // Button events with motion
        try stdout.print("\x1B[?1003h", .{}); // All motion events
        try stdout.print("\x1B[?1006h", .{}); // SGR extended mode
        try stdout.print("\x1B[?1005h", .{}); // UTF-8 extended mode

        try stdout.print("\x1B[H", .{}); // Put cursor at position 0,0

        var ctx = TermContext{
            .stdout = stdout,
            .stdin = tty_file.reader(),
            .original_state = old_termios,
            .tty_file = tty_file,
            .win_size = WinSize{ .rows = 0, .cols = 0 },
        };
        try ctx.getTermSize();
        return ctx;
    }

    pub fn deinit(self: TermContext) void {
        _ = linux.tcsetattr(self.tty_file.handle, linux.TCSA.NOW, &self.original_state);
        self.tty_file.close();
        self.stdout.print("\x1B[?25h", .{}) catch {};
        self.stdout.print("\x1B[?1049l", .{}) catch {};
        self.stdout.print("\x1b[?9l", .{}) catch {};
        self.stdout.print("\x1B[?1000l", .{}) catch {};
        self.stdout.print("\x1B[?1001l", .{}) catch {};
        self.stdout.print("\x1B[?1002l", .{}) catch {};
        self.stdout.print("\x1B[?1003l", .{}) catch {};
        self.stdout.print("\x1B[?1006l", .{}) catch {};
        self.stdout.print("\x1B[?1005l", .{}) catch {};
    }

    const Winsize = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };

    pub fn getTermSize(self: *TermContext) !void {
        var ws: Winsize = undefined;
        _ = linux.ioctl(self.tty_file.handle, linux.T.IOCGWINSZ, @intFromPtr(&ws));

        self.win_size.rows = ws.ws_row;
        self.win_size.cols = ws.ws_col;
    }

    pub fn getInput(self: *TermContext) !Input {
        if (self.input_len == 0) {
            const n = try self.stdin.read(self.input_buffer[0..]);
            if (n == 0) return Input{ .control = null };
            self.input_len = n;
        }
        const bytes = self.input_buffer[0..self.input_len];

        // Mouse input
        if (bytes.len >= 8 and bytes.len < 20 and bytes[0] == 0x1B and
            bytes[1] == 0x5B and bytes[2] == 0x3C)
        {
            const mouse_data = bytes[3 .. bytes.len - 1];
            var parts = std.mem.split(u8, mouse_data, ";");
            // b, x, y
            var mouse: [3]u32 = undefined;
            var count: usize = 0;
            while (parts.next()) |part| {
                if (count >= 3) return error.WrongMouseData;
                mouse[count] = try std.fmt.parseInt(u32, part, 10);
                count += 1;
            }
            self.consume_bytes(bytes.len);
            return Input{ .mouse = MouseIn{ .b = mouse[0], .x = mouse[1], .y = mouse[2], .suffix = bytes[bytes.len - 1] } };
        }

        // Handle control keys
        if (bytes[0] == 0x1B) {
            switch (bytes.len) {
                1 => {
                    self.consume_bytes(1);
                    return Input{ .control = ControlKeys.Escape };
                },
                3 => {
                    if (bytes[1] != 0x4F and bytes[1] != 0x5B) {
                        self.consume_bytes(3);
                        return Input{ .control = ControlKeys.None };
                    }
                    const in = switch (bytes[2]) {
                        // 0x1B, 0x5B, ...
                        0x41 => Input{ .control = ControlKeys.Up },
                        0x42 => Input{ .control = ControlKeys.Down },
                        0x43 => Input{ .control = ControlKeys.Right },
                        0x44 => Input{ .control = ControlKeys.Left },
                        0x46 => Input{ .control = ControlKeys.End },
                        0x48 => Input{ .control = ControlKeys.Home },

                        // 0x1B, 0x4F, ...
                        0x50 => Input{ .control = ControlKeys.F1 },
                        0x51 => Input{ .control = ControlKeys.F2 },
                        0x52 => Input{ .control = ControlKeys.F3 },
                        0x53 => Input{ .control = ControlKeys.F4 },
                        else => Input{ .control = ControlKeys.None },
                    };
                    self.consume_bytes(3);
                    return in;
                },
                4 => {
                    if (bytes[1] != 0x5B or bytes[3] != 0x7E) {
                        self.consume_bytes(4);
                        return Input{ .control = ControlKeys.None };
                    }
                    const in = switch (bytes[2]) {
                        0x32 => Input{ .control = ControlKeys.Insert },
                        0x33 => Input{ .control = ControlKeys.Delete },
                        0x35 => Input{ .control = ControlKeys.PageUp },
                        0x36 => Input{ .control = ControlKeys.PageDown },
                        else => Input{ .control = ControlKeys.None },
                    };
                    self.consume_bytes(4);
                    return in;
                },
                5 => {
                    if (bytes[1] != 0x5B or bytes[4] != 0x7E) {
                        self.consume_bytes(5);
                        return Input{ .control = ControlKeys.None };
                    }
                    var in: Input = undefined;
                    if (bytes[2] == 0x31) {
                        in = switch (bytes[3]) {
                            0x35 => Input{ .control = ControlKeys.F5 },
                            0x37 => Input{ .control = ControlKeys.F6 },
                            0x38 => Input{ .control = ControlKeys.F7 },
                            0x39 => Input{ .control = ControlKeys.F8 },
                            else => Input{ .control = ControlKeys.None },
                        };
                        self.consume_bytes(5);
                        return in;
                    }
                    if (bytes[2] == 0x32) {
                        in = switch (bytes[3]) {
                            0x30 => Input{ .control = ControlKeys.F9 },
                            0x31 => Input{ .control = ControlKeys.F10 },
                            0x33 => Input{ .control = ControlKeys.F11 },
                            0x34 => Input{ .control = ControlKeys.F12 },
                            else => Input{ .control = ControlKeys.None },
                        };
                        self.consume_bytes(5);
                        return in;
                    }
                },
                else => {
                    self.consume_bytes(bytes.len);
                    return Input{ .control = ControlKeys.None };
                },
            }
        }

        // Handle UTF-8 chars
        var utf8_input: [4]u8 = [_]u8{ 0, 0, 0, 0 };
        var utf8_size: u8 = 0;
        while (self.input_len > 0) {
            const c = bytes[0];
            self.consume_bytes(1);
            utf8_input[utf8_size] = c;
            utf8_size += 1;
        }
        return Input{ .utf8 = utf8_input };
    }

    fn consume_bytes(self: *TermContext, n: usize) void {
        if (n <= self.input_len) {
            std.mem.copyForwards(u8, &self.input_buffer, self.input_buffer[n..self.input_len]);
            self.input_len -= n;
        } else {
            self.input_len = 0;
        }
    }
};

// These are the only control keys hadled by the getInput function
pub const ControlKeys = enum {
    Up,
    Down,
    Left,
    Right,
    Escape,
    F1,
    F2,
    F3,
    F4,
    F5,
    F6,
    F7,
    F8,
    F9,
    F10,
    F11,
    F12,
    Home,
    End,
    Insert,
    Delete,
    PageUp,
    PageDown,
    None,
};

pub const InputType = enum {
    control,
    utf8,
    mouse,
};

pub const Input = union(InputType) {
    control: ?ControlKeys,
    utf8: [4]u8,
    mouse: MouseIn,
};

pub const MouseIn = struct {
    b: u32,
    x: u32,
    y: u32,
    suffix: u8,
};

pub fn utf8_array_equal(a: [4]u8, b: [4]u8) bool {
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

pub fn utf8_code_point_to_array(comptime c: u21) [4]u8 {
    var bytes: [4]u8 = .{0} ** 4;
    if (c <= 0x7F) {
        // 1-byte encoding
        bytes[0] = @as(u8, @intCast(c));
    } else if (c <= 0x7FF) {
        // 2-byte encoding
        bytes[0] = 0xC0 | @as(u8, @intCast(c >> 6));
        bytes[1] = 0x80 | @as(u8, @intCast(c & 0x3F));
    } else if (c <= 0xFFFF) {
        // 3-byte encoding
        bytes[0] = 0xE0 | @as(u8, @intCast(c >> 12));
        bytes[1] = 0x80 | @as(u8, @intCast((c >> 6) & 0x3F));
        bytes[2] = 0x80 | @as(u8, @intCast(c & 0x3F));
    } else {
        // 4-byte encoding
        bytes[0] = 0xF0 | @as(u8, @intCast(c >> 18));
        bytes[1] = 0x80 | @as(u8, @intCast((c >> 12) & 0x3F));
        bytes[2] = 0x80 | @as(u8, @intCast((c >> 6) & 0x3F));
        bytes[3] = 0x80 | @as(u8, @intCast(c & 0x3F));
    }
    return bytes;
}

pub fn utf8_byte_size(byte: [4]u8) u8 {
    if (byte[0] & 0x80 == 0) {
        return 1;
    } else if (byte[0] & 0xE0 == 0xC0) {
        return 2;
    } else if (byte[0] & 0xF0 == 0xE0) {
        return 3;
    } else if (byte[0] & 0xF8 == 0xF0) {
        return 4;
    } else {
        return 0;
    }
}
