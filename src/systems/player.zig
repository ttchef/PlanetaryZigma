const std = @import("std");

const WorldModule = @import("World");
const World = WorldModule.World;
const Camera = WorldModule.Camera;
const Player = WorldModule.Player;
const Collider = WorldModule.Collider;
const nz = @import("numz");
const sdl = @import("sdl");

pub fn update(world: *World, delta_time: f32) !void {
    var query = world.query(&.{ Player, Camera, nz.Transform3D(f32), Collider });
    while (query.next()) |entity| {
        var transform = entity.getPtr(nz.Transform3D(f32), world).?;
        const camera = entity.getPtr(Camera, world).?;
        const keyboard = sdl.SDL_GetKeyboardState(null);
        const pitch_rad = &transform.rotation[0];
        const yaw_rad = &transform.rotation[1];

        const mouse = sdl.SDL_GetMouseState(null, null);

        var relative_x: f32 = undefined;
        var relative_y: f32 = undefined;
        _ = sdl.SDL_GetRelativeMouseState(&relative_x, &relative_y);

        //SDL_BUTTON_X1 works on Lucas machine for right click
        if (mouse == sdl.SDL_BUTTON_RIGHT or mouse == sdl.SDL_BUTTON_X1) {
            if (!sdl.SDL_HideCursor()) return error.SdlHideCursor;
            yaw_rad.* += relative_x * camera.sensitivity * delta_time;
            pitch_rad.* -= relative_y * camera.sensitivity * delta_time;
            camera.was_rotating = true;
        } else if (camera.was_rotating) {
            _ = sdl.SDL_GetRelativeMouseState(null, null);
            camera.was_rotating = false;
            if (!sdl.SDL_ShowCursor()) return error.SdlShowCursor;
        }

        pitch_rad.* = std.math.clamp(pitch_rad.*, -1.5, 1.5);

        const forward = nz.vec.normalize(nz.Vec3(f32){
            @cos(pitch_rad.*) * @sin(yaw_rad.*),
            @sin(pitch_rad.*),
            -@cos(pitch_rad.*) * @cos(yaw_rad.*),
        });

        const right = nz.vec.normalize(nz.vec.cross(forward, nz.Vec3(f32){ 0, 1, 0 }));

        const up = nz.vec.normalize(nz.vec.cross(right, forward));

        // std.debug.print(
        //     \\--- Mouse / Orientation Debug ---
        //     \\mouse buttons: {x}
        //     \\rel mouse:     ({d:.2}, {d:.2})
        //     \\sensitivity:   {d:.3}
        //     \\yaw:          ({d:.3} rad)
        //     \\pitch:        ({d:.3} rad)
        //     \\forward:       ({d:.3}, {d:.3}, {d:.3})
        //     \\right:         ({d:.3}, {d:.3}, {d:.3})
        //     \\up:            ({d:.3}, {d:.3}, {d:.3})
        //     \\---------------------------------
        //     \\
        // ,
        //     .{
        //         mouse,
        //         relative_x,
        //         relative_y,
        //         camera.sensitivity,
        //         yaw_rad.*,
        //         pitch_rad.*,
        //         forward[0],
        //         forward[1],
        //         forward[2],
        //         right[0],
        //         right[1],
        //         right[2],
        //         up[0],
        //         up[1],
        //         up[2],
        //     },
        // );

        var move = nz.Vec3(f32){ 0, 0, 0 };
        const velocity = camera.speed * delta_time;

        if (keyboard[sdl.SDL_SCANCODE_W])
            move += nz.vec.scale(forward, velocity);
        if (keyboard[sdl.SDL_SCANCODE_S])
            move -= nz.vec.scale(forward, velocity);
        if (keyboard[sdl.SDL_SCANCODE_A])
            move -= nz.vec.scale(right, velocity);
        if (keyboard[sdl.SDL_SCANCODE_D])
            move += nz.vec.scale(right, velocity);
        if (keyboard[sdl.SDL_SCANCODE_Q])
            move -= nz.vec.scale(up, velocity);
        if (keyboard[sdl.SDL_SCANCODE_E])
            move += nz.vec.scale(up, velocity);

        if (keyboard[sdl.SDL_SCANCODE_UP])
            camera.speed += 10;
        if (keyboard[sdl.SDL_SCANCODE_DOWN])
            camera.speed -= 10;

        const speed_multiplier: f32 = if (keyboard[sdl.SDL_SCANCODE_LSHIFT]) 3 else 0;

        camera.speed = std.math.clamp(camera.speed, 0, 1000);

        transform.position += nz.vec.scale(move, speed_multiplier + 1);

        if (keyboard[sdl.SDL_SCANCODE_R]) {
            yaw_rad.* = 0;
            pitch_rad.* = 0;
            transform.position = .{ 0, 0, 0 };
        }

        std.debug.print(
            \\--- Camera Movement Debug---
            \\move:        ({d:.3}, {d:.3}, {d:.3})
            \\forward:     ({d:.3}, {d:.3}, {d:.3})
            \\right:       ({d:.3}, {d:.3}, {d:.3})
            \\up:          ({d:.3}, {d:.3}, {d:.3})
            \\velocity:    {d:.3}
            \\speed:       {d:.3}
            \\mult:        {d:.1}
            \\camera pos:  ({d:.3}, {d:.3}, {d:.3})
            \\yaw:         {d:.3}
            \\pitch:       {d:.3}
            \\roll:       {d:.3}
            \\delta_time:  {d:.10}
            \\-----------------------------
            \\
        ,
            .{
                move[0],               move[1],               move[2],
                forward[0],            forward[1],            forward[2],
                right[0],              right[1],              right[2],
                up[0],                 up[1],                 up[2],
                velocity,              camera.speed,          speed_multiplier + 1,
                transform.position[0], transform.position[1], transform.position[2],
                yaw_rad.*,             pitch_rad.*,           transform.rotation[2],
                delta_time,
            },
        );
    }
}
