const std = @import("std");
const nz = @import("numz");
pub const zphy = @import("zphysics");
const ecs = @import("ecs");
physics_system: *zphy.PhysicsSystem,
broad_phase_layer_interface: *BroadPhaseLayerInterface,
object_layer_pair_filter: *ObjectLayerPairFilter,
object_vs_broad_phase_layer_filter: *ObjectVsBroadPhaseLayerFilter,
contact_listener: *ContactListener,

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
pub fn init(allocator: *std.mem.Allocator, world: *ecs.World) !*@This() {
    // const space = try allocator.alloc(i32, 1024 * 1024 * 1024);
    // _ = space;
    try zphy.init(allocator.*, .{});
    const broad_phase_layer_interface = try allocator.create(BroadPhaseLayerInterface);
    broad_phase_layer_interface.* = BroadPhaseLayerInterface.init();
    const object_layer_pair_filter = try allocator.create(ObjectLayerPairFilter);
    object_layer_pair_filter.* = .{};
    const object_vs_broad_phase_layer_filter = try allocator.create(ObjectVsBroadPhaseLayerFilter);
    object_vs_broad_phase_layer_filter.* = .{};
    const contact_listener = try allocator.create(ContactListener);
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

    const body_interface = physics_system.getBodyInterfaceMut();

    // const floor_shape_settings = try zphy.BoxShapeSettings.create(.{ 100.0, 1.0, 100.0 });
    // defer floor_shape_settings.asShapeSettings().release();
    //
    // const floor_shape = try floor_shape_settings.asShapeSettings().createShape();
    // defer floor_shape.release();
    //
    // _ = try body_interface.createAndAddBody(.{
    //     .position = .{ 0.0, -1.0, 0.0, 1.0 },
    //     .rotation = .{ 0.0, 0.0, 0.0, 1.0 },
    //     .shape = floor_shape,
    //     .motion_type = .static,
    //     .object_layer = object_layers.non_moving,
    // }, .activate);

    const box_shape_settings = try zphy.BoxShapeSettings.create(.{ 1, 1, 1 });
    defer box_shape_settings.asShapeSettings().release();
    const box_shape = try box_shape_settings.asShapeSettings().createShape();
    defer box_shape.release();

    var query = world.query(&.{ ecs.Collider, nz.Transform3D(f32) });
    //TODO: Lucas make custom mesh shape load yes.
    var custom_shape: zphy.Shape = undefined;
    defer custom_shape.release();
    while (query.next()) |entry| {
        const transform = entry.get(nz.Transform3D(f32), world).?;
        const collider = entry.getPtr(ecs.Collider, world).?;
        const matrix = transform.toMat4x4();
        const euler_to_quat = nz.quat.Hamiltonian(f32).fromEuler(transform.rotation);

        const shape = switch (collider.shape) {
            .primitive => |primitive_shape| switch (primitive_shape) {
                .box => box_shape,
                else => box_shape,
            },
            // else => box_shape,
            .mesh => |mesh_shape| {
                const mesh_shape_setting = try zphy.MeshShapeSettings.create(
                    mesh_shape.vertices.items.ptr,
                    @intCast(mesh_shape.vertices.items.len),
                    @sizeOf(nz.Vec3(f32)),
                    mesh_shape.indices.items,
                );
                defer mesh_shape_setting.asShapeSettings().release();
                custom_shape = try mesh_shape_setting.asShapeSettings().createShape();
                => custom_shape,
            },
        };

        const body_id = try body_interface.createAndAddBody(.{
            .position = matrix.vec4Position(),
            .rotation = euler_to_quat.toVecReversed(),
            .shape = shape,
            .motion_type = .dynamic,
            .object_layer = object_layers.moving,
            .user_data = @intFromEnum(entry),
            .angular_velocity = .{ 0.0, 0.0, 0.0, 0 },
            //.allow_sleeping = false,
            .max_angular_velocity = collider.max_angular_velocity,
        }, .activate);
        collider.body_id = body_id;
    }

    physics_system.optimizeBroadPhase();

    const system = try allocator.create(@This());
    system.* = .{
        .contact_listener = contact_listener,
        .physics_system = physics_system,
        .broad_phase_layer_interface = broad_phase_layer_interface,
        .object_layer_pair_filter = object_layer_pair_filter,
        .object_vs_broad_phase_layer_filter = object_vs_broad_phase_layer_filter,
    };
    return system;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    allocator.destroy(self.object_vs_broad_phase_layer_filter);
    allocator.destroy(self.object_layer_pair_filter);
    allocator.destroy(self.broad_phase_layer_interface);
    allocator.destroy(self.contact_listener);
    self.physics_system.destroy();
    zphy.deinit();
}

pub fn update(self: *@This(), world: *ecs.World, delta_time: f32) void {
    self.physics_system.update(delta_time, .{}) catch unreachable;

    const bodies = self.physics_system.getBodiesUnsafe();
    for (bodies) |body| {
        // std.debug.print("[0]UPDATE\n", .{});
        if (!zphy.isValidBodyPointer(body) or body.motion_properties == null) continue;
        const transform = world.entityGetPtr(nz.Transform3D(f32), @enumFromInt(body.user_data)).?;
        // std.debug.print("USER_DATA {d}\n", .{body.user_data});

        // std.debug.print("ENTRY_ID {d}\n", .{entry.?.getGeneration(world)});
        const position: nz.Vec3(f32) = .{
            // 0,
            @as(f32, @floatCast(body.position[0])),
            @as(f32, @floatCast(body.position[1])),
            @as(f32, @floatCast(body.position[2])),
        };
        var rotation: nz.quat.Hamiltonian(f32) = .{
            .x = body.rotation[0],
            .y = body.rotation[1],
            .z = body.rotation[2],
            .w = body.rotation[3],
        };
        transform.*.position = position;
        transform.rotation = rotation.toEuler();
        // std.debug.print("ROTATION {any}\n", .{body.rotation});
    }
}
