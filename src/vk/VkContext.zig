const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const is_debug_mode: bool = builtin.mode == std.builtin.Mode.Debug;

const vk_dispatch = @import("vk_dispatch.zig");
const BaseDispatch = vk_dispatch.BaseDispatch;
const InstanceDispatch = vk_dispatch.InstanceDispatch;
const DeviceDispatch = vk_dispatch.DeviceDispatch;

const UploadContext = @import("UploadContext.zig");
const Swapchain = @import("Swapchain.zig");

const vk_init = @import("vk_init.zig");
const vk_mem = @import("vk_memory.zig");
const vk_cmd = @import("vk_cmd.zig");

const zk = @import("zulkan.zig");

const context_init = @import("vk_context_init.zig");

const VkDevice = @import("VkDevice.zig");

const VkContext = @This();
const Self = VkContext;

allocator: Allocator,
//
vki: InstanceDispatch,
vkd: DeviceDispatch,
//
instance: vk.Instance,
debug_messenger: ?vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
device: vk.Device,
//
graphics_queue: DeviceQueue,
present_queue: DeviceQueue,
upload_context: UploadContext,
//

pub const DeviceQueue = struct {
    handle: vk.Queue,
    family: u32,
};

pub const init = context_init.initVkContext;

pub fn deinit(self: VkContext) void {
    self.upload_context.deinit(self);

    self.vkd.destroyDevice(self.device, null);
    self.vki.destroySurfaceKHR(self.instance, self.surface, null);
    if (self.debug_messenger) |debug_messenger| self.vki.destroyDebugUtilsMessengerEXT(self.instance, debug_messenger, null);
    self.vki.destroyInstance(self.instance, null);
}

pub fn immediateSubmitBegin(self: VkContext) !vk.CommandBuffer {
    return try self.upload_context.immediateSubmitBegin(self);
}

pub fn immediateSubmitEnd(self: VkContext) !void {
    try self.upload_context.immediateSubmitEnd(self);
}

pub fn createShaderModule(self: Self, comptime shader_source: []const u8) !vk.ShaderModule {
    return self.vkd.createShaderModule(self.device, &.{
        .flags = .{},
        .code_size = @intCast(u32, shader_source.len),
        .p_code = @ptrCast([*]const u32, shader_source.ptr),
    }, null);
}

pub fn destroyShaderModule(self: Self, shader_module: vk.ShaderModule) void {
    self.vkd.destroyShaderModule(self.device, shader_module, null);
}

// Render pass -----
pub fn createRenderPass(self: Self, create_info: zk.RenderPassCreateInfo) !vk.RenderPass {
    return self.vkd.createRenderPass(self.device, &create_info.raw(), null);
}

pub fn destroyRenderPass(self: Self, render_pass: vk.RenderPass) void {
    self.vkd.destroyRenderPass(self.device, render_pass, null);
}

// Descriptors -----
pub fn createDescriptorPool(self: Self, create_info: zk.DescriptorPoolCreateInfo) !vk.DescriptorPool {
    return self.vkd.createDescriptorPool(self.device, &create_info.raw(), null);
}

pub fn destroyDescriptorPool(self: Self, descriptor_pool: vk.DescriptorPool) void {
    self.vkd.destroyDescriptorPool(self.device, descriptor_pool, null);
}

pub fn createDescriptorSetLayout(self: Self, create_info: zk.DescriptorSetLayoutCreateInfo) !vk.DescriptorSetLayout {
    return self.vkd.createDescriptorSetLayout(self.device, &create_info.raw(), null);
}

pub fn destroyDescriptorSetLayout(self: Self, descriptor_set_layout: vk.DescriptorSetLayout) void {
    self.vkd.destroyDescriptorSetLayout(self.device, descriptor_set_layout, null);
}

pub fn allocateDescriptorSet(self: Self, descriptor_pool: vk.DescriptorPool, layout: vk.DescriptorSetLayout) !vk.DescriptorSet {
    const alloc_info: vk.DescriptorSetAllocateInfo = (zk.DescriptorSetAllocateInfo{
        .descriptor_pool = descriptor_pool,
        .set_layouts = &.{layout},
    }).raw();

    var descriptor_set: vk.DescriptorSet = undefined;
    try self.vkd.allocateDescriptorSets(self.device, &alloc_info, @ptrCast([*]vk.DescriptorSet, &descriptor_set));

    return descriptor_set;
}

pub fn freeDescriptorSet(self: Self, descriptor_pool: vk.DescriptorPool, descriptor_set: vk.DescriptorSet) void {
    self.vkd.freeDescriptorSets(self.device, descriptor_pool, 1, @ptrCast([*]const vk.DescriptorSet, descriptor_set));
}

pub fn freeDescriptorSets(self: Self, descriptor_pool: vk.DescriptorPool, descriptor_sets: []const vk.DescriptorSet) void {
    self.vkd.freeDescriptorSets(self.device, descriptor_pool, @intCast(u32, descriptor_sets.len), @ptrCast([*]const vk.DescriptorSet, descriptor_sets.ptr));
}

// Pipeline -----
pub fn createPipelineLayout(self: Self, create_info: zk.PipelineLayoutCreateInfo) !vk.PipelineLayout {
    return self.vkd.createPipelineLayout(self.device, &create_info.raw(), null);
}

pub fn destroyPipelineLayout(self: Self, pipeline_layout: vk.PipelineLayout) void {
    self.vkd.destroyPipelineLayout(self.device, pipeline_layout, null);
}

pub fn createPipelineLayouts(self: Self, create_info: zk.PipelineLayoutCreateInfo, handles: []vk.PipelineLayout) !void {
    for (handles) |*handle| handle.* = try self.createPipelineLayout(create_info);
}

pub fn destroyPipelineLayouts(self: Self, pipeline_layouts: []vk.PipelineLayout) void {
    for (pipeline_layouts) |layout| self.destroyPipelineLayout(layout);
}

pub fn allocatePipelineLayoutHandles(self: Self, count: usize) ![]vk.PipelineLayout {
    return self.allocator.alloc(vk.PipelineLayout, count);
}

pub fn freePipelineLayoutHandles(self: Self, handles: []vk.PipelineLayout) void {
    self.allocator.free(handles);
}

pub fn createGraphicsPipeline(self: Self, create_info: vk.GraphicsPipelineCreateInfo, pipeline_cache: vk.PipelineCache) !vk.Pipeline {
    var pipeline: vk.Pipeline = undefined;
    _ = try self.vkd.createGraphicsPipelines(self.device, pipeline_cache, 1, @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &create_info), null, @ptrCast([*]vk.Pipeline, &pipeline));
    return pipeline;
}

pub fn destroyPipeline(self: Self, pipeline: vk.Pipeline) void {
    self.vkd.destroyPipeline(self.device, pipeline, null);
}

// Memory
pub fn createBuffer(self: Self, create_info: zk.BufferCreateInfo) !vk.Buffer {
    return self.vkd.createBuffer(self.device, &create_info.raw(), null);
}

pub fn createBufferGraphicsQueue(self: Self, size: vk.DeviceSize, usage: vk.BufferUsageFlags) !vk.Buffer {
    return self.createBuffer(.{
        .flags = .{},
        .size = size,
        .usage = usage,
        .sharing_mode = .exclusive,
        .queue_family_indices = &.{self.graphics_queue.family},
    });
}

pub fn destroyBuffer(self: Self, buffer: vk.Buffer) void {
    self.vkd.destroyBuffer(self.device, buffer, null);
}

pub fn allocateBufferMemory(self: Self, buffer: vk.Buffer, memory_type: vk_mem.MemoryType) !vk.DeviceMemory {
    return self.allocateBufferMemory2(buffer, memory_type.propertyFlags());
}

pub fn createImage(self: Self, create_info: vk.ImageCreateInfo) !vk.Image {
    return self.vkd.createImage(self.device, &create_info, null);
}

pub fn destroyImage(self: Self, image: vk.Image) void {
    self.vkd.destroyImage(self.device, image, null);
}

pub fn allocateImageMemory(self: Self, image: vk.Image, memory_type: vk_mem.MemoryType) !vk.DeviceMemory {
    return try self.allocateImageMemory2(image, memory_type.propertyFlags());
}

pub fn allocateImageMemory2(self: Self, image: vk.Image, memory_property_flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_reqs = self.vkd.getImageMemoryRequirements(self.device, image);
    const mem_type_index = try self.findMemoryTypeIndex(mem_reqs.memory_type_bits, memory_property_flags);

    const mem_alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type_index,
    };

    const memory = try self.vkd.allocateMemory(self.device, &mem_alloc_info, null);
    errdefer self.freeMemory(memory);

    const memory_offset = 0;
    try self.vkd.bindImageMemory(self.device, image, memory, memory_offset);

    return memory;
}

pub fn createImageView(self: Self, create_info: vk.ImageViewCreateInfo) !vk.ImageView {
    return self.vkd.createImageView(self.device, &create_info, null);
}

pub fn destroyImageView(self: Self, image_view: vk.ImageView) void {
    self.vkd.destroyImageView(self.device, image_view, null);
}

// TODO private
pub fn findMemoryTypeIndex(self: Self, memory_type_bits: u32, flags: vk.MemoryPropertyFlags) !u32 {
    const mem_props = self.vki.getPhysicalDeviceMemoryProperties(self.physical_device);

    for (mem_props.memory_types[0..mem_props.memory_type_count]) |mem_type, i| {
        if (memory_type_bits & @as(u32, 1) << @truncate(u5, i) != 0 and mem_type.property_flags.contains(flags)) {
            return @truncate(u32, i);
        }
    }

    return error.NoSuitableMemoryTypeAvailable;
}

pub fn allocateBufferMemory2(self: Self, buffer: vk.Buffer, memory_property_flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
    const mem_reqs = self.vkd.getBufferMemoryRequirements(self.device, buffer);
    const mem_type_index = try self.findMemoryTypeIndex(mem_reqs.memory_type_bits, memory_property_flags);

    const mem_alloc_info = vk.MemoryAllocateInfo{
        .allocation_size = mem_reqs.size,
        .memory_type_index = mem_type_index,
    };

    const memory = try self.vkd.allocateMemory(self.device, &mem_alloc_info, null);
    errdefer self.freeMemory(memory);

    const memory_offset = 0;
    try self.vkd.bindBufferMemory(self.device, buffer, memory, memory_offset);

    return memory;
}

pub fn createStagingBuffer(self: Self, size: vk.DeviceSize) !vk.Buffer {
    return self.createBuffer(.{
        .flags = .{},
        .size = size,
        .usage = .{ .transfer_src_bit = true },
        .sharing_mode = .exclusive,
        .queue_family_indices = &.{self.graphics_queue.family}, // TODO transfer queue on seperate thread
    });
}

pub fn allocateStagingBufferMemory(self: Self, staging_buffer: vk.Buffer) !vk.DeviceMemory {
    return self.allocateBufferMemory(staging_buffer, .cpu_gpu_visible);
}

pub fn mapMemory(self: Self, memory: vk.DeviceMemory, memory_size: vk.DeviceSize) !?*anyopaque {
    const flags = vk.MemoryMapFlags{}; // there are no flags as of the current API
    const offset: vk.DeviceSize = 0;
    return try self.vkd.mapMemory(self.device, memory, offset, memory_size, flags);
}

/// Maps the memory and returns a many-item pointer aligned as T.
pub fn mapMemoryAligned(self: Self, memory: vk.DeviceMemory, memory_size: vk.DeviceSize, comptime T: type) ![*]T {
    const data: ?*anyopaque = try self.mapMemory(memory, memory_size);
    const data_aligned_ptr: ?*align(@alignOf(T)) anyopaque = @alignCast(@alignOf(T), data);
    return @ptrCast([*]T, data_aligned_ptr);
}

pub fn unmapMemory(self: Self, memory: vk.DeviceMemory) void {
    self.vkd.unmapMemory(self.device, memory);
}

pub fn freeMemory(self: Self, memory: vk.DeviceMemory) void {
    self.vkd.freeMemory(self.device, memory, null);
}

// Commands -----
pub fn createCommandPool(self: Self, flags: vk.CommandPoolCreateFlags, queue_family_index: u32) !vk.CommandPool {
    return try self.vkd.createCommandPool(self.device, &.{
        .flags = flags,
        .queue_family_index = queue_family_index,
    }, null);
}

pub fn destroyCommandPool(self: Self, command_pool: vk.CommandPool) void {
    self.vkd.destroyCommandPool(self.device, command_pool, null);
}

pub fn resetCommandPool(self: Self, command_pool: vk.CommandPool, flags: vk.CommandPoolResetFlags) void {
    self.vkd.resetCommandPool(self.device, command_pool, flags);
}

pub fn allocateCommandBuffer(self: Self, command_pool: vk.CommandPool, level: vk.CommandBufferLevel) !vk.CommandBuffer {
    const command_buffers_allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = level,
        .command_buffer_count = 1,
    };
    var command_buffer: vk.CommandBuffer = undefined;
    try self.vkd.allocateCommandBuffers(self.device, &command_buffers_allocate_info, @ptrCast([*]vk.CommandBuffer, &command_buffer));
    return command_buffer;
}

pub fn freeCommandBuffer(self: Self, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer) void {
    self.vkd.freeCommandBuffers(self.device, command_pool, 1, @ptrCast([*]const vk.CommandBuffer, &command_buffer));
}

pub fn allocateCommandBufferHandles(self: Self, count: usize) ![]vk.CommandBuffer {
    return try self.allocator.alloc(vk.CommandBuffer, count);
}

pub fn freeCommandBufferHandles(self: Self, handles: []vk.CommandBuffer) void {
    self.allocator.free(handles);
}

pub fn allocateCommandBuffers(self: Self, command_pool: vk.CommandPool, level: vk.CommandBufferLevel, handles: []vk.CommandBuffer) !void {
    const command_buffers_allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = level,
        .command_buffer_count = @intCast(u32, handles.len),
    };

    try self.vkd.allocateCommandBuffers(self.device, &command_buffers_allocate_info, handles.ptr);
}

pub fn freeCommandBuffers(self: Self, command_pool: vk.CommandPool, handles: []vk.CommandBuffer) void {
    self.vkd.freeCommandBuffers(self.device, command_pool, @intCast(u32, handles.len), @ptrCast([*]const vk.CommandBuffer, handles.ptr));
}

pub fn beginRecordCommandBuffer(self: Self, command_buffer: vk.CommandBuffer, usage: vk.CommandBufferUsageFlags) !vk_cmd.CommandBufferRecorder {
    return vk_cmd.CommandBufferRecorder.begin(self, command_buffer, usage);
}

// Uniform buffers
pub fn allocateUniformBuffers(self: Self, comptime BufferType: type, count: usize) ![]vk_mem.AllocatedBuffer {
    const allocator = self.allocator;

    const allocated_buffers = try allocator.alloc(vk_mem.AllocatedBuffer, count);
    errdefer allocator.free(allocated_buffers);

    var allocated_count: usize = 0;
    errdefer for (allocated_buffers[0..allocated_count]) |allocated_uniform_buffer| allocated_uniform_buffer.destroyFree(self);

    while (allocated_count < count) {
        const buffer = try self.createBufferGraphicsQueue(@sizeOf(BufferType), .{ .uniform_buffer_bit = true });
        errdefer self.destroyBuffer(buffer);

        const memory = try self.allocateBufferMemory(buffer, .cpu_gpu_visible);
        errdefer self.freeMemory(memory);

        allocated_buffers[allocated_count] = vk_mem.AllocatedBuffer{ .buffer = buffer, .memory = memory };
        allocated_count += 1;
    }

    return allocated_buffers;
}

pub fn freeUniformBuffers(self: Self, uniform_buffers: []vk_mem.AllocatedBuffer) void {
    for (uniform_buffers) |allocated_buffer| allocated_buffer.destroyFree(self);
    self.allocator.free(uniform_buffers);
}

// Sync
pub fn createFence(self: Self, flags: vk.FenceCreateFlags) !vk.Fence {
    return self.vkd.createFence(self.device, &.{ .flags = flags }, null);
}

pub fn destroyFence(self: Self, fence: vk.Fence) void {
    self.vkd.destroyFence(self.device, fence, null);
}

pub fn waitForFence(self: Self, fence: vk.Fence) !void {
    const wait_all = vk.TRUE;
    const timeout = std.math.maxInt(u64);
    _ = try self.vkd.waitForFences(self.device, 1, @ptrCast([*]const vk.Fence, &fence), wait_all, timeout);
}

pub fn waitForFenceWithTimeout(self: Self, fence: vk.Fence, timeout: u64) !void {
    const wait_all = vk.TRUE;
    _ = try self.vkd.waitForFences(self.device, 1, @ptrCast([*]const vk.Fence, &fence), wait_all, timeout);
}

pub fn resetFence(self: Self, fence: vk.Fence) !void {
    try self.vkd.resetFences(self.device, 1, @ptrCast([*]const vk.Fence, &fence));
}

pub fn createSemaphore(self: Self) !vk.Semaphore {
    return self.vkd.createSemaphore(self.device, &.{ .flags = .{} }, null);
}

pub fn destroySemaphore(self: Self, semaphore: vk.Semaphore) void {
    self.vkd.destroySemaphore(self.device, semaphore, null);
}

// Framebuffers
// Framebuffer
pub fn createFramebuffer(self: Self, create_info: zk.FrameBufferCreateInfo) !vk.Framebuffer {
    return self.vkd.createFramebuffer(self.device, &create_info.raw(), null);
}

pub fn destroyFramebuffer(self: Self, framebuffer: vk.Framebuffer) void {
    self.vkd.destroyFramebuffer(self.device, framebuffer, null);
}

pub fn allocateFramebufferHandles(self: Self, swapchain: Swapchain) ![]vk.Framebuffer {
    return try self.allocator.alloc(vk.Framebuffer, swapchain.images.len);
}

pub fn freeFramebufferHandles(self: Self, handles: []vk.Framebuffer) void {
    self.allocator.free(handles);
}

pub fn createFramebuffers(self: Self, swapchain: Swapchain, render_pass: vk.RenderPass, handles: []vk.Framebuffer) !void {
    var created_count: usize = 0;
    errdefer self.destroyFramebuffers(handles[0..created_count]);

    const depth_image_view = swapchain.depth_image.image_view;

    for (swapchain.images) |swap_image| {
        handles[created_count] = try self.createFramebuffer(.{
            .flags = .{},
            .render_pass = render_pass,
            .attachments = &.{
                swap_image.image_view,
                depth_image_view,
            },
            .extent = swapchain.extent,
            .layer_count = 1,
        });
        created_count += 1;
    }
}

pub fn destroyFramebuffers(self: Self, framebuffers: []const vk.Framebuffer) void {
    for (framebuffers) |framebuffer| self.destroyFramebuffer(framebuffer);
}

pub fn updateDescriptorSets(self: Self, descriptor_writes: []const vk.WriteDescriptorSet, descriptor_copies: []const vk.CopyDescriptorSet) !void {
    self.vkd.updateDescriptorSets(self.device, @intCast(u32, descriptor_writes.len), @ptrCast([*]const vk.WriteDescriptorSet, descriptor_writes.ptr), @intCast(u32, descriptor_copies.len), @ptrCast([*]const vk.CopyDescriptorSet, descriptor_copies.ptr));
}
