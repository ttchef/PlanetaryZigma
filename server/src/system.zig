const std = @import("std");
const testing = @import("test.zig");
const shared = @import("shared");
const nz = shared.nz;
pub const ec = shared.ec;
// const Physics = @import("Physics.zig");
// physics: *Physics,

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const World = struct {
    mutex: std.Io.Mutex,
    ec: ec.World(&.{
        nz.Transform3D(f32),
    }),

    pub fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .mutex = .init,
            .ec = try .init(allocator, null),
        };
    }
    pub fn deinit(self: *@This()) void {
        self.ec.deinit();
    }
};

pub const Context = struct {
    allocator: std.mem.Allocator,

    pub const Data = struct {
        allocator: std.mem.Allocator,
    };

    pub fn init(data: Data) !@This() {
        return .{
            .allocator = data.allocator,
        };
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        const world = info.world;
        _ = world;
        // std.debug.print("enetiess : {d}\n", .{world.ec.generation.items.len});
        _ = self;
    }
};

comptime {
    _ = ffi;
}

pub const ffi = struct {
    pub const Table = struct {
        systemContextInit: *const fn (*Context, data: *const Context.Data) callconv(.c) void,
        systemContextDeinit: *const fn (*Context) callconv(.c) void,
        systemContextUpdate: *const fn (*Context, data: *const Info) callconv(.c) void,

        pub fn load(dynlib: *std.DynLib) !@This() {
            var self: @This() = undefined;
            inline for (@typeInfo(@This()).@"struct".fields) |field| {
                std.log.debug("Looking up symbol: {s}", .{field.name});
                const ptr = dynlib.lookup(field.type, field.name);
                if (ptr) |p| {
                    @field(self, field.name) = p;
                } else {
                    std.log.err("Failed to lookup symbol: {s}", .{field.name});
                    return error.DynlibLookup;
                }
            }
            return self;
        }
    };

    pub export fn systemContextInit(context: *Context, data: *const Context.Data) void {
        std.log.debug("system context init", .{});
        context.* = Context.init(data.*) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit();
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, info: *const Info) void {
        const result = context.update(info);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpStackTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
