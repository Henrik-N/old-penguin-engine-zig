const vk = @import("vulkan");
// const VkContext = @import("vk_context.zig").VkContext;
const VkContext = @import("VkContext.zig");

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
        clear_values: []const vk.ClearValue,
        render_pass: vk.RenderPass,
        framebuffer: vk.Framebuffer,
    };

    pub fn beginRenderPass(self: Self, params: BeginRenderPassParams) void {
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
            .clear_value_count = @intCast(u32, params.clear_values.len),
            .p_clear_values = @ptrCast([*]const vk.ClearValue, params.clear_values.ptr),
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

    pub fn bindIndexBuffer(self: Self, buffer: vk.Buffer, offset: vk.DeviceSize, index_type: vk.IndexType) void {
        self.context.vkd.cmdBindIndexBuffer(self.command_buffer, buffer, offset, index_type);
    }

    pub const BindDescriptorSetsParams = struct {
        bind_point: vk.PipelineBindPoint,
        pipeline_layout: vk.PipelineLayout,
        descriptor_sets: []const vk.DescriptorSet,
        dynamic_offsets: []const u32,
    };

    pub fn bindDescriptorSets(self: Self, params: BindDescriptorSetsParams) void {
        const first_set = 0;
        self.context.vkd.cmdBindDescriptorSets(self.command_buffer, params.bind_point, params.pipeline_layout, first_set, @intCast(u32, params.descriptor_sets.len), @ptrCast([*]const vk.DescriptorSet, params.descriptor_sets.ptr), @intCast(u32, params.dynamic_offsets.len), @ptrCast([*]const u32, params.dynamic_offsets.ptr));
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

    pub const DrawIndexedParams = struct {
        index_count: usize,
        instance_count: usize,
        first_index: usize,
        vertex_offset: isize,
        first_instance: usize,
    };

    pub fn drawIndexed(self: Self, params: DrawIndexedParams) void {
        self.context.vkd.cmdDrawIndexed(
            self.command_buffer,
            @intCast(u32, params.index_count),
            @intCast(u32, params.instance_count),
            @intCast(u32, params.first_index),
            @intCast(i32, params.vertex_offset),
            @intCast(u32, params.first_instance),
        );
    }
};
