const std = @import("std");
const shared = @import("shared");
const nz = shared.numz;
const system = @import("../system.zig");
const Spawner = @import("Spawner.zig");
const Physics = @import("Physics.zig");
const Info = system.Info;
const component = system.World.component;

gpa: std.mem.Allocator,
world: *system.World,

pub fn init(self: *@This(), gpa: std.mem.Allocator, world: *system.World, spawner: *Spawner) !void {
    self.* = .{
        .gpa = gpa,
        .world = world,
    };
    _ = try spawner.spawnPlanet();
    // for (0..20) |_| {
    //     _ = try spawner.spawnEnemy();
    // }
}
pub fn deinit(self: *@This()) !void {
    _ = self;
}

pub fn update(self: *@This(), info: *const Info, spawner: *Spawner, physics: *const Physics) !void {
    _ = self;
    var player: *system.Entity = undefined;
    for (info.world.entities.values()) |*entity| {
        if (entity.kind == .player) {
            player = entity;
            if (player.input.mouse_button_left) {
                _ = try spawner.spawnEnemy();
            }
            break;
        }
    } else return;

    const body_interface = physics.physics_system.getBodyInterfaceMut();

    var planet_size: f32 = 0;
    for (info.world.entities.values()) |*entity| {
        if (entity.flags.planet == true) {
            planet_size = @floatFromInt(entity.planet);
            break;
        }
    }
    for (info.world.entities.values()) |*entity| {
        if (entity.kind != .enemy) continue;
        if (!entity.flags.transform or !entity.flags.collider) continue;
        const body_id = entity.collider.body_id orelse continue;

        var to_player = player.transform.position - entity.transform.position;
        const distance = nz.vec.length(to_player);
        if (distance < 2) continue;
        const power: u32 = 1000;
        // const forward = entity.transform.forward();
        // const forward: nz.quat.Hamiltonian(f32) = .fromEuler(forward_vec);

        // std.log.debug("distance: {d}", .{distance});
        if (distance < planet_size / 2) {
            const dir = nz.quat.Hamiltonian(f32).fromEuler(nz.vec.normalize(to_player));
            body_interface.setRotation(body_id, dir.toVec(), .activate);
            const force = nz.vec.scale(nz.vec.normalize(to_player), power);
            body_interface.addForce(body_id, force);
        } else {
            to_player = -player.transform.position - entity.transform.position;
            const dir = nz.quat.Hamiltonian(f32).fromEuler(nz.vec.normalize(to_player));
            body_interface.setRotation(body_id, dir.toVec(), .activate);
            const force = -nz.vec.scale(nz.vec.normalize(to_player), power);
            body_interface.addForce(body_id, force);
        }

        // if (distance < 100) {
        //     const dir = nz.vec.scale(to_player, 1.0 / distance);
        //     body_interface.addForce(body_id, nz.vec.scale(dir, 1000));
        // }
    }
}
