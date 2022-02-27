const vk = @import("vulkan");
const VkContext = @import("VkContext.zig");

const std = @import("std");

pub const SyncInfo = struct {
    signal_fence: ?vk.Fence,
    wait_semaphore: ?vk.Semaphore,
    wait_stage: ?vk.PipelineStageFlags,
    signal_semaphore: ?vk.Semaphore,
};

pub fn waitForFence(context: VkContext, fence: vk.Fence) !void {
    const wait_all = vk.TRUE;
    const timeout = std.math.maxInt(u64);

    _ = try context.vkd.waitForFences(context.device, 1, @ptrCast([*]const vk.Fence, &fence), wait_all, timeout);
}

pub fn resetFence(context: VkContext, fence: vk.Fence) !void {
    try context.vkd.resetFences(context.device, 1, @ptrCast([*]const vk.Fence, &fence));
}
