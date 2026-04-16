const std = @import("std");
const zphy = @import("zphy");
const shared = @import("shared");
const system = @import("../system.zig");
const component = system.World.component;
const nz = shared.numz;

gpa: std.mem.Allocator,
io: std.Io,
global_state_reload: zphy.GlobalState,
physics_system: *zphy.PhysicsSystem,
broad_phase_layer_interface: *BroadPhaseLayerInterface,
object_layer_pair_filter: *ObjectLayerPairFilter,
object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
contact_listener: *ContactListener,

pub const Collider = struct {
    const Primitive = enum {
        capsule,
        box,
        sphere,
    };
    const Mesh = struct {
        // render_handle: usize,
        indices: std.ArrayList(u32),
        vertices: std.ArrayList([4]f32),
    };
    shape: union(enum) { primitive: Primitive, mesh: Mesh },
    body_id: ?zphy.BodyId = null,
    motion_type: zphy.MotionType,
    // max_angular_velocity: f32 = 1,
};

const object_layers = struct {
    const non_moving: zphy.ObjectLayer = 0;
    const moving: zphy.ObjectLayer = 1;
    const len: u32 = 2;
};

const broad_phase_layers = struct {
    const non_moving: zphy.BroadPhaseLayer = 0;
    const moving: zphy.BroadPhaseLayer = 1;
    const len: u32 = 2;
};

const BroadPhaseLayerInterface = extern struct {
    broad_phase_layer_interface: zphy.BroadPhaseLayerInterface = .init(@This()),
    object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined,

    fn init() BroadPhaseLayerInterface {
        var object_to_broad_phase: [object_layers.len]zphy.BroadPhaseLayer = undefined;
        object_to_broad_phase[object_layers.non_moving] = broad_phase_layers.non_moving;
        object_to_broad_phase[object_layers.moving] = broad_phase_layers.moving;
        return .{ .object_to_broad_phase = object_to_broad_phase };
    }

    fn selfPtr(broad_phase_layer_interface: *zphy.BroadPhaseLayerInterface) *BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    fn selfPtrConst(broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface) *const BroadPhaseLayerInterface {
        return @alignCast(@fieldParentPtr("broad_phase_layer_interface", broad_phase_layer_interface));
    }

    pub fn getNumBroadPhaseLayers(_: *const zphy.BroadPhaseLayerInterface) callconv(.c) u32 {
        return broad_phase_layers.len;
    }

    pub fn getBroadPhaseLayer(
        broad_phase_layer_interface: *const zphy.BroadPhaseLayerInterface,
        layer: zphy.ObjectLayer,
    ) callconv(.c) zphy.BroadPhaseLayer {
        return selfPtrConst(broad_phase_layer_interface).object_to_broad_phase[layer];
    }
};
const ObjectVsBroadPhaseLayerFilter = extern struct {
    object_vs_broad_phase_layer_filter: zphy.ObjectVsBroadPhaseLayerFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectVsBroadPhaseLayerFilter,
        layer1: zphy.ObjectLayer,
        layer2: zphy.BroadPhaseLayer,
    ) callconv(.c) bool {
        return switch (layer1) {
            object_layers.non_moving => layer2 == broad_phase_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};
const ObjectLayerPairFilter = extern struct {
    object_layer_pair_filter: zphy.ObjectLayerPairFilter = .init(@This()),

    pub fn shouldCollide(
        _: *const zphy.ObjectLayerPairFilter,
        object1: zphy.ObjectLayer,
        object2: zphy.ObjectLayer,
    ) callconv(.c) bool {
        return switch (object1) {
            object_layers.non_moving => object2 == object_layers.moving,
            object_layers.moving => true,
            else => unreachable,
        };
    }
};

const ContactListener = extern struct {
    contact_listener: zphy.ContactListener = .init(@This()),

    fn selfPtr(contact_listener: *zphy.ContactListener) *ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    fn selfPtrConst(contact_listener: *const zphy.ContactListener) *const ContactListener {
        return @alignCast(@fieldParentPtr("contact_listener", contact_listener));
    }

    pub fn onContactValidate(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        base_offset: *const [3]zphy.Real,
        collision_result: *const zphy.CollideShapeResult,
    ) callconv(.c) zphy.ValidateResult {
        _ = contact_listener;
        _ = body1;
        _ = body2;
        _ = base_offset;
        _ = collision_result;
        return .accept_all_contacts;
    }

    pub fn onContactAdded(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactPersisted(
        contact_listener: *zphy.ContactListener,
        body1: *const zphy.Body,
        body2: *const zphy.Body,
        _: *const zphy.ContactManifold,
        _: *zphy.ContactSettings,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = body1;
        _ = body2;
    }

    pub fn onContactRemoved(
        contact_listener: *zphy.ContactListener,
        sub_shape_id_pair: *const zphy.SubShapeIdPair,
    ) callconv(.c) void {
        _ = contact_listener;
        _ = sub_shape_id_pair;
    }
};

pub fn init(self: *@This(), gpa: std.mem.Allocator, io: std.Io) !void {
    try zphy.init(gpa, io, .{});
    const broad_phase_layer_interface = try gpa.create(BroadPhaseLayerInterface);
    broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();
    const object_layer_pair_filter = try gpa.create(ObjectLayerPairFilter);
    object_layer_pair_filter.* = .{};
    const object_vs_broad_phase_layer_filter = try gpa.create(ObjectVsBroadPhaseLayerFilter);
    object_vs_broad_phase_layer_filter.* = .{};
    const contact_listener = try gpa.create(ContactListener);
    contact_listener.* = .{};

    // Create physics system
    const physics_system = try zphy.PhysicsSystem.create(
        @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(@alignCast(broad_phase_layer_interface))),
        @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(@alignCast(object_vs_broad_phase_layer_filter))),
        @as(*const zphy.ObjectLayerPairFilter, @ptrCast(@alignCast(object_layer_pair_filter))),
        .{
            .max_bodies = 1024,
            .num_body_mutexes = 0,
            .max_body_pairs = 1024,
            .max_contact_constraints = 1024,
        },
    );

    physics_system.setGravity(.{ 0, 0, 0 });

    physics_system.optimizeBroadPhase();

    const planet: shared.Planet = try .init(gpa, 10);

    const mesh_shape_setting = try zphy.MeshShapeSettings.create(
        planet.vertices.items.ptr,
        @intCast(planet.vertices.items.len),
        @sizeOf([4]f32),
        planet.indices.items,
    );
    zphy.MeshShapeSettings.sanitize(mesh_shape_setting);
    defer mesh_shape_setting.asShapeSettings().release();
    const custom_shape = try mesh_shape_setting.asShapeSettings().createShape();

    const body_interface = physics_system.getBodyInterfaceMut();
    const body_id = try body_interface.createAndAddBody(.{
        .position = .{ 0, 0, 0, 1 },
        .rotation = .{ 0, 0, 0, 1 },
        .shape = custom_shape,
        .motion_type = .static,
        .object_layer = object_layers.moving,
        // .user_data = @intFromEnum(entry),
        .angular_velocity = .{ 0.0, 0.0, 0.0, 0 },
        // .max_angular_velocity = collider.max_angular_velocity,
        //.allow_sleeping = false,
    }, .activate);
    _ = body_id;

    self.* = .{
        .global_state_reload = undefined,
        .gpa = gpa,
        .io = io,
        .contact_listener = contact_listener,
        .physics_system = physics_system,
        .broad_phase_layer_interface = broad_phase_layer_interface,
        .object_layer_pair_filter = object_layer_pair_filter,
        .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
    };
}

pub fn deinit(self: *@This()) void {
    self.gpa.destroy(self.contact_listener);
    self.gpa.destroy(self.broad_phase_layer_interface);
    self.gpa.destroy(self.object_layer_pair_filter);
    self.gpa.destroy(self.object_vs_broad_phase_layer_filter);
    zphy.PhysicsSystem.destroy(self.physics_system);
    zphy.deinit();
}

pub fn reload(self: *@This(), pre_reload: bool, world: *system.World) void {
    if (pre_reload) {
        // Serialize body states before destroying
        // TODO: Implement body serialization when you have active bodies
        std.log.debug("before", .{});

        // Destroy physics system to stop worker threads before unload
        zphy.PhysicsSystem.destroy(self.physics_system);

        std.log.debug("After", .{});
        self.physics_system = undefined;
        self.global_state_reload = zphy.preReload();
    } else {
        zphy.postReload(self.gpa, self.io, self.global_state_reload);
        std.log.debug("XDDD", .{});

        // Refresh vtable pointers FIRST - before creating physics system
        self.broad_phase_layer_interface.broad_phase_layer_interface = zphy.BroadPhaseLayerInterface.init(BroadPhaseLayerInterface);
        self.object_vs_broad_phase_layer_filter.object_vs_broad_phase_layer_filter = zphy.ObjectVsBroadPhaseLayerFilter.init(ObjectVsBroadPhaseLayerFilter);
        self.object_layer_pair_filter.object_layer_pair_filter = zphy.ObjectLayerPairFilter.init(ObjectLayerPairFilter);
        self.contact_listener.contact_listener = zphy.ContactListener.init(ContactListener);

        // Recreate physics system with fresh vtable pointers
        self.physics_system = zphy.PhysicsSystem.create(
            @as(*const zphy.BroadPhaseLayerInterface, @ptrCast(@alignCast(self.broad_phase_layer_interface))),
            @as(*const zphy.ObjectVsBroadPhaseLayerFilter, @ptrCast(@alignCast(self.object_vs_broad_phase_layer_filter))),
            @as(*const zphy.ObjectLayerPairFilter, @ptrCast(@alignCast(self.object_layer_pair_filter))),
            .{
                .max_bodies = 1024,
                .num_body_mutexes = 0,
                .max_body_pairs = 1024,
                .max_contact_constraints = 1024,
            },
        ) catch unreachable;
        self.physics_system.setGravity(.{ 0, 0, 0 });
        var query = world.ecz.query(&.{system.World.component.collider});
        while (query.next()) |entity| {
            const collider = entity.getComponentPtr(system.World.component.collider);
            collider.body_id = null;
        }
        // TODO: Restore body states here when you have active bodies
    }
}

pub fn update(self: *@This(), info: *const system.Info) !void {
    var query = info.world.ecz.query(&.{ system.World.component.collider, system.World.component.transform });
    const body_interface = self.physics_system.getBodyInterfaceMut();
    while (query.next()) |entity| {
        const collider = entity.getComponentPtr(system.World.component.collider);
        const transform = entity.getComponent(system.World.component.transform);
        const matrix = transform.toMat4x4();
        if (collider.body_id == null) {
            const shape = switch (collider.shape) {
                .primitive => |primitive_shape| switch (primitive_shape) {
                    .box => shape: {
                        const box_shape_settings = try zphy.BoxShapeSettings.create(.{ 1, 1, 1 });
                        defer box_shape_settings.asShapeSettings().release();
                        const box_shape = try box_shape_settings.asShapeSettings().createShape();
                        break :shape box_shape;
                    },
                    .sphere => shape: {
                        const sphere_shape_settings = try zphy.SphereShapeSettings.create(1);
                        defer sphere_shape_settings.asShapeSettings().release();
                        const sphere_shape = try sphere_shape_settings.asShapeSettings().createShape();
                        break :shape sphere_shape;
                    },
                    .capsule => shape: {
                        const capsule_shape_settings = try zphy.CapsuleShapeSettings.create(1, 1);
                        defer capsule_shape_settings.asShapeSettings().release();
                        const capsule_shape = try capsule_shape_settings.asShapeSettings().createShape();
                        break :shape capsule_shape;
                    },
                },
                .mesh => |mesh_shape| shape: {
                    const mesh_shape_setting = try zphy.MeshShapeSettings.create(
                        mesh_shape.vertices.items.ptr,
                        @intCast(mesh_shape.vertices.items.len),
                        @sizeOf([4]f32),
                        mesh_shape.indices.items,
                    );
                    zphy.MeshShapeSettings.sanitize(mesh_shape_setting);
                    defer mesh_shape_setting.asShapeSettings().release();
                    const custom_shape = try mesh_shape_setting.asShapeSettings().createShape();
                    break :shape custom_shape;
                },
            };
            defer shape.release();

            std.log.debug("XDD", .{});
            const body_id = try body_interface.createAndAddBody(.{
                .position = matrix.vec4Position(),
                .rotation = transform.rotation.toVec(),
                .shape = shape,
                .motion_type = collider.motion_type,
                .object_layer = object_layers.moving,
                .user_data = entity.id,
                .angular_velocity = .{ 0.0, 0.0, 0.0, 0 },
                // .max_angular_velocity = collider.max_angular_velocity,
                //.allow_sleeping = false,
            }, .activate);
            collider.body_id = body_id;
        }
    }

    try self.playerInput(info);

    const bodies = self.physics_system.getBodiesMutUnsafe();
    // std.debug.print("GRAVITY \n", .{});
    for (bodies) |body| {
        if (!zphy.isValidBodyPointer(body) or body.motion_properties == null) continue;
        const entity = info.world.ecz.entityFromId(@intCast(body.user_data));
        const transform = entity.getComponent(system.World.component.transform);
        const up = nz.vec.normalize(transform.position);
        _ = up;
        // const force = -up;
        // body.addForce(nz.vec.scale(force, 1000));
        // std.debug.print("GRAVITY {any}\n", .{force});

        // const distance = nz.vec.distance(transform.position, .{ 0, 0, 0 });
        // const look_at_pos = nz.vec.scale(nz.vec.forward(nz.Vec3(f32){ 0, 0, 0 }, location_front), distance);
        // transform.rotation = std.math.radiansToDegrees(nz.vec.forward(transform.position, look_at_pos));
    }

    self.physics_system.update(info.delta_time, .{}) catch unreachable;

    for (bodies) |body| {
        // std.debug.print("[0]UPDATE\n", .{}); xd
        if (!zphy.isValidBodyPointer(body) or body.motion_properties == null) continue;
        const entity = info.world.ecz.entityFromId(@intCast(body.user_data));
        const transform = entity.getComponentPtr(system.World.component.transform);
        // std.debug.print("USER_DATA {d}\n", .{body.user_data});

        // std.debug.print("ENTRY_ID {d}\n", .{entry.?.getGeneration(world)});
        const position: nz.Vec3(f32) = .{
            // 0,
            @as(f32, @floatCast(body.position[0])),
            @as(f32, @floatCast(body.position[1])),
            @as(f32, @floatCast(body.position[2])),
        };

        transform.position = position;

        // transform.*.position = .{ 0, 0, 100 };
        // std.log.debug("time: {d}, {d}", .{ info.elapsed_time, @mod(info.elapsed_time, 5) });
        // if (@mod(info.elapsed_time, 5) > 4) transform.*.position = .{ 0, 0, 100 };
    }
}

fn playerInput(self: *@This(), info: *const system.Info) !void {
    const body = self.physics_system.getBodyInterfaceMut();
    var query = info.world.ecz.query(&.{ component.collider, component.input, component.camera, component.transform });
    while (query.next()) |entity| {
        const collider = entity.getComponentPtr(component.collider);
        const camera: *nz.Transform3D(f32) = entity.getComponentPtr(component.camera);
        const transform: *nz.Transform3D(f32) = entity.getComponentPtr(component.transform);
        const input: shared.net.Command.Input = entity.getComponent(component.input);

        const forward = camera.forward();
        const right = camera.right();
        const up = camera.up2();

        //Simple free camera rotation
        if (input.mouse_button_right) {
            const sensitivity: f32 = 0.01;
            const delta_yaw: f32 = @floatCast(-input.mouse_delta[0] * sensitivity * info.delta_time);
            const delta_pitch: f32 = @floatCast(-input.mouse_delta[1] * sensitivity * info.delta_time);

            const world_up = nz.Vec3(f32){ 0, 1, 0 };
            const yaw_quat = nz.quat.Hamiltonian(f32).angleAxis(delta_yaw, world_up);

            camera.rotation = yaw_quat.mul(camera.rotation);
            camera.rotation = camera.rotation.normalize();

            const pitch_quat = nz.quat.Hamiltonian(f32).angleAxis(delta_pitch, nz.Vec3(f32){ 1, 0, 0 });

            camera.rotation = camera.rotation.mul(pitch_quat);
            camera.rotation = camera.rotation.normalize();
            // std.log.debug("rot {any}", .{camera.rotation});
        }

        //Simple body orientation (just copy camera for now)
        transform.rotation = camera.rotation;

        //Collider movement - simple free movement
        if (collider.body_id) |id| {
            var move = nz.Vec3(f32){ 0, 0, 0 };
            const velocity = 1;

            if (input.forward)
                move += nz.vec.scale(forward, velocity);
            if (input.backward)
                move -= nz.vec.scale(forward, velocity);
            if (input.left)
                move -= nz.vec.scale(right, velocity);
            if (input.right)
                move += nz.vec.scale(right, velocity);
            if (input.up)
                move += nz.vec.scale(up, velocity);
            if (input.down)
                move -= nz.vec.scale(up, velocity);

            body.setLinearVelocity(id, nz.vec.scale(move, info.delta_time));

            if (input.r) {
                camera.* = .{};
                body.setLinearVelocity(id, .{ 0, 0, 0 });
                body.setPosition(id, .{ 0, 0, 0 }, .activate);
                body.setRotation(id, .{ 1, 0, 0, 0 }, .activate);
            }
        }
    }
}
