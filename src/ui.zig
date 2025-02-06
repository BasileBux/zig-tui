const std = @import("std");
const term = @import("term.zig");
const widgets = @import("widgets/widgets.zig");
const in_f = @import("widgets/input.zig");

var window_resized = std.atomic.Value(bool).init(false);
fn handleSigwinch(sig: c_int) callconv(.C) void {
    _ = sig;
    window_resized.store(true, .seq_cst);
}

var sigint_received: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
fn handleSigint(_: c_int) callconv(.C) void {
    sigint_received.store(true, .seq_cst);
}

pub const Ui = struct {
    ctx: *term.TermContext,
    exit_sig: bool,
    update: bool,
    input_field: in_f.InputField,

    pub fn init(ctx: *term.TermContext) !Ui {
        // Signal handling
        const sigint_act = std.os.linux.Sigaction{
            .handler = .{ .handler = handleSigint },
            .mask = std.os.linux.empty_sigset,
            .flags = 0,
        };
        _ = std.os.linux.sigaction(std.os.linux.SIG.INT, &sigint_act, null);
        const sigwinch_act = std.os.linux.Sigaction{
            .handler = .{ .handler = handleSigwinch },
            .mask = std.os.linux.empty_sigset,
            .flags = 0,
        };
        _ = std.os.linux.sigaction(std.os.linux.SIG.WINCH, &sigwinch_act, null);

        return Ui{
            .ctx = ctx,
            .exit_sig = false,
            .update = true,
            .input_field = in_f.InputField.init(ctx.stdout, .{ .x = 1, .y = 1 }, .{ .x = ctx.win_size.cols - 2, .y = 3 }),
        };
    }

    pub fn run(self: *Ui) !void {
        while (!self.exit_sig) {
            try self.signal_manager();
            const in: term.Input = self.ctx.getInput() catch break;
            switch (in) {
                term.InputType.control => |control| {
                    const unwrapped_control = control orelse term.ControlKeys.None;
                    switch (unwrapped_control) {
                        term.ControlKeys.Escape => {
                            self.exit_sig = true;
                            break;
                        },
                        else => {
                            // Handle other control keys
                        },
                    }
                },
                term.InputType.utf8 => |value| {
                    self.update = true;
                    self.input_field.update(value);
                },
            }

            if (self.update) {
                try self.ctx.stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen and move cursor to top left
                try self.input_field.render();
                self.update = false;
            }
        }
    }

    fn signal_manager(self: *Ui) !void {
        if (sigint_received.load(.seq_cst)) {
            sigint_received.store(false, .seq_cst);
            self.exit_sig = true;
            return;
        }
        if (window_resized.load(.seq_cst)) {
            window_resized.store(false, .seq_cst);
            try self.ctx.getTermSize();
            try self.ctx.stdout.print("\x1b[2J\x1b[H", .{}); // Clear screen and move cursor to top left
            self.update = true;
        }
    }
};
