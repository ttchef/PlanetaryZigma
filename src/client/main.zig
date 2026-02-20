const std = @import("std");
const shared = @import("shared");

pub fn main() !void {
    std.debug.print("Client! {s}\n", .{shared.test_string});
}
