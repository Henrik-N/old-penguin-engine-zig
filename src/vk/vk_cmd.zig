const vk = @import("vulkan");
// const VkContext = @import("vk_context.zig").VkContext;
const VkContext = @import("VkContext.zig");

const vk_sync = @import("vk_sync.zig");
const vk_init = @import("vk_init.zig");

const mem = @import("std").mem;

const vk_cmd = @This();

pub fn beginCommandBuffer(context: VkContext, command_buffer: vk.CommandBuffer, usage: vk.CommandBufferUsageFlags) !void {
    const cmd_buf_begin_info = vk.CommandBufferBeginInfo{
        .flags = usage,
        .p_inheritance_info = null,
    };

    try context.vkd.beginCommandBuffer(command_buffer, &cmd_buf_begin_info);
}

pub fn endCommandBuffer(context: VkContext, command_buffer: vk.CommandBuffer) !void {
    try context.vkd.endCommandBuffer(command_buffer);
}

pub const CommandBufferRecorder = struct {
    context: *const VkContext,
    command_buffer: vk.CommandBuffer,

    const Self = @This();

    pub fn begin(context: VkContext, command_buffer: vk.CommandBuffer, usage: vk.CommandBufferUsageFlags) !Self {
        const cmd_buf_begin_info = vk.CommandBufferBeginInfo{
            .flags = usage,
            .p_inheritance_info = null,
        };

        try context.vkd.beginCommandBuffer(command_buffer, &cmd_buf_begin_info);

        return Self{
            .context = &context,
            .command_buffer = command_buffer,
        };
    }

    pub fn beginImmediateSubmit(context: VkContext) !Self {
        const command_buffer = try context.upload_context.immediateSubmitBegin(context);

        return Self{
            .context = &context,
            .command_buffer = command_buffer,
        };
    }

    pub fn end(self: Self) !void {
        try self.context.vkd.endCommandBuffer(self.command_buffer);
    }

    pub fn endImmediateSubmit(self: Self) !void {
        try self.context.upload_context.immediateSubmitEnd(self.context.*);
    }

    pub fn copyBuffer(self: Self, dst: vk.Buffer, src: vk.Buffer, regions: []const vk.BufferCopy) void {
        self.context.vkd.cmdCopyBuffer(
            self.command_buffer,
            src,
            dst,
            @intCast(u32, regions.len),
            @ptrCast([*]const vk.BufferCopy, regions.ptr),
        );
    }

    pub fn setViewport(self: Self, viewport: vk.Viewport) void {
        self.context.vkd.cmdSetViewport(self.command_buffer, 0, 1, @ptrCast([*]const vk.Viewport, &viewport));
    }

    pub fn setScissor(self: Self, scissor: vk.Rect2D) void {
        self.context.vkd.cmdSetScissor(self.command_buffer, 0, 1, @ptrCast([*]const vk.Rect2D, &scissor));
    }

    pub const BeginRenderPassParams = struct {
        extent: vk.Extent2D,
        clear_color: [4]f32,

        render_pass: vk.RenderPass,
        framebuffer: vk.Framebuffer,
    };

    pub fn beginRenderPass(self: Self, params: BeginRenderPassParams) void {
        const clear_value = vk.ClearValue{
            .color = .{ .float_32 = params.clear_color },
        };

        const render_area = vk.Rect2D{
            .offset = .{
                .x = 0,
                .y = 0,
            },
            .extent = params.extent,
        };

        self.context.vkd.cmdBeginRenderPass(self.command_buffer, &.{
            .render_pass = params.render_pass,
            .framebuffer = params.framebuffer,
            .render_area = render_area,
            .clear_value_count = 1,
            .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear_value),
        }, .@"inline");
    }

    pub fn endRenderPass(self: Self) void {
        self.context.vkd.cmdEndRenderPass(self.command_buffer);
    }

    pub fn bindPipeline(self: Self, pipeline: vk.Pipeline, bind_point: vk.PipelineBindPoint) void {
        self.context.vkd.cmdBindPipeline(self.command_buffer, bind_point, pipeline);
    }

    pub const BindVertexBuffersParams = struct {
        first_binding: u32,
        vertex_buffers: []const vk.Buffer,
        offsets: []const vk.DeviceSize,
    };

    pub fn bindVertexBuffers(self: Self, params: BindVertexBuffersParams) void {
        self.context.vkd.cmdBindVertexBuffers(self.command_buffer, params.first_binding, @intCast(u32, params.vertex_buffers.len), @ptrCast([*]const vk.Buffer, params.vertex_buffers.ptr), @ptrCast([*]const vk.DeviceSize, params.offsets.ptr));
    }

    pub const DrawParams = struct {
        vertex_count: u32,
        instance_count: u32,
        first_vertex: u32,
        first_instance: u32,
    };

    pub fn draw(self: Self, params: DrawParams) void {
        self.context.vkd.cmdDraw(self.command_buffer, params.vertex_count, params.instance_count, params.first_vertex, params.first_instance);
    }

    // context.vkd.cmdBindVertexBuffers(command_buffer, 0, 1, @ptrCast([*]const vk.Buffer, &params.vertex_buffer), &offset);
    //     context.vkd.cmdDraw(command_buffer, vertices.len, 1, 0, 0);

    // pub const RenderPassBeginParams = struct {

    // };

    // pub fn beginRenderPass(self: Self, render_pass: vk.RenderPass, render_area: vk.Extent2D) !void {

    //  context.vkd.cmdBeginRenderPass(cmdbuf, &.{
    //     .render_pass = params.render_pass,
    //     .framebuffer = params.framebuffer,
    //     .render_area = render_area,
    //     .clear_value_count = 1,
    //     .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
    // }, .@"inline");

    // const render_area = vk.Rect2D{
    //     .offset = .{ .x = 0, .y = 0 },
    //     .extent = params.extent,
    // };

    // context.vkd.cmdBeginRenderPass(cmdbuf, &.{
    //     .render_pass = params.render_pass,
    //     .framebuffer = params.framebuffer,
    //     .render_area = render_area,
    //     .clear_value_count = 1,
    //     .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear),
    // }, .@"inline");

    // }
};

// pub fn setViewport(context: VkContext, viewport: vk.Viewport) !void {}

// pub fn beginSingleTimeCommands(context: VkContext, command_pool: vk.CommandPool) !vk.CommandBuffer {
//
//     const command_buffer = vk_init.commandBuffer(context, command_pool, .primary);
//     vk_cmd.beginCommandBuffer(cotext, command_buffer, .{ .singl})
//
//
//
// }

// pub fn queueSubmit(context: VkContext, command_buffer: vk.CommandBuffer, queue: vk.Queue, sync_info: vk_sync.SyncInfo) !void {
//     // const sub_info = vk.SubmitInfo{
//     //     .wait_semaphore_count = if (sync.info.wait_semaphore != .null_handle) 1 else 0,
//     //     .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &sync_info.wait_semaphore),
//
//     // };
//
//     const submit_info = vk.SubmitInfo{
//         .wait_semaphore_count = if (sync_info.wait_semaphore) |_| 1 else 0,
//         .p_wait_semaphores = if (sync_info.wait_semaphore) |wait_semaphore| @ptrCast([*]const vk.Semaphore, &wait_semaphore) else undefined,
//         .p_wait_dst_stage_mask = if (sync_info.wait_stage) |wait_stage| @ptrCast([*]const vk.PipelineStageFlags, &wait_stage) else undefined,
//         .command_buffer_count = 1,
//         .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &command_buffer),
//         .signal_semaphore_count = if (sync_info.signal_semaphore) |_| 1 else 0,
//         .p_signal_semaphores = if (sync_info.signal_semaphore) |signal_semaphore| @ptrCast([*]const vk.Semaphore, &signal_semaphore) else undefined,
//     };
//
//     try context.vkd.queueSubmit(queue, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info), fence: Fence)
//
//     try context.vkd.queueSubmit(queue, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info, signal_fence);
// }
