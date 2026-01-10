const std = @import("std");
const nz = @import("numz");
const glfw = @import("glfw");

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

pub fn proccessCamera(self: *@This(), window: *glfw.Window) void {
    // ---- Mouse movement ----
    // _ = glfw.c.glfwSetCursorPosCallback(window.toC(), cursorPosCallback);
    //
    // self.yaw += delta_x / 200.0;
    // self.pitch -= delta_y / 200.0;

    self.pitch = 0;

    if (glfw.io.Key.left.get(window)) self.yaw -= 0.01;
    if (glfw.io.Key.right.get(window)) self.yaw += 0.01;
    // self.yaw = 0;

    self.pitch = std.math.clamp(self.pitch, -1.55, 1.55);

    // ---- Keyboard movement ----
    const speed: f32 = 0.1;

    if (glfw.io.Key.w.get(window)) self.velocity[2] -= speed;
    if (glfw.io.Key.s.get(window)) self.velocity[2] += speed;
    if (glfw.io.Key.a.get(window)) self.velocity[0] -= speed;
    if (glfw.io.Key.d.get(window)) self.velocity[0] += speed;
    if (glfw.io.Key.q.get(window)) self.position[1] -= 0.5;
    if (glfw.io.Key.e.get(window)) self.position[1] += 0.5;
    const len = @typeInfo(@TypeOf(self.velocity)).vector.len;
    inline for (0..len) |i| {
        if (self.velocity[i] > 0) {
            self.velocity[i] = std.math.clamp(self.velocity[i] - speed / 2, 0, 5);
        } else if (self.velocity[i] < 0) {
            self.velocity[i] = std.math.clamp(self.velocity[i] + speed / 2, -5, 0);
        }
    }

    const camera_rotation = self.getRotationMatrix();
    // const self.otation = nz.Mat4x4(f32).identity;
    const dir4: nz.Vec4(f32) = .{
        self.velocity[0],
        self.velocity[1],
        self.velocity[2],
        0.0,
    };
    const moved4: nz.Vec4(f32) = camera_rotation.mulVec4(dir4);
    self.position += .{ moved4[0], moved4[1], moved4[2] };
}
