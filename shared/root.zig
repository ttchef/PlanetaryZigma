const std = @import("std");

pub const nz = @import("numz");
pub const ec = @import("ecs");
pub const Watcher = @import("watcher.zig");
pub const AssetServer = @import("AssetServer.zig");

pub const net = struct {
    pub const server_ip: []const u8 = "127.0.0.1";
    pub const server_port: u16 = 8080;
    pub const data_size: u32 = 1024;
    pub const endian: std.builtin.Endian = .little;
    pub const Command = union(Opcode) {
        connect: Connect,
        disconnect: void,
        acknowledge: void,
        spawn_entity: SpawnEntity,

        pub const Opcode = enum(u16) {
            connect,
            disconnect,
            acknowledge,
            spawn_entity,
        };

        pub const Header = packed struct {
            opcode: Opcode,
        };

        pub const Parsed = struct {
            header: Header,
            command: Command,
        };

        pub const Connect = struct {
            name_len: u16,
            name: []const u8,
        };

        pub const SpawnEntity = struct {
            id: u32,
        };

        pub fn write(self: *const @This(), writer: *std.Io.Writer) !void {
            switch (std.meta.activeTag(self.*)) {
                inline else => |tag| {
                    const tag_name = @tagName(tag);
                    const opcode = std.meta.stringToEnum(Opcode, tag_name).?;
                    const header: Header = .{ .opcode = opcode };
                    try writer.writeStruct(header, endian);
                    try marshal(writer, @field(self.*, tag_name));
                },
            }
        }

        pub fn parse(reader: *std.Io.Reader) !Parsed {
            const header = try reader.takeStruct(Header, endian);
            switch (header.opcode) {
                inline else => |opcode| return .{
                    .header = header,
                    .command = try .parseFromOpcode(reader, opcode),
                },
            }
        }

        fn parseFromOpcode(reader: *std.Io.Reader, comptime opcode: Opcode) !Command {
            const tag_name = @tagName(opcode);
            const T = @FieldType(Command, tag_name);
            const out = try unmarshal(null, reader, T, true);
            return @unionInit(Command, tag_name, out);
        }

        fn marshal(writer: *std.Io.Writer, value: anytype) !void {
            const T: type = @TypeOf(value);
            switch (@typeInfo(T)) {
                .void => return,
                .bool => try writer.writeInt(u8, @intFromBool(value), endian),
                .int => try writer.writeInt(T, value, endian),
                .float => |float| try writer.writeInt(@Int(.signed, float.bits), @bitCast(float), endian),
                .pointer => |pointer| {
                    if (pointer.child == u8)
                        try writer.writeAll(value)
                    else
                        try writer.writeSliceEndian(pointer.child, value, endian);
                },
                .array => |arr| if (arr.child == u8)
                    try writer.writeAll(&value)
                else
                    try writer.writeSliceEndian(arr.child, value, endian),
                .@"struct" => |@"struct"| switch (@"struct".layout) {
                    .auto => inline for (std.meta.fields(T)) |field| {
                        const field_value = @field(value, field.name);
                        try marshal(writer, field_value);
                    },
                    .@"extern" => @compileError("preferred to not serialize structs with extern layout"),
                    .@"packed" => try writer.writeStruct(value, endian),
                },
                .@"enum" => |@"enum"| try writer.writeInt(@"enum".tag_type, @intFromEnum(value), endian),
                .enum_literal => try writer.writeAll(@tagName(value)),
                else => @compileError("can not serialize type of " ++ @typeName(T) ++ " aka " ++ @tagName(@typeInfo(T))),
            }
        }

        fn unmarshal(opt_allocator: ?std.mem.Allocator, reader: *std.Io.Reader, Out: type, deserialize_slices: bool) !Out {
            return switch (@typeInfo(Out)) {
                .void => return,
                .bool => try reader.takeByte() == 1,
                .int => try reader.takeInt(Out, endian),
                .float => std.mem.readInt(Out, try reader.takeArray(@sizeOf(Out)), endian),
                .@"enum" => try reader.takeEnum(Out, endian),
                .@"struct" => {
                    var out: Out = std.mem.zeroes(Out);

                    inline for (@typeInfo(Out).@"struct".fields) |field| @field(out, field.name) = switch (@typeInfo(field.type)) {
                        .bool => try reader.takeByte() == 1,
                        .int => try reader.takeInt(field.type, endian),
                        .float => std.mem.readInt(field.type, try reader.takeArray(@sizeOf(Out)), endian),
                        .pointer => |ptr| if (deserialize_slices) slice: {
                            const element_len_name = field.name ++ "_len";
                            std.debug.assert(@typeInfo(@FieldType(Out, element_len_name)) == .int);
                            const element_len: usize = @field(out, element_len_name);
                            if (ptr.child == u8) {
                                const slice = try reader.take(element_len);
                                reader.toss((4 - (slice.len % 4)) % 4);
                                break :slice if (opt_allocator) |allocator| try allocator.dupe(u8, slice) else slice;
                            } else {
                                if (opt_allocator) |allocator| {
                                    const slice = try allocator.alloc(ptr.child, element_len);

                                    for (0..element_len) |i| {
                                        slice[i] = try unmarshal(allocator, reader, ptr.child, endian, true);
                                    }
                                    break :slice slice;
                                } else {
                                    for (0..element_len) |_| {
                                        _ = try unmarshal(null, reader, ptr.child, endian, true);
                                    }

                                    break :slice &.{};
                                }
                            }
                        } else &.{},
                        .array => |array| if (array.child == u8) (try reader.takeArray(array.len)).* else array: {
                            var val: field.type = std.mem.zeroes(field.type);
                            for (0..array.len) |i| {
                                val[i] = try unmarshal(reader, array.child, endian, deserialize_slices, false);
                            }
                            break :array val;
                        },
                        .@"enum" => e: {
                            break :e reader.takeEnum(field.type, endian) catch |err| {
                                std.log.err("{s} {s} {s}", .{ @errorName(err), @typeName(Out), field.name });
                                return err;
                            };
                        },
                        .@"struct" => |s| switch (s.layout) {
                            .auto, .@"extern" => try unmarshal(opt_allocator, reader, field.type, deserialize_slices),
                            .@"packed" => try reader.takeStruct(field.type, endian),
                        },
                        else => @compileError("can not read type of " ++ @typeName(field.type) ++ " aka " ++ @tagName(@typeInfo(field.type))),
                    };
                    return out;
                },
                else => unreachable,
            };
        }
    };
};
