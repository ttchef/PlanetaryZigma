const std = @import("std");
const zphy = @import("zphysics");

const ecs = @import("ecs");
const World = ecs.World;
const Camera = ecs.Camera;
const Player = ecs.Player;
const Collider = ecs.Collider;
const nz = @import("numz");
const sdl = @import("sdl");

var k_was_pressed: bool = false;

pub fn update(world: *World, physics: *zphy.PhysicsSystem, delta_time: f32) !void {
    var query = world.query(&.{ Player, Camera, nz.Transform3D(f32), Collider });
    while (query.next()) |entity| {
        var transform = entity.getPtr(nz.Transform3D(f32), world).?;
        const camera = entity.getPtr(Camera, world).?;
        const collider = entity.getPtr(Collider, world).?;
        const keyboard = sdl.SDL_GetKeyboardState(null);
        var current_pitch_rad = camera.transform.rotation[0];
        var current_yaw_rad = camera.transform.rotation[1];

        const mouse = sdl.SDL_GetMouseState(null, null);

        // camera.sensitivity = 1;
        // camera.speed = 500;

        var relative_x: f32 = undefined;
        var relative_y: f32 = undefined;
        _ = sdl.SDL_GetRelativeMouseState(&relative_x, &relative_y);

        //SDL_BUTTON_X1 works on Lucas machine for right click
        if (mouse == sdl.SDL_BUTTON_RIGHT or mouse == sdl.SDL_BUTTON_X1) {
            if (!sdl.SDL_HideCursor()) return error.SdlHideCursor;
            current_yaw_rad += relative_x * camera.sensitivity * delta_time;
            current_pitch_rad -= relative_y * camera.sensitivity * delta_time;
            camera.was_rotating = true;
        } else if (camera.was_rotating) {
            _ = sdl.SDL_GetRelativeMouseState(null, null);
            camera.was_rotating = false;
            if (!sdl.SDL_ShowCursor()) return error.SdlShowCursor;
        }

        // current_pitch_rad = std.math.clamp(current_pitch_rad, -1.5, 1.5);
        var forward = nz.vec.forwardFromEuler(nz.Vec3(f32){ current_pitch_rad, current_yaw_rad, 0 });

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

        if (keyboard[sdl.SDL_SCANCODE_SPACE])
            move += nz.vec.scale(up, velocity);

        if (keyboard[sdl.SDL_SCANCODE_UP])
            camera.speed += 10;
        if (keyboard[sdl.SDL_SCANCODE_DOWN])
            camera.speed -= 10;
        camera.speed = std.math.clamp(camera.speed, 0, 1000);

        const speed_multiplier: f32 = if (keyboard[sdl.SDL_SCANCODE_LSHIFT]) 3 else 1;
        move = nz.vec.scale(move, speed_multiplier);

        const body = physics.getBodyInterfaceMut();

        body.setLinearVelocity(collider.body_id, move);

        if (keyboard[sdl.SDL_SCANCODE_K]) {
            if (k_was_pressed == false) {
                k_was_pressed = true;
                try spawnBox(world, transform.position);
            }
        } else {
            k_was_pressed = false;
        }

        if (keyboard[sdl.SDL_SCANCODE_X]) {
            std.debug.print(
                \\--- camera movement debug-------- 
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
                \\----------------------------
                \\
            ,
                .{
                    move[0],               move[1],               move[2],
                    forward[0],            forward[1],            forward[2],
                    right[0],              right[1],              right[2],
                    up[0],                 up[1],                 up[2],
                    velocity,              camera.speed,          speed_multiplier + 1,
                    transform.position[0], transform.position[1], transform.position[2],
                    transform.rotation[0], transform.rotation[1], transform.rotation[2],
                    delta_time,
                },
            );
        }

        if (keyboard[sdl.SDL_SCANCODE_R]) {
            body.setLinearVelocity(collider.body_id, .{ 0, 0, 0 });
            body.setPosition(collider.body_id, .{ 0, 0, 0 }, .activate);
            body.setRotation(collider.body_id, .{ 1, 0, 0, 0 }, .activate);
        }
        camera.transform = transform.*;
        camera.transform.position[2] += 2;
        camera.transform.rotation = .{ current_pitch_rad, current_yaw_rad, 0 };
    }
}

fn spawnBox(world: *World, player_pos: [3]f32) !void {

    // var planet_mesh2 = try Planet.init(allocator, .{ 0, 0, 0 }, 10);
    // defer planet_mesh2.deinit(allocator);
    // const box2: usize = try renderer.createMesh("planet2", planet_mesh2.indices.items, planet_mesh2.vertices.items);
    const entity_mesh2 = try world.addEntity();
    entity_mesh2.set(nz.Transform3D(f32), .{ .position = player_pos }, world);
    entity_mesh2.set(
        ecs.Collider,
        .{
            .shape = .{
                .primitive = .sphere,
            },
            .motion_type = .dynamic,
        },
        world,
    );
}
