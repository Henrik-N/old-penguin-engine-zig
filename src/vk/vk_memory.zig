const vk = @import("vulkan");
const std = @import("std");
const mem = std.mem;
//
// const vk_context = @import("vk_context.zig");
// const VkContext = vk_context.VkContext;
const VkContext = @import("VkContext.zig");
const DeviceQueue = VkContext.DeviceQueue;
//const DeviceQueue = vk_context.DeviceQueue;

const vk_init = @import("vk_init.zig");
const vk_mem = @This();
const vk_cmd = @import("vk_cmd.zig");

// https://asawicki.info/news_1740_vulkan_memory_types_on_pc_and_how_to_use_them
// https://gpuopen.com/learn/vulkan-device-memory/
// https://zeux.io/2020/02/27/writing-an-efficient-vulkan-renderer/

// https://developer.nvidia.com/vulkan-memory-management

/// Helper enum for abstracting VkMemoryPropertyFlags as intended usage of the memory.
pub const MemoryType = enum {
    /// Fast VRAM not directly visible from cpu. Fast, use as much as possible for bulk data
    gpu_only,

    /// GPU memory visible to the CPU, great for smaller allocations as it's faster. Usually the max size is 256MB.
    // TODO check if the physical device supports this
    gpu_cpu_visible,

    /// CPU-side memory visible to the GPU. Reads happen over PCIE bus. 
    // Altough using gpu_cpu_visble will be faster, this allows the GPU to read bigger chunks than 256MB, and is supported on all hardware.
    cpu_gpu_visible,

    pub fn propertyFlags(self: MemoryType) vk.MemoryPropertyFlags {
        switch (self) {
            .gpu_only => return .{ .device_local_bit = true },
            .gpu_cpu_visible => return .{
                .device_local_bit = true,
                .host_coherent_bit = true,
            }, // host coherent removes the need for flushing
            .cpu_gpu_visible => return .{
                .host_visible_bit = true,
                .host_coherent_bit = true,
            },
        }
    }
};

pub const AllocatedBuffer = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,

    const Self = @This();

    pub fn destroyFree(self: Self, context: VkContext) void {
        destroyBuffer(context, self.buffer);
        freeMemory(context, self.memory);
    }

    /// Creates an allocates a staging buffer
    pub fn initStaging(context: VkContext, size: vk.DeviceSize) !Self {
        const buffer = try vk_mem.createBuffer(context, size, .{ .transfer_src_bit = true });
        const memory = try vk_mem.allocateBufferMemory(context, buffer, .cpu_gpu_visible);

        return Self{
            .buffer = buffer,
            .memory = memory,
        };
    }
};

/// Immediately uploads data to a gpu buffer.
pub fn immediateUpload(context: VkContext, buffer: vk.Buffer, comptime T: type, upload_data: []const T) !void {
    const buffer_size = @sizeOf(T) * upload_data.len;

    const staging: vk_mem.AllocatedBuffer = try vk_mem.allocateStagingBufferMemory(context, buffer_size);
    defer staging.destroyFree(context);

    { // map memory
        const mapped_staging_memory: [*]T = try vk_mem.mapMemoryAligned(context, staging.memory, vk.WHOLE_SIZE, T);
        defer vk_mem.unmapMemory(context, staging.memory);

        for (upload_data) |data, i| {
            mapped_staging_memory[i] = data;
        }
    }

    const cmd = try vk_cmd.CommandBufferRecorder.beginImmediateSubmit(context);

    const copy_regions = [_]vk.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = 0,
        .size = buffer_size,
    }};

    cmd.copyBuffer(buffer, staging.buffer, &copy_regions);

    try cmd.endImmediateSubmit();
}

pub fn allocateStagingBufferMemory(context: VkContext, size: vk.DeviceSize) !AllocatedBuffer {
    const buffer = try vk_mem.createBuffer(context, size, .{ .transfer_src_bit = true });
    const memory = try vk_mem.allocateBufferMemory(context, buffer, .cpu_gpu_visible);

    return AllocatedBuffer{
        .buffer = buffer,
        .memory = memory,
    };
}

pub fn createBuffer(context: VkContext, size: vk.DeviceSize, usage: vk.BufferUsageFlags) !vk.Buffer {
    const graphics_queue_family = context.graphics_queue.family;

    const create_info = vk.BufferCreateInfo{
        .flags = .{},
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
        // .queue_family_index_count = 0,
        // .p_queue_family_indices = undefined,
        .queue_family_index_count = 1,
        .p_queue_family_indices = @ptrCast([*]const u32, &graphics_queue_family),
    };

    return try context.vkd.createBuffer(context.device, &create_info, null);
}

pub fn destroyBuffer(context: VkContext, buffer: vk.Buffer) void {
    context.vkd.destroyBuffer(context.device, buffer, null);
}

pub fn allocateBufferMemory(context: VkContext, buffer: vk.Buffer, memory_type: MemoryType) !vk.DeviceMemory {
    return try allocateBufferMemory2(context, buffer, memory_type.propertyFlags());
}

pub fn allocateBufferMemory2(context: VkContext, buffer: vk.Buffer, memory_property_flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_reqs = context.vkd.getBufferMemoryRequirements(context.device, buffer);
    const mem_type_index = try findMemoryTypeIndex(context, mem_reqs.memory_type_bits, memory_property_flags);

    const mem_alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type_index,
    };

    const memory = try context.vkd.allocateMemory(context.device, &mem_alloc_info, null);
    errdefer freeMemory(context, memory);

    const memory_offset = 0;
    try context.vkd.bindBufferMemory(context.device, buffer, memory, memory_offset);

    return memory;
}

pub fn freeMemory(context: VkContext, memory: vk.DeviceMemory) void {
    context.vkd.freeMemory(context.device, memory, null);
}

pub fn mapMemory(context: VkContext, memory: vk.DeviceMemory, memory_size: vk.DeviceSize) !?*anyopaque {
    const flags = vk.MemoryMapFlags{}; // there are no flags as of the current API
    return try context.vkd.mapMemory(context.device, memory, 0, memory_size, flags);
}

/// Maps the memory and returns a many-item pointer aligned as T.
pub fn mapMemoryAligned(context: VkContext, memory: vk.DeviceMemory, memory_size: vk.DeviceSize, comptime T: type) ![*]T {
    const data: ?*anyopaque = try vk_mem.mapMemory(context, memory, memory_size);
    const data_aligned_ptr: ?*align(@alignOf(T)) anyopaque = @alignCast(@alignOf(T), data);
    return @ptrCast([*]T, data_aligned_ptr);
}

pub fn unmapMemory(context: VkContext, memory: vk.DeviceMemory) void {
    context.vkd.unmapMemory(context.device, memory);
}

pub fn findMemoryTypeIndex(context: VkContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    const mem_props = context.vki.getPhysicalDeviceMemoryProperties(context.physical_device);

    for (mem_props.memory_types[0..mem_props.memory_type_count]) |mem_type, i| {
        if (memory_type_bits & @as(u32, 1) << @truncate(u5, i) != 0 and mem_type.property_flags.contains(flags)) {
            return @truncate(u32, i);
        }
    }

    return error.NoSuitableMemoryTypeAvailable;
}
