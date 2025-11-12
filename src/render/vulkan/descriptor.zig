const std = @import("std");
const vk = @import("vulkan.zig");

pub const DescriptorAllocatorGrowable = struct {
    ratios: std.ArrayList(PoolSizeRatio) = .empty,
    full_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
    ready_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty,
    sets_per_pool: u32 = 0,

    pub const PoolSizeRatio = struct {
        desciptor_type: vk.c.VkDescriptorType,
        ratio: f32,
    };

    pub fn init(allocator: std.mem.Allocator, device: vk.Device, max_sets: u32, pool_ratios: []PoolSizeRatio) !@This() {
        const ratios: std.ArrayList(PoolSizeRatio) = .empty;

        for (pool_ratios) |ratio| {
            ratios.append(allocator, ratio);
        }

        const new_pool = createPool(device, max_sets, pool_ratios);

        const sets_per_pool: u32 = max_sets * 1.5;

        const ready_pools: std.ArrayList(vk.c.VkDescriptorPool) = .empty;
        ready_pools.append(allocator, new_pool);
        return .{
            .full_pools = .empty,
            .sets_per_pool = sets_per_pool,
            .ready_pools = ready_pools,
            .ratios = ratios.toOwnedSlice(allocator),
        };
    }

    pub fn clearPools(self: @This(), allocator: std.mem.Allocator, device: vk.Device) void {
        for (self.ready_pools) |ready_pool| {
            try vk.check(vk.c.vkResetDescriptorPool(device, ready_pool, 0));
        }
        for (self.full_pools) |full_pool| {
            try vk.check(vk.c.vkResetDescriptorPool(device, full_pool, 0));
            self.full_pools.append(allocator, full_pool);
        }
        self.full_pools.clearAndFree(allocator);
    }
    pub fn deinit(self: @This(), allocator: std.mem.Allocator, device: vk.Device) void {
        for (self.ready_pools) |ready_pool| {
            try vk.check(vk.c.vkDestroyDescriptorPool(device, ready_pool, 0));
        }
        self.ready_pools.clearAndFree(allocator);
        for (self.full_pools) |full_pool| {
            try vk.check(vk.c.vkDestroyDescriptorPool(device, full_pool, 0));
        }
        self.full_pools.clearAndFree(allocator);
    }

    pub fn allocate(self: @This(), allocator: std.mem.Allocator, device: vk.Device, layout: vk.c.VkDescriptorSetLayout, pNext: *?void) vk.c.VkDescriptorSet {
        const pool_to_use = getPool(device);

        var allocInfo: vk.c.VkDescriptorSetAllocateInfo = .{
            .pNext = pNext,
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .descriptorPool = pool_to_use,
            .descriptorSetCount = 1,
            .pSetLayouts = &layout,
        };

        var descriptor_set: vk.c.VkDescriptorSet = undefined;
        const result: vk.c.VkResult = try vk.check(vk.c.vkAllocateDescriptorSets(device, &allocInfo, &descriptor_set));

        if (result == vk.c.VK_ERROR_OUT_OF_POOL_MEMORY or result == vk.c.VK_ERROR_FRAGMENTED_POOL) {
            self.full_pools.append(allocator, pool_to_use);
            pool_to_use = getPool(device);
            allocInfo.descriptorPool = pool_to_use;
            vk.check(vk.c.vkAllocateDescriptorSets(device, &allocInfo, &descriptor_set));
        }
        self.ready_pools.append(allocator, pool_to_use);
        return descriptor_set;
    }

    fn getPool(self: @This(), device: vk.Device) vk.c.VkDescriptorPool {
        var new_pool: vk.c.VkDescriptorPool = undefined;
        if (self.ready_pools.len != 0) {
            new_pool = self.ready_pools.popBack();
        } else {
            new_pool = createPool(device, self.sets_per_pool, self.ratios);

            self.sets_per_pool = self.sets_per_pool * 1.5;
            if (self.sets_per_pool > 4092) {
                self.sets_per_pool = 4092;
            }
        }

        return new_pool;
    }

    fn createPool(allocator: std.mem.Allocator, device: vk.Device, set_count: u32, pool_ratios: []PoolSizeRatio) vk.c.VkDescriptorPool {
        const pool_sizes: std.ArrayList(vk.c.VkDescriptorPoolSize) = .initCapacity(allocator, pool_ratios.len);
        for (pool_ratios) |ratio| {
            const pool_size: vk.c.VkDescriptorPoolSize = .{
                .type = ratio.desciptor_type,
                .descriptorCount = ratio.ratio,
            };
            pool_sizes.pushBack(pool_size);
        }

        var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = 0,
            .maxSets = set_count,
            .poolSizeCount = pool_sizes.len,
            .pPool_sizes = pool_sizes.buffer,
        };

        var new_pool: vk.c.VkDescriptorPool = undefined;
        try vk.check(vk.c.vkCreateDescriptorPool(device, &pool_info, null, &new_pool));
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

    pub fn appendImage(self: @This(), binding: u32, image: vk.c.VkImageView, sampler: vk.c.VkSampler, layout: vk.c.VkImageLayout, descriptor_set_type: vk.c.VkDescriptorType) void {
        const info: vk.c.VkDescriptorImageInfo = .{
            .sampler = sampler,
            .imageView = image,
            .imageLayout = layout,
        };
        self.image[self.image_count] = info;
        self.image_count += 1;

        const write: vk.c.VkWriteDescriptorSet = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstBinding = binding,
            .dstSet = vk.c.VK_NULL_HANDLE,
            .descriptorCount = 1,
            .descriptorType = descriptor_set_type,
            .pImageInfo = &info,
        };

        self.writes[self.writes_count] = write;
        self.writes_count += 1;
    }

    pub fn appendBuffer(self: @This(), binding: u32, buffer: vk.c.VkBuffer, size: usize, offset: usize, descriptor_set_type: vk.c.VkDescriptorType) void {
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
            .dstSet = vk.c.VK_NULL_HANDLE,
            .descriptorCount = 1,
            .descriptorType = descriptor_set_type,
            .pBufferInfo = &info,
        };

        self.writes_infos[self.writes_count] = write;
        self.writes_count += 1;
    }

    pub fn clear(self: @This()) void {
        self = std.mem.zeroes(@This());
    }

    pub fn updateSet(self: @This(), device: vk.Device, set: vk.c.VkDescriptorSet) void {
        for (self.writes[0..self.writes_count]) |writer| {
            writer.dstSet = set;
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

//TODO DO THIS
const BuilderDescriptorLayout = struct {
    _drawImageDescriptors: vk.c.VkDescriptorSet,
    descriptor_pool: vk.c.VkDescriptorPool,
    _drawImageDescriptorLayou: vk.c.VkDescriptorSetLayout,

    //TODO: DONT TAKE IN  draw_iamge: vk.c.VkImage HERE
    pub fn init(device: vk.Device, draw_iamge: vk.c.VkImageView) !@This() {
        const max_sets: i32 = 10;
        const descriptor_pool_size: []const vk.c.VkDescriptorPoolSize = &.{
            .{ .type = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE, .descriptorCount = 1 * max_sets },
        };

        var pool_info: vk.c.VkDescriptorPoolCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .flags = vk.c.VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT,
            .maxSets = max_sets,
            .poolSizeCount = @intCast(descriptor_pool_size.len),
            .pPoolSizes = @ptrCast(descriptor_pool_size),
        };

        var pool: vk.c.VkDescriptorPool = undefined;
        try vk.check(vk.c.vkCreateDescriptorPool(device.handle, &pool_info, null, &pool));

        const new_bind: []const vk.c.VkDescriptorSetLayoutBinding = &.{.{
            .binding = 0,
            .descriptorCount = 1,
            .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .stageFlags = vk.c.VK_SHADER_STAGE_COMPUTE_BIT,
        }};

        var descriptor_set_layout_info: vk.c.VkDescriptorSetLayoutCreateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
            .bindingCount = @intCast(new_bind.len),
            .pBindings = @ptrCast(new_bind),
        };

        var set: vk.c.VkDescriptorSetLayout = undefined;
        try vk.check((vk.c.vkCreateDescriptorSetLayout(device.handle, &descriptor_set_layout_info, null, &set)));

        var alloc_info: vk.c.VkDescriptorSetAllocateInfo = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
            .pNext = null,
            .descriptorPool = @ptrCast(pool),
            .descriptorSetCount = 1,
            .pSetLayouts = &set,
        };

        var ds: vk.c.VkDescriptorSet = undefined;
        try vk.check(vk.c.vkAllocateDescriptorSets(device.handle, &alloc_info, &ds));

        var img_info: vk.c.VkDescriptorImageInfo = .{
            .imageLayout = vk.c.VK_IMAGE_LAYOUT_GENERAL,
            .imageView = draw_iamge,
        };

        var drawImageWrite: vk.c.VkWriteDescriptorSet = .{
            .sType = vk.c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .pNext = null,
            .dstBinding = 0,
            .dstSet = ds,
            .descriptorCount = 1,
            .descriptorType = vk.c.VK_DESCRIPTOR_TYPE_STORAGE_IMAGE,
            .pImageInfo = &img_info,
        };

        vk.c.vkUpdateDescriptorSets(device.handle, 1, &drawImageWrite, 0, null);

        return .{
            ._drawImageDescriptorLayou = set,
            ._drawImageDescriptors = ds,
            .descriptor_pool = pool,
        };
    }

    pub fn deinit(self: @This(), device: vk.Device) void {
        _ = vk.c.vkFreeDescriptorSets(device.handle, self.descriptor_pool, 1, &self._drawImageDescriptors);
        vk.c.vkDestroyDescriptorPool(device.handle, self.descriptor_pool, null);
        vk.c.vkDestroyDescriptorSetLayout(device.handle, self._drawImageDescriptorLayou, null);
    }
};
