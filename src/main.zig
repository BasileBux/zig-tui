const std = @import("std");
const term = @import("term.zig");
const ui = @import("ui.zig");

pub fn main() !void {
    var ctx = try term.TermContext.init();
    defer ctx.deinit();

    while (true) {
        const in: term.Input = ctx.getInput() catch break;
        switch (in) {
            term.InputType.control => |control| {
                _ = control orelse term.ControlKeys.None;
            },
            term.InputType.utf8 => |value| {
                if (value[0] == 'q') {
                    break;
                }

                if (value[0] == '\n') {
                    try ctx.stdout.print("Enter key pressed\n", .{});
                    continue;
                }
                if (value[0] == ' ') {
                    try ctx.stdout.print("Space key pressed\n", .{});
                    continue;
                }
                if (value[0] == 0x7f or value[0] == 0x08) {
                    try ctx.stdout.print("Backspace key pressed\n", .{});
                    continue;
                }
                try ctx.stdout.print("Entered value: {s}\n", .{value});
            },
            term.InputType.mouse => |mouse| {
                std.debug.print("b: {d}, x: {d}, y: {d}, suffix: {d}\n", .{ mouse.b, mouse.x, mouse.y, mouse.suffix });
            },
        }
    }

    // var tui = try ui.Ui.init(&ctx);
    // try tui.run();
}
