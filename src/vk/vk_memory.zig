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
        context.destroyBuffer(self.buffer);
        context.freeMemory(self.memory);
    }
};

/// Immediately uploads data to a gpu buffer.
pub fn immediateUpload(context: VkContext, buffer: vk.Buffer, comptime T: type, upload_data: []const T) !void {
    const buffer_size = @sizeOf(T) * upload_data.len;

    const staging_buffer = try context.createStagingBuffer(buffer_size);
    defer context.destroyBuffer(staging_buffer);
    const staging_memory = try context.allocateStagingBufferMemory(staging_buffer);
    defer context.freeMemory(staging_memory);

    { // map memory
        const mapped_staging_memory = try context.mapMemoryAligned(staging_memory, vk.WHOLE_SIZE, T);
        defer context.unmapMemory(staging_memory);

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

    cmd.copyBuffer(buffer, staging_buffer, &copy_regions);

    try cmd.endImmediateSubmit();
}

// pub fn allocateImageMemory(context: VkContext, image: vk.Image, memory_type: MemoryType) !vk.DeviceMemory {
//     return try allocateImageMemory2(context, image, memory_type.propertyFlags());
// }
//
// pub fn allocateImageMemory2(context: VkContext, image: vk.Image, memory_property_flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
//     const mem_reqs = context.vkd.getImageMemoryRequirements(context.device, image);
//     const mem_type_index = try context.findMemoryTypeIndex(mem_reqs.memory_type_bits, memory_property_flags);
//
//     const mem_alloc_info = vk.MemoryAllocateInfo{
//         .allocation_size = mem_reqs.size,
//         .memory_type_index = mem_type_index,
//     };
//
//     const memory = try context.vkd.allocateMemory(context.device, &mem_alloc_info, null);
//     errdefer context.freeMemory(memory);
//
//     const memory_offset = 0;
//     try context.vkd.bindImageMemory(context.device, image, memory, memory_offset);
//
//     return memory;
// }

// pub fn freeMemory(context: VkContext, memory: vk.DeviceMemory) void {
//     context.vkd.freeMemory(context.device, memory, null);
// }
//
// pub fn mapMemory(context: VkContext, memory: vk.DeviceMemory, memory_size: vk.DeviceSize) !?*anyopaque {
//     const flags = vk.MemoryMapFlags{}; // there are no flags as of the current API
//     return try context.vkd.mapMemory(context.device, memory, 0, memory_size, flags);
// }
//
// /// Maps the memory and returns a many-item pointer aligned as T.
// pub fn mapMemoryAligned(context: VkContext, memory: vk.DeviceMemory, memory_size: vk.DeviceSize, comptime T: type) ![*]T {
//     const data: ?*anyopaque = try vk_mem.mapMemory(context, memory, memory_size);
//     const data_aligned_ptr: ?*align(@alignOf(T)) anyopaque = @alignCast(@alignOf(T), data);
//     return @ptrCast([*]T, data_aligned_ptr);
// }
//
// pub fn unmapMemory(context: VkContext, memory: vk.DeviceMemory) void {
//     context.vkd.unmapMemory(context.device, memory);
// }

// pub fn createAllocateUniformBuffers(allocator: mem.Allocator, context: VkContext, comptime T: type, count: usize) ![]vk_mem.AllocatedBuffer {
//     const allocated_buffers = try allocator.alloc(vk_mem.AllocatedBuffer, count);
//     errdefer allocator.free(allocated_buffers);
//
//     var allocated_count: usize = 0;
//     errdefer for (allocated_buffers[0..allocated_count]) |allocated_uniform_buffer| allocated_uniform_buffer.destroyFree(context);
//
//     while (allocated_count < count) {
//         const buffer = try vk_mem.createBuffer(context, @sizeOf(T), .{ .uniform_buffer_bit = true });
//         errdefer vk_mem.destroyBuffer(context, buffer);
//
//         const memory = try vk_mem.allocateBufferMemory(context, buffer, .cpu_gpu_visible);
//         errdefer vk_mem.freeMemory(context, memory);
//
//         allocated_buffers[allocated_count] = vk_mem.AllocatedBuffer { .buffer = buffer, .memory = memory };
//         allocated_count += 1;
//     }
//
//     return allocated_buffers;
// }

pub fn destroyFreeUniformBuffers(allocator: mem.Allocator, context: VkContext, uniform_buffers: []const vk_mem.AllocatedBuffer) void {
    for (uniform_buffers) |ub| ub.destroyFree(context);
    allocator.free(uniform_buffers);
}
