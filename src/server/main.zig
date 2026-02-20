const std = @import("std");
const shared = @import("shared");

pub fn main() !void {
    std.debug.print("Server! {s}\n", .{shared.test_string});
}
