const std = @import("std");
const vk = @import("vulkan.zig");

pub const Growable = struct {
    ratios: std.ArrayList(PoolSizeRatio) = .empty,
    full_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
    ready_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
    sets_per_pool: u32 = 0,

    pub const PoolSizeRatio = struct {
        desciptor_type: vk.c.VkDescriptorType,
        ratio: u32,
    };

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, pool_ratios: []PoolSizeRatio) !@This() {
        var ratios: std.ArrayList(PoolSizeRatio) = .empty;

        for (pool_ratios) |*ratio| {
            try ratios.append(allocator, ratio.*);
        }

        const new_pool = try createPool(allocator, device, max_sets, pool_ratios);

        const sets_per_pool: u32 = @intFromFloat(@as(f32, @floatFromInt(max_sets)) * 1.5);

        var ready_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty;
        try ready_pools.append(allocator, new_pool);
        return .{
            .full_pools = .empty,
            .sets_per_pool = sets_per_pool,
            .ready_pools = ready_pools,
            .ratios = ratios,
        };
    }

    pub fn clearPools(self: *@This(), allocator: std.mem.Allocator, device: vk.Device) !void {
        for (self.ready_pools.items) |ready_pool| {
            try vk.check(vk.c.vkResetDescriptorPool(device.handle, ready_pool, 0));
        }
        for (self.full_pools.items) |full_pool| {
            try vk.check(vk.c.vkResetDescriptorPool(device.handle, full_pool, 0));
            try self.full_pools.append(allocator, full_pool);
        }
        self.full_pools.clearAndFree(allocator);
    }

    pub fn deinit(self: *@This(), allocator: std.mem.Allocator, device: vk.Device) void {
        for (self.ready_pools.items) |ready_pool| {
            vk.c.vkDestroyDescriptorPool(device.handle, ready_pool, 0);
        }
        self.ready_pools.clearAndFree(allocator);
        self.ready_pools.deinit(allocator);
        for (self.full_pools.items) |full_pool| {
            vk.c.vkDestroyDescriptorPool(device.handle, full_pool, 0);
        }
        self.full_pools.clearAndFree(allocator);
        self.full_pools.deinit(allocator);
        self.ratios.deinit(allocator);
    }

    pub fn allocate(self: *@This(), allocator: std.mem.Allocator, device: vk.Device, layout: vk.c.VkDescriptorSetLayout, pNext: ?*void) !vk.c.VkDescriptorSet {
        var pool_to_use = try self.getPool(allocator, device);

        var alloc_info: vk.c.VkDescriptorSetAllocateInfo = .{
            .pNext = pNext,
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = pool_to_use,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout,
        };

        var descriptor_set: vk.c.VkDescriptorSet = undefined;
        const result: vk.c.VkResult = vk.c.vkAllocateDescriptorSets(device.handle, &alloc_info, &descriptor_set);

        if (result == vk.c.VK_ERROR_OUT_OF_POOL_MEMORY or result == vk.c.VK_ERROR_FRAGMENTED_POOL) {
            try self.full_pools.append(allocator, pool_to_use);
            pool_to_use = try self.getPool(allocator, device);
            alloc_info.descriptorPool = pool_to_use;
            try vk.check(vk.c.vkAllocateDescriptorSets(device.handle, &alloc_info, &descriptor_set));
        }
        try self.ready_pools.append(allocator, pool_to_use);
        return descriptor_set;
    }

    fn getPool(self: *@This(), allocator: std.mem.Allocator, device: vk.Device) !vk.c.VkDescriptorPool {
        var new_pool: vk.c.VkDescriptorPool = undefined;
        if (self.ready_pools.items.len != 0) {
            new_pool = self.ready_pools.pop().?;
        } else {
            new_pool = try createPool(allocator, device, self.sets_per_pool, self.ratios.items);

            self.sets_per_pool = @intFromFloat(@as(f32, @floatFromInt(self.sets_per_pool)) * 1.5);

            if (self.sets_per_pool > 4092) {
                self.sets_per_pool = 4092;
            }
        }

        return new_pool;
    }

    fn createPool(allocator: std.mem.Allocator, device: vk.Device, set_count: u32, pool_ratios: []PoolSizeRatio) !vk.c.VkDescriptorPool {
        var pool_sizes: std.ArrayList(vk.c.VkDescriptorPoolSize) = try .initCapacity(allocator, pool_ratios.len);
        defer pool_sizes.deinit(allocator);
        for (pool_ratios) |ratio| {
            const pool_size: vk.c.VkDescriptorPoolSize = .{
                .type = ratio.desciptor_type,
                .descriptorCount = ratio.ratio,
            };
            try pool_sizes.append(allocator, pool_size);
        }

        var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = 0,
            .maxSets = set_count,
            .poolSizeCount = @intCast(pool_sizes.items.len),
            .pPoolSizes = pool_sizes.items.ptr,
        };

        var new_pool: vk.c.VkDescriptorPool = undefined;
        try vk.check(vk.c.vkCreateDescriptorPool(device.handle, &pool_info, null, &new_pool));
        return new_pool;
    }
};

pub const Writer = struct {
    image_infos: [16]vk.c.VkDescriptorImageInfo = undefined,
    image_count: usize = 0,
    buffer_infos: [16]vk.c.VkDescriptorBufferInfo = undefined,
    buffer_count: usize = 0,
    writes: [16]vk.c.VkWriteDescriptorSet = undefined,
    writes_count: usize = 0,

    pub fn appendImage(self: *@This(), binding: u32, image_view: vk.c.VkImageView, sampler: vk.c.VkSampler, layout: vk.c.VkImageLayout, descriptor_set_type: vk.c.VkDescriptorType) void {
        const info: vk.c.VkDescriptorImageInfo = .{
            .sampler = sampler,
            .imageView = image_view,
            .imageLayout = layout,
        };
        self.image_infos[self.image_count] = info;

        const write: vk.c.VkWriteDescriptorSet = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = descriptor_set_type,
            .pImageInfo = &self.image_infos[self.image_count],
        };

        self.image_count += 1;
        self.writes[self.writes_count] = write;
        self.writes_count += 1;
    }

    pub fn appendBuffer(self: *@This(), binding: u32, buffer: vk.c.VkBuffer, size: usize, offset: usize, descriptor_set_type: vk.c.VkDescriptorType) void {
        const info: vk.c.VkDescriptorBufferInfo = .{
            .buffer = buffer,
            .offset = offset,
            .range = size,
        };
        self.buffer_infos[self.buffer_count] = info;
        self.buffer_count += 1;

        const write: vk.c.VkWriteDescriptorSet = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = null,
            .descriptorCount = 1,
            .descriptorType = descriptor_set_type,
            .pBufferInfo = &info,
        };

        self.writes[self.writes_count] = write;
        self.writes_count += 1;
    }

    pub fn clear(self: @This()) void {
        self = std.mem.zeroes(@This());
    }

    pub fn updateSet(self: *@This(), device: vk.Device, set: vk.c.VkDescriptorSet) void {
        for (self.writes[0..self.writes_count]) |*writer| {
            writer.dstSet = set;
            std.debug.print("desctype: {d}\n", .{writer.descriptorType});
        }
        vk.c.vkUpdateDescriptorSets(
            device.handle,
            @intCast(self.writes_count),
            self.writes[0..].ptr,
            0,
            null,
        );
    }
};

pub const Layout = struct {
    handle: vk.c.VkDescriptorSetLayout,

    pub const Config = struct {
        bindings: [16]vk.c.VkDescriptorSetLayoutBinding = undefined,
        binding_count: usize = 0,

        pub fn addBinding(self: *@This(), binding: u32, descriptor_type: vk.c.VkDescriptorType) void {
            const newbind: vk.c.VkDescriptorSetLayoutBinding = .{
                .binding = binding,
                .descriptorCount = 1,
                .descriptorType = descriptor_type,
            };

            self.bindings[self.binding_count] = newbind;
            self.binding_count += 1;
        }

        pub fn clear(self: @This()) void {
            self = std.mem.zeroes(@This());
        }
    };

    pub fn init(device: vk.Device, config: *Config, shader_stages: vk.c.VkShaderStageFlags) !@This() {
        for (config.bindings[0..config.binding_count]) |*binding| {
            binding.stageFlags |= shader_stages;
        }

        var info: vk.c.VkDescriptorSetLayoutCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .pBindings = &config.bindings[0],
            .bindingCount = @intCast(config.binding_count),
        };

        var set: vk.c.VkDescriptorSetLayout = undefined;
        try vk.check(vk.c.vkCreateDescriptorSetLayout(device.handle, &info, null, &set));
        return .{ .handle = set };
    }

    pub fn deinit(self: @This(), device: vk.Device) void {
        vk.c.vkDestroyDescriptorSetLayout(device.handle, self.handle, null);
    }
};
