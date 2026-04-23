const std = @import("std");
const shared = @import("shared");
const system = @import("../system.zig");
const nz = shared.numz;

pub fn init(self: *@This()) !void {
    self.* = .{};
}

pub fn deinit(self: *@This()) void {
    _ = self;
}

/// Rotate each entity.transform so its local up-axis matches normalize(position).
/// Player bodies already have their yaw set to a tangent-aligned rotation by
/// PlayerController, so this is a no-op for them — it's mainly for passive
/// entities (enemies, props) that physics leaves in arbitrary orientations.
pub fn update(self: *@This(), info: *const system.Info) !void {
    _ = self;

    for (info.world.entities.values()) |*entity| {
        if (!entity.flags.transform) continue;
        const transform = &entity.transform;

        const desired_up: nz.Vec3(f32) = nz.vec.normalize(transform.position);
        const current_up: nz.Vec3(f32) = transform.up2();

        const d = std.math.clamp(nz.vec.dot(current_up, desired_up), -1.0, 1.0);
        if (d >= 0.9999) continue;

        const axis: nz.Vec3(f32) = if (d > -0.9999)
            nz.vec.normalize(nz.vec.cross(current_up, desired_up))
        else
            nz.vec.normalize(nz.vec.cross(current_up, transform.forward()));
        const angle = std.math.acos(d);
        const align_quat: nz.quat.Hamiltonian(f32) = .angleAxis(angle, axis);
        transform.rotation = align_quat.mul(transform.rotation).normalize();
    }
}
