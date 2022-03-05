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
pub fn ImmediateUploadParams(comptime T: type) type {
    return struct {
        buffer: vk.Buffer,
        offset: vk.DeviceSize,
        upload_data: []const T,
    };
}

pub fn immediateUpload(context: VkContext, comptime T: type, params: ImmediateUploadParams(T)) !void {
    const upload_data_size = @sizeOf(T) * params.upload_data.len;

    const staging_buffer = try context.createStagingBuffer(upload_data_size);
    defer context.destroyBuffer(staging_buffer);
    const staging_memory = try context.allocateStagingBufferMemory(staging_buffer);
    defer context.freeMemory(staging_memory);

    { // map memory
        const mapped_staging_memory = try context.mapMemoryAligned(.{
            .memory = staging_memory,
            .offset = 0,
            .size = upload_data_size,
        }, T);

        defer context.unmapMemory(staging_memory);

        for (params.upload_data) |data, i| {
            mapped_staging_memory[i] = data;
        }
    }

    const cmd = try vk_cmd.CommandBufferRecorder.beginImmediateSubmit(context);

    const copy_regions = [_]vk.BufferCopy{.{
        .src_offset = 0,
        .dst_offset = params.offset,
        .size = upload_data_size,
    }};

    cmd.copyBuffer(params.buffer, staging_buffer, &copy_regions);

    try cmd.endImmediateSubmit();
}
