const std = @import("std");
const nz = @import("numz");

available_entities: std.Deque(Entity) = .empty,

pub const Rigidbody = struct {
    force: nz.Vec3(f32),
    mass: f32 = 1.0,
};

pub fn EcsCmp(comps: []const type) type {
    const L: type = @Type(.{ .@"struct" = .{
        .fields = blk: {
            var fields: [comps.len]std.builtin.Type.StructField = undefined;
            for (comps, &fields) |comp, *field| field.* = .{
                .name = @typeName(comp),
                .type = comp,
                .alignment = @alignOf(comp),
                .is_comptime = false,
                .default_value_ptr = null,
            };

            break :blk &fields;
        },
        .decls = &[_]std.builtin.Type.Declaration{},
        .is_tuple = false,
        .layout = .auto,
    } });

    return struct {
        pub const Layout = L;
        layout: Layout = undefined,

        pub fn sayAll(self: @This()) void {
            inline for (comps) |comp| {
                std.debug.print("{s}\n", .{@typeName(@TypeOf(@field(self.layout, @typeName(comp))))});
            }

            //TODO: Use this to get all combos of Archetypes!
            //TODO: Also add an additional array for entities ID to know what data is associated with what id.
            // inline for (1..comptime std.math.pow(usize, 2, comps.len)) |mask| {
            //     inline for (comps, 0..) |num, i| {
            //         if ((mask >> @intCast(i)) & 1 == 1) {
            //             std.debug.print("{s}, ", .{@typeName(num)});
            //         }
            //     }
            //     std.debug.print("\n", .{});
            // }
        }
    };
}

const max_entities = 4096;

pub const Entity = enum(u32) {
    _,
};

pub fn init(allocator: std.mem.Allocator) !@This() {
    //TODO alloc the self with alloc. for seafty reasons down the line.
    var self: @This() = .{ .available_entities = try .initCapacity(allocator, max_entities) };
    for (0..max_entities) |i| {
        self.available_entities.pushBackAssumeCapacity(@enumFromInt(i));
    }
    return self;
}

pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
    self.available_entities.deinit(allocator);
}

pub fn update(self: *@This()) void {
    for (0..max_entities) |i| {
        std.debug.print("id {d}\n", .{@intFromEnum(self.available_entities.at(i))});
    }
}

// pub fn createNewEntity(self: @This()) Entity {
//     self.available_entities.popFront();
// }
