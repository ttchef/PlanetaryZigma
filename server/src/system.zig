const std = @import("std");
const shared = @import("shared");
const NetworkManager = @import("system/NetworkManager.zig");
const nz = shared.numz;
pub const ecz = shared.ecz;
const Physics = @import("system/Physics.zig");

pub const Info = struct {
    delta_time: f32,
    elapsed_time: f32,
    world: *World,
};

pub const World = struct {
    mutex: std.Io.Mutex = .init,

    ecz: ecz.World(&.{
        component.transform,
        component.collider,
        component.input,
        component.camera,
        component.planet,
        component.entity_type,
    }),

    pub const component = struct {
        pub const transform: ecz.Component = .{ .name = .transform, .type = nz.Transform3D(f32) };
        pub const collider: ecz.Component = .{ .name = .collider, .type = Physics.Collider };
        pub const input: ecz.Component = .{ .name = .input, .type = shared.net.Command.Input };
        pub const camera: ecz.Component = .{ .name = .camera, .type = nz.Transform3D(f32) };
        pub const planet: ecz.Component = .{ .name = .planet, .type = u32 };
        pub const entity_type: ecz.Component = .{ .name = .entity_type, .type = shared.EntityType };
    };

    pub fn init(gpa: std.mem.Allocator) !@This() {
        return .{ .ecz = .init(gpa) };
    }
    pub fn deinit(self: *@This()) void {
        self.ecz.deinit();
    }
};

pub const Context = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    world: *World,
    network_manager: NetworkManager,
    physics: Physics,
    request_exit: bool = false,

    pub const Data = struct {
        gpa: std.mem.Allocator,
        world: *World,
        io: std.Io,
    };

    pub fn init(self: *@This(), data: *const Data) !void {
        self.* = .{
            .gpa = data.gpa,
            .io = data.io,
            .world = data.world,
            .network_manager = undefined,
            .physics = undefined,
        };
        try self.network_manager.init(data.gpa, data.io);
        try self.physics.init(data.gpa, data.io);

        //TODO: maybe not do planet init here?
        var planet_entity = try data.world.ecz.spawnEntity();
        const planet_size: u32 = 30;
        try planet_entity.putComponent(World.component.planet, planet_size);
        try planet_entity.putComponent(World.component.transform, .{});
        try planet_entity.putComponent(World.component.entity_type, .planet);
        const planet: shared.Planet = try .init(data.gpa, planet_size);
        std.log.debug("ptr: {*}, len:{d}", .{ planet.vertices.items.ptr, planet.vertices.items.len });

        try planet_entity.putComponent(World.component.collider, .{
            .shape = .{
                .mesh = .{
                    .indices = planet.indices,
                    .vertices = planet.vertices,
                },
            },
            .motion_type = .static,
        });
        std.log.debug("OK ", .{});
        //TODO: planet init
    }
    pub fn deinit(self: *@This()) !void {
        self.physics.deinit();
        try self.network_manager.deinit();
    }

    pub fn update(self: *@This(), info: *const Info) !void {
        try self.network_manager.update(info);
        try self.physics.update(info);
        // self.request_exit = true;
        // if (info.elapsed_time > 1) self.request_exit = true;
    }
    fn reload(self: *@This(), pre_reload: bool) !void {
        std.log.debug("before-1", .{});
        self.physics.reload(pre_reload, self.world);
        try self.network_manager.reload(pre_reload);
        std.log.debug("before-0", .{});
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
        systemContextReload: *const fn (*Context, pre_reload: bool) callconv(.c) void,

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
        context.init(data) catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
    }

    pub export fn systemContextDeinit(context: *Context) void {
        std.log.debug("system context deinit", .{});
        context.deinit() catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            std.log.err("context init: {s}", .{@errorName(err)});
            return;
        };
        context.* = undefined;
    }

    pub export fn systemContextUpdate(context: *Context, info: *const Info) void {
        const result = context.update(info);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
    pub export fn systemContextReload(context: *Context, pre_reload: bool) void {
        const result = context.reload(pre_reload);
        result catch |err| {
            if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            std.log.err("context update: {any}", .{@errorName(err)});
            return;
        };
    }
};
