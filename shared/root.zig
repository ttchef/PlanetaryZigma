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
    pub const cmd = struct {
        pub const Header = packed struct {
            opcode: Opcode,
        };
        pub const Opcode = enum(u16) {
            connect,
            disconnect,
        };
        pub const Connect = struct {
            name_len: u16,
            name: []const u8,
        };
        pub fn writeBuf(buffer: []u8, header: Header, value: anytype) !usize {
            var fixed_writer: std.Io.Writer = .fixed(buffer);
            const writer = &fixed_writer;
            try writer.writeStruct(header, endian);
            try marshal(writer, value);
            return writer.end;
        }
        pub fn readBuf(T: type, buffer: []u8) !struct { Header, T, usize } {
            var fixed_reader: std.Io.Reader = .fixed(buffer);
            const reader = &fixed_reader;
            const header = try reader.takeStruct(Header, endian);
            const out = try unmarshal(null, reader, T, true);
            return .{ header, out, reader.bufferedLen() };
        }
        fn marshal(writer: *std.Io.Writer, value: anytype) !void {
            const T: type = @TypeOf(value);
            switch (@typeInfo(T)) {
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
                            .auto, .@"extern" => try unmarshal(reader, field.type, endian),
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
