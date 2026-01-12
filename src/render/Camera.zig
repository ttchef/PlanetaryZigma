const std = @import("std");
const nz = @import("numz");
const sdl = @import("sdl");

velocity: nz.Vec3(f32) = @splat(0),
position: nz.Vec3(f32) = @splat(0),

pitch: f32 = 0,
yaw: f32 = 0,

speed: f32 = 0.5,
sensitivity: f32 = 0.05,
was_rotating: bool = false,

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

pub fn proccessCamera(self: *@This(), delta_time: f32) !void {
    const keyboard = sdl.SDL_GetKeyboardState(null);
    const pitch = &self.pitch;
    const yaw = &self.yaw;

    const mouse = sdl.SDL_GetMouseState(null, null);

    var relative_x: f32 = undefined;
    var relative_y: f32 = undefined;
    _ = sdl.SDL_GetRelativeMouseState(&relative_x, &relative_y);

    if (mouse == sdl.SDL_BUTTON_RIGHT) {
        if (!sdl.SDL_HideCursor()) return error.SdlHideCursor;
        yaw.* += relative_x * self.sensitivity;
        pitch.* += relative_y * self.sensitivity;
        self.was_rotating = true;
    } else if (self.was_rotating) {
        _ = sdl.SDL_GetRelativeMouseState(null, null);
        self.was_rotating = false;
        if (!sdl.SDL_ShowCursor()) return error.SdlShowCursor;
    }

    pitch.* = std.math.clamp(pitch.*, -89.9, 89.9);

    const yaw_rad = std.math.degreesToRadians(yaw.*);
    const pitch_rad = std.math.degreesToRadians(pitch.*);

    const forward = nz.vec.normalize(nz.Vec3(f32){
        @cos(pitch_rad) * @sin(yaw_rad),
        -@sin(pitch_rad),
        -@cos(pitch_rad) * @cos(yaw_rad),
    });

    const right = nz.vec.normalize(nz.vec.cross(forward, nz.Vec3(f32){ 0, 1, 0 }));

    const up = nz.vec.normalize(nz.vec.cross(right, forward));

    var move = nz.Vec3(f32){ 0, 0, 0 };
    const velocity = self.speed * delta_time;

    if (keyboard[sdl.SDL_SCANCODE_W])
        move -= nz.vec.scale(forward, velocity);
    if (keyboard[sdl.SDL_SCANCODE_S])
        move += nz.vec.scale(forward, velocity);
    if (keyboard[sdl.SDL_SCANCODE_A])
        move += nz.vec.scale(right, velocity);
    if (keyboard[sdl.SDL_SCANCODE_D])
        move -= nz.vec.scale(right, velocity);
    if (keyboard[sdl.SDL_SCANCODE_SPACE])
        move -= nz.vec.scale(up, velocity);
    if (keyboard[sdl.SDL_SCANCODE_LCTRL])
        move += nz.vec.scale(up, velocity);

    if (keyboard[sdl.SDL_SCANCODE_UP])
        self.speed += 10;
    if (keyboard[sdl.SDL_SCANCODE_DOWN])
        self.speed -= 10;

    const speed_multiplier: f32 = @floatFromInt(@intFromBool(keyboard[sdl.SDL_SCANCODE_LSHIFT]));

    self.speed = std.math.clamp(self.speed, 0, 1000);

    self.position += nz.vec.scale(move, speed_multiplier + 1);

    if (keyboard[sdl.SDL_SCANCODE_R]) {
        yaw.* = 0;
        pitch.* = 0;
        self.position = .{ 0, 0, 0 };
    }
}

// //TODO: FIX CAMERA LOL XD
// pub fn proccessCamera(self: *@This(), window: *glfw.Window) void {
//     // ---- Mouse movement ----
//     // _ = glfw.c.glfwSetCursorPosCallback(window.toC(), cursorPosCallback);
//     //
//     // self.yaw += delta_x / 200.0;
//     // self.pitch -= delta_y / 200.0;
//
//     self.pitch = 0;
//
//     if (glfw.io.Key.left.get(window)) self.yaw -= 0.01;
//     if (glfw.io.Key.right.get(window)) self.yaw += 0.01;
//     // self.yaw = 0;
//
//     self.pitch = std.math.clamp(self.pitch, -1.55, 1.55);
//
//     // ---- Keyboard movement ----
//     const speed: f32 = 0.1;
//
//     if (glfw.io.Key.w.get(window)) self.velocity[2] -= speed;
//     if (glfw.io.Key.s.get(window)) self.velocity[2] += speed;
//     if (glfw.io.Key.a.get(window)) self.velocity[0] -= speed;
//     if (glfw.io.Key.d.get(window)) self.velocity[0] += speed;
//     if (glfw.io.Key.q.get(window)) self.position[1] -= 0.5;
//     if (glfw.io.Key.e.get(window)) self.position[1] += 0.5;
//     const len = @typeInfo(@TypeOf(self.velocity)).vector.len;
//     inline for (0..len) |i| {
//         if (self.velocity[i] > 0) {
//             self.velocity[i] = std.math.clamp(self.velocity[i] - speed / 2, 0, 5);
//         } else if (self.velocity[i] < 0) {
//             self.velocity[i] = std.math.clamp(self.velocity[i] + speed / 2, -5, 0);
//         }
//     }
//
//     const camera_rotation = self.getRotationMatrix();
//     // const self.otation = nz.Mat4x4(f32).identity;
//     const dir4: nz.Vec4(f32) = .{
//         self.velocity[0],
//         self.velocity[1],
//         self.velocity[2],
//         0.0,
//     };
//     const moved4: nz.Vec4(f32) = camera_rotation.mulVec4(dir4);
//     self.position += .{ moved4[0], moved4[1], moved4[2] };
// }
