const std = @import("std");
const Camera = @import("Renderer").Camera;
const nz = @import("numz");
const sdl = @import("sdl");

is_local: bool = true,

pub fn update(world: *World, delta_time: f32) !void {
    var query = world.query(&.{ @This(), Camera, nz.Transform3D(f32) });
    while (query.next()) |entity| {
        var transform = entity.getPtr(nz.Transform3D(f32), world).?;
        const camera = entity.getPtr(Camera, world).?;
        const keyboard = sdl.SDL_GetKeyboardState(null);
        const pitch = &transform.rotation[0];
        const yaw = &transform.rotation[1];

        const mouse = sdl.SDL_GetMouseState(null, null);

        var relative_x: f32 = undefined;
        var relative_y: f32 = undefined;
        _ = sdl.SDL_GetRelativeMouseState(&relative_x, &relative_y);

        if (mouse == sdl.SDL_BUTTON_RIGHT) {
            if (!sdl.SDL_HideCursor()) return error.SdlHideCursor;
            yaw.* += relative_x * camera.sensitivity;
            pitch.* += relative_y * camera.sensitivity;
            camera.was_rotating = true;
        } else if (camera.was_rotating) {
            _ = sdl.SDL_GetRelativeMouseState(null, null);
            camera.was_rotating = false;
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
        const velocity = camera.speed * delta_time;

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
            camera.speed += 10;
        if (keyboard[sdl.SDL_SCANCODE_DOWN])
            camera.speed -= 10;

        const speed_multiplier: f32 = @floatFromInt(@intFromBool(keyboard[sdl.SDL_SCANCODE_LSHIFT]));

        camera.speed = std.math.clamp(camera.speed, 0, 1000);

        transform.position += nz.vec.scale(move, speed_multiplier + 1);

        if (keyboard[sdl.SDL_SCANCODE_R]) {
            yaw.* = 0;
            pitch.* = 0;
            transform.position = .{ 0, 0, 0 };
        }
    }
}
