const std = @import("std");
const nz = @import("numz");

velocity: nz.Vec3(f32) = @splat(0),
position: nz.Vec3(f32) = @splat(0),

pitch: f32 = 0,
yaw: f32 = 0,

pub fn getViewMatrix(self: *@This()) nz.Mat4x4(f32) {
    var cameraTranslation = nz.Mat4x4(f32).translate(self.position);
    const cameraRotation = getRotationMatrix(self);
    return (cameraTranslation.mul(cameraRotation)).inverse();
}

pub fn getRotationMatrix(self: *@This()) nz.Mat4x4(f32) {
    const pitchRotation: nz.quat.Hamiltonian(f32) = .angleAxis(self.pitch, .{ 1, 0, 0 });
    const yawRotation: nz.quat.Hamiltonian(f32) = .angleAxis(self.yaw, .{ 0, -1, 0 });

    return nz.Mat4x4(f32).fromQuaternion(yawRotation.toVec()).mul(nz.Mat4x4(f32).fromQuaternion(pitchRotation.toVec()));
}
