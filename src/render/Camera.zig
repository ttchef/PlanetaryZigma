const std = @import("std");
const nz = @import("numz");

velocity: nz.Vec3(f32) = @splat(0),
position: nz.Vec3(f32) = @splat(0),

pitch: f32 = 0,
yaw: f32 = 0,

pub fn getViewMatrix(self: *@This()) nz.Mat4x4(f32) {
    const cameraTranslation: nz.Mat4x4(f32) = .translate(self.position);
    const cameraRotation = getRotationMatrix();
    return (cameraTranslation.mul(cameraRotation)).inverse();
}

pub fn getRotationMatrix(self: *@This()) nz.Mat4x4(f32) {
    const pitchRotation: nz.quat.Hamiltonian(f32) = .fromVec(.{ self.pitch, 1, 0, 0 });
    const yawRotation: nz.quat.Hamiltonian(f32) = .fromVec(.{ self.yaw, 0, -1, 0 });

    return nz.Mat4x4(f32).fromQuaternion(yawRotation).mul(nz.Mat4x4(f32).fromQuaternion(pitchRotation));
}
