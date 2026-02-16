const std = @import("std");
const nz = @import("numz");

pub const Point = extern struct {
    position: [3]f32,
    color: nz.color.Rgba(u8),
};

pub const Line = extern struct {
    from: Point,
    to: Point,
};
