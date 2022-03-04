// const std = @import("std");
// const Allocator = std.mem.Allocator;
// const vk = @import("vulkan");
// const zk = @import("zulkan.zig");
//
// const vk_mem = @import("vk_memory.zig");
//
// const DeviceDispatch = @import("vk_dispatch.zig").DeviceDispatch;
//
// const VkDevice = @This();
// const Self = VkDevice;
//
// //allocator: Allocator,
// //
// handle: vk.Device,
// vkd: DeviceDispatch,
// //
//
// pub fn init(device: vk.Device, vkd: DeviceDispatch) Self {
//     return Self{
//         .handle = device,
//         .vkd = vkd,
//     };
// }
//
// pub fn createShaderModule(self: Self, comptime shader_source: []const u8) !vk.ShaderModule {
//     return self.vkd.createShaderModule(self.handle, &.{
//         .flags = .{},
//         .code_size = @intCast(u32, shader_source.len),
//         .p_code = @ptrCast([*]const u32, shader_source.ptr),
//     }, null);
// }
//
// pub fn destroyShaderModule(self: Self, shader_module: vk.ShaderModule) void {
//     self.vkd.destroyShaderModule(self.handle, shader_module, null);
// }
//
// pub fn createRenderPass(self: Self, create_info: zk.RenderPassCreateInfo) !vk.RenderPass {
//     return self.vkd.createRenderPass(self.handle, &create_info.raw(), null);
// }
//
// pub fn destroyRenderPass(self: Self, render_pass: vk.RenderPass) void {
//     self.vkd.destroyRenderPass(self.handle, render_pass, null);
// }
//
// pub fn createDescriptorSetLayout(self: Self, create_info: zk.DescriptorSetLayoutCreateInfo) !vk.DescriptorSetLayout {
//     return self.vkd.createDescriptorSetLayout(self.handle, &create_info.raw(), null);
// }
//
// pub fn destroyDescriptorSetLayout(self: Self, descriptor_set_layout: vk.DescriptorSetLayout) void {
//     self.vkd.destroyDescriptorSetLayout(self.handle, descriptor_set_layout, null);
// }
//
// pub fn createDescriptorPool(self: Self, create_info: zk.DescriptorPoolCreateInfo) !vk.DescriptorPool {
//     return self.vkd.createDescriptorPool(self.handle, &create_info.raw(), null);
// }
//
// pub fn destroyDescriptorPool(self: Self, descriptor_pool: vk.DescriptorPool) void {
//     self.vkd.destroyDescriptorPool(self.handle, descriptor_pool, null);
// }
//
// pub fn createPipelineLayout(self: Self, create_info: zk.PipelineLayoutCreateInfo) !vk.PipelineLayout {
//     return self.vkd.createPipelineLayout(self.handle, &create_info.raw(), null);
// }
//
// pub fn destroyPipelineLayout(self: Self, pipeline_layout: vk.PipelineLayout) void {
//     self.vkd.destroyPipelineLayout(self.handle, pipeline_layout, null);
// }
//
// pub fn createFramebuffer(self: Self, create_info: zk.FrameBufferCreateInfo) !vk.Framebuffer {
//     return self.vkd.createFramebuffer(self.handle, &create_info.raw(), null);
// }
//
// pub fn destroyFramebuffer(self: Self, framebuffer: vk.Framebuffer) void {
//     self.vkd.destroyFramebuffer(self.handle, framebuffer, null);
// }
//
// pub const CreateBufferParams = struct { size: vk.DeviceSize, usage: vk.BufferUsageFlags, queue_family: u32 };
//
// pub fn createBuffer(self: Self, params: CreateBufferParams) !vk.Buffer {
//     return self.vkd.createBuffer(self.handle, &.{
//         .flags = .{},
//         .size = params.size,
//         .usage = params.usage,
//         .sharing_mode = .exclusive,
//         .queue_family_index_count = 1,
//         .p_queue_family_indices = @ptrCast([*]const u32, &params.queue_family),
//     }, null);
// }
//
// pub fn destroyBuffer(self: Self, buffer: vk.Buffer) void {
//     self.vkd.destroyBuffer(self.handle, buffer, null);
// }
//
// pub fn freeMemory(self: Self, memory: vk.DeviceMemory) void {
//     self.vkd.freeMemory(self.handle, memory, null);
// }
