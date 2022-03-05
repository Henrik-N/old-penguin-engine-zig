const vk = @import("vulkan");
const VkContext = @import("VkContext.zig");
const vk_init = @import("vk_init.zig");
const vk_cmd = @import("vk_cmd.zig");

const UploadContext = @This();
const Self = UploadContext;

upload_fence: vk.Fence,
command_pool: vk.CommandPool,
command_buffer: vk.CommandBuffer,
queue: VkContext.DeviceQueue,

// TODO maybe use a transfer queue on a seperate thread in the future rather than the graphics queue
pub fn init(context: VkContext, queue: VkContext.DeviceQueue) !Self {
    const fence = try context.createFence(.{});

    const command_pool = try context.createCommandPool(.{ .reset_command_buffer_bit = true }, queue.family);
    const command_buffer = try context.allocateCommandBuffer(command_pool, .primary);

    return Self{
        .upload_fence = fence,
        .command_pool = command_pool,
        .command_buffer = command_buffer,
        .queue = queue,
    };
}

pub fn deinit(self: Self, context: VkContext) void {
    context.destroyFence(self.upload_fence);
    context.freeCommandBuffer(self.command_pool, self.command_buffer);
    context.destroyCommandPool(self.command_pool);
}

pub fn immediateSubmitBegin(self: Self, context: VkContext) !vk.CommandBuffer {
    try vk_cmd.beginCommandBuffer(context, self.command_buffer, .{ .one_time_submit_bit = true });

    return self.command_buffer;
}

pub fn immediateSubmitEnd(self: Self, context: VkContext) !void {
    const cmd_buf = self.command_buffer;

    try vk_cmd.endCommandBuffer(context, cmd_buf);

    const submit_info = vk.SubmitInfo{
        .wait_semaphore_count = 0,
        .p_wait_semaphores = undefined,
        .p_wait_dst_stage_mask = undefined,
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmd_buf),
        .signal_semaphore_count = 0,
        .p_signal_semaphores = undefined,
    };

    try context.vkd.queueSubmit(self.queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info), self.upload_fence);

    try context.waitForFence(self.upload_fence);
    try context.resetFence(self.upload_fence);

    try context.vkd.resetCommandBuffer(self.command_buffer, .{});
}
