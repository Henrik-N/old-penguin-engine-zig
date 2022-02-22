const vk = @import("vulkan");
const VkContext = @import("vk_context.zig").VkContext;
const std = @import("std");
const mem = std.mem;

// https://asawicki.info/news_1740_vulkan_memory_types_on_pc_and_how_to_use_them
// https://gpuopen.com/learn/vulkan-device-memory/
// https://zeux.io/2020/02/27/writing-an-efficient-vulkan-renderer/

// https://developer.nvidia.com/vulkan-memory-management


/// Helper enum for abstracting VkMemoryPropertyFlags as intended usage of the memory.
pub const MemoryAccess = enum {
    /// Fast VRAM not directly visible from cpu. Fast, use as much as possible for bulk data
    gpu_only,

    /// GPU memory visible to the CPU, great for smaller allocations as it's faster. Usually the max size is 256MB.
    // TODO check if the physical device supports this
    gpu_cpu_visible_dont_use_for_now,

    /// CPU-side memory visible to the GPU. Reads happen over PCIE bus. 
    // Altough using gpu_cpu_visble will be faster, this allows the GPU to read bigger chunks than 256MB, and is supported on all hardware.
    cpu_gpu_visible,

    fn memoryPropertyFlags(self: MemoryAccess) vk.MemoryPropertyFlags {
        switch (self) {
            .gpu_only => return .{ .device_local_bit = true },
            .gpu_cpu_visible_dont_use_for_now => return .{
                .device_local_bit = true,
                .host_coherent_bit = true,
            }, // host coherent removes the need for flushing
            .cpu_gpu_visible => return .{
                .host_visible_bit = true,
                .host_coherent_bit = true,
                .host_cached_bit = true, // informs us that this access to this memory will go through CPU cache == faster // TODO host cached flag may not be available on all platforms
            },
        }
    }
};


pub fn createBuffer(context: VkContext, size: vk.DeviceSize, usage: vk.BufferUsageFlags) !vk.Buffer {
    const create_info = vk.BufferCreateInfo{
        .flags = .{},
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
        .queue_family_index_count = 0,
        .p_queue_family_indices = undefined,
    };

    return try context.vkd.createBuffer(context.device, &create_info, null);
}

pub fn destroyBuffer(context: VkContext, buffer: vk.Buffer) void {
    context.vkd.destroyBuffer(context.device, buffer, null);
}



pub fn allocateBufferMemory(context: VkContext, buffer: vk.Buffer, memory_property_flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_reqs = context.vkd.getBufferMemoryRequirements(context.device, buffer);
    const mem_type_index = findMemoryTypeIndex(context, mem_reqs.memory_type_bits, memory_property_flags);

    const mem_alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type_index,
    };

    const memory = try context.vkd.allocateMemory(context.device, &mem_alloc_info, null);

    const memory_offset = 0;
    _ = try context.vkd.bindBufferMemory(context.device, buffer, memory, memory_offset);

    return memory;
}













fn memoryAllocTest(context: VkContext) !void {
    var buffer_create_info = vk.BufferCreateInfo{
        .flags = .{ },
        .size = 2,
        .usage = .{ .vertex_buffer_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_index_count = 1,
        .p_queue_family_indices = @ptrCast([*]const u32, &context.graphics_queue.family),
    };

    const buffer = try context.vkd.createBuffer(context.device, &buffer_create_info, null);
    defer context.vkd.destroyBuffer(context.device, buffer, null);

    const buffer_mem_reqs = context.vkd.getBufferMemoryRequirements(context.device, buffer);

    std.log.info("----------------", .{});
    std.log.info("buffer mem reqs => size: {}, alignment: {}", .{buffer_mem_reqs.size, buffer_mem_reqs.alignment});
    
    const alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = buffer_mem_reqs.size, // alignment?
        .memory_type_index = try findMemoryTypeIndex(context, buffer_mem_reqs.memory_type_bits, MemoryAccess.cpu_gpu_visible.memoryPropertyFlags()),
    };

    const allocated_mem = try context.vkd.allocateMemory(context.device, &alloc_info, null);
    context.vkd.freeMemory(context.device, allocated_mem, null);
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








// Block of allocated gpu memory
// pub const AllocatedBuffer = struct {
//     buffer: vk.Buffer,
//     memory: vk.DeviceMemory,
//     // allocated_size: vk.DeviceMemory,
//     size: vk.DeviceSize,
// };
// 
// /// View into region of an Allocation
// pub const AllocationView = struct {
//     offset: vk.DeviceSize, // offset into the allocation where this view starts
//     span: vk.DeviceSize, // amount of bytes from the start of the allocation to the end
//     allocation_type: AllocationType,
// };
// 
// 
// /// Representation for a heap on the gpu
// const DeviceHeap = struct {
//     supported_access: vk.MemoryPropertyFlags,
//     allocations: []AllocatedBuffer,
// };


// Allocator for buffers with vk handles and allocated gpu memory
// pub const VkAllocator = struct {
//     device_heaps: [vk.MAX_MEMORY_HEAPS]DeviceHeap,
//     device_heap_count: usize,
// 
//     pub fn init(context: VkContext) !?VkAllocator {
//         const pd_props = context.vki.getPhysicalDeviceProperties(context.physical_device);
//         _ = pd_props;
// 
//         const mem_props = context.vki.getPhysicalDeviceMemoryProperties(context.physical_device);
// 
//         var device_heaps: [vk.MAX_MEMORY_HEAPS]DeviceHeap = undefined;
//         const device_heap_count = mem_props.memory_heap_count;
// 
// 
// 
//         for (mem_props.memory_types[0..mem_props.memory_type_count]) |mem_type, index| {
//             std.log.info("heap: {}, mem_type_index: {}\n------", .{mem_type.heap_index, index});
// 
//             std.log.info("mem type index: {}, memory property: {}", .{index, mem_type});
// 
//             if (mem_type.property_flags.contains(MemoryAccess.gpu_only.memoryPropertyFlags())) {
//                 device_heaps[mem_type.heap_index] = DeviceHeap{
//                     .supported_access = MemoryAccess.gpu_only.memoryPropertyFlags(),
//                 };
//             }
//             if (mem_type.property_flags.contains(MemoryAccess.cpu_gpu_visible.memoryPropertyFlags())) {
//                 device_heaps[mem_type.heap_index] = DeviceHeap{
//                     .supported_access = MemoryAccess.cpu_gpu_visible.memoryPropertyFlags(),
//                 };
//             }
//         }
// 
//         const buf = try context.vkd.createBuffer(context.device, &.{
//             .flags = .{},
//             .size = @sizeOf(u32),
//             .usage = .{ .vertex_buffer_bit = true },
//             .sharing_mode = .exclusive,
//             .queue_family_index_count = 1,
//             .p_queue_family_indices = @ptrCast([*]const u32, &context.graphics_queue.family),
//         }, null);
//         defer context.vkd.destroyBuffer(context.device, buf, null);
// 
//         const buffer_mem_requirements = context.vkd.getBufferMemoryRequirements(context.device, buf);
// 
// 
//         for (device_heaps[0..device_heap_count]) |device_heap, index| {
//             if(device_heap.supported_access.contains(buffer_mem_requirements.memory_type_bits)) {
//                 std.log.info("allocate buffer on heap index: {}", .{index});
//             }
//         }
// 
// 
// 
// 
// 
//         return VkAllocator{
//             .device_heaps = device_heaps,
//             .device_heap_count = device_heap_count,
//         };
//     }
// 
//     // pub allocate(self: *VkAllocator)
// 
// };

// fn findMemoryTypeIndex(context: VkContext, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
//     const mem_props = context.vki.getPhysicalDeviceMemoryProperties(context.physical_device);
//
//     for (mem_props.memory_heaps[0..mem_props.memory_heap_count]) |memory_heap, index| {
//
//     }
//
//     // for (mem_props) |mem_prop, index| {
//     //     if (mem_props.memory_heap.flags == gpu_mem_gpu_only) {
//     //         // has gpu only support
//     //         std.log.info("heap index: {} is for gpu-side only memory", .{index});
//     //     }
//     // }
//
//
//     // TODO find the memory heap for each type, keep track of it's allocated sizes (using allocation callbacks as well?)
//     // check the flags for each type
//     // check for duplicates: if it's the same heap for two different combinations of flags they must share the same memory counter
//
//
//     //for (context.mem_props.memory_types[0..context.mem])
//     return error.Some;
// }

