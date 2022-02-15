const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");
const VkContext = @import("vk/vk_context.zig").VkContext;
const Swapchain = @import("vk/vk_swapchain.zig").Swapchain;

const ShaderResources = @import("resources");

const vk_init = @import("vk/vk_init.zig");

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    const app_name = "Penguin Engine";

    const window = try glfw.Window.create(extent.width, extent.height, app_name, null, null, .{
        .client_api = .no_api, // don't create an OpenGL context
    });
    defer window.destroy();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const context = try VkContext.init(app_name, window, allocator);
    defer context.deinit();

    const swapchain = try Swapchain.init(context, window, allocator);
    defer swapchain.deinit(context, allocator);

    const vert_shader_module = try vk_init.shaderModule(context, ShaderResources.tri_vert);
    defer context.vkd.destroyShaderModule(context.device, vert_shader_module, null);

    const frag_shader_module = try vk_init.shaderModule(context, ShaderResources.tri_frag);
    defer context.vkd.destroyShaderModule(context.device, frag_shader_module, null);

    // pipeline
    //
    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        vk_init.pipeline.shaderStageCreateInfo(.{ .vertex_bit = true }, vert_shader_module),
        vk_init.pipeline.shaderStageCreateInfo(.{ .fragment_bit = true }, frag_shader_module),
    };

    const vertex_input_state = vk_init.pipeline.vertexInputStateCreateInfo();
    const input_assembly_state = vk_init.pipeline.inputAssemblyStateCreateInfo(vk.PrimitiveTopology.triangle_list);
    // const tessellation_state: ?vk.PipelineTessellationStateCreateInfo = null;

    const viewport = vk_init.pipeline.viewport(swapchain.extent);
    const scissor = vk_init.pipeline.scissor(swapchain.extent);
    const viewport_state = vk_init.pipeline.viewportStateCreateInfo(viewport, scissor);

    const rasterization_state = vk_init.pipeline.rasterizationStateCreateInfo(vk.PolygonMode.fill); // .line, .point
    const multisample_state = vk_init.pipeline.multisampleStateCreateInfo();
    // const depth_stencil_state: ?vk.PipelineDepthStencilStateCreateInfo = null;
    const color_blend_attachment_states = [_]vk.PipelineColorBlendAttachmentState{
        vk_init.pipeline.colorBlendAttachmentState(.alpha_blending),
    };
    const color_blend_state = vk_init.pipeline.colorBlendStateCreateInfo(color_blend_attachment_states[0..]);
    //const dynamic_states_to_enable = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
    //const dynamic_state = vk_init.pipeline.dynamicStateCreateInfo(dynamic_states_to_enable[0..]);

    const pipeline_layout = try context.vkd.createPipelineLayout(context.device, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer context.vkd.destroyPipelineLayout(context.device, pipeline_layout, null);

    const render_pass = try vk_init.defaultRenderPass(context, swapchain);
    defer context.vkd.destroyRenderPass(context.device, render_pass, null);

    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = @intCast(u32, shader_stages.len),
        .p_stages = @ptrCast([*]const vk.PipelineShaderStageCreateInfo, &shader_stages),
        .p_vertex_input_state = &vertex_input_state,
        .p_input_assembly_state = &input_assembly_state,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_state,
        .p_rasterization_state = &rasterization_state,
        .p_multisample_state = &multisample_state,
        .p_depth_stencil_state = null,
        .p_color_blend_state = &color_blend_state,
        .p_dynamic_state = null,
        .layout = pipeline_layout,
        // NOTE It is possible to use other render passes with this pipeline instance than the one set here,
        // provided they are a compatible renderpass.
        // More info here: https://www.khronos.org/registry/vulkan/specs/1.3-extensions/html/chap8.html#renderpass-compatibility
        .render_pass = render_pass,
        .subpass = 0, // the index of the subpass in the render pass where this pipeline will be used
        //
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    const pipeline_cache: vk.PipelineCache = .null_handle;

    var pipeline: vk.Pipeline = undefined;
    _ = try context.vkd.createGraphicsPipelines(context.device, pipeline_cache, 1, // pipeline count
        @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &pipeline_create_info), null, @ptrCast([*]vk.Pipeline, &pipeline));
    defer context.vkd.destroyPipeline(context.device, pipeline, null);

    const framebuffers = try vk_init.frameBuffers(allocator, context, render_pass, swapchain);
    defer allocator.free(framebuffers);
    defer for (framebuffers) |framebuffer| context.vkd.destroyFramebuffer(context.device, framebuffer, null);

    // command pool and command buffers
    // const command_pool = try vk_init.commandPool(context, .{}, context.graphics_queue.family);
    const command_pool = try vk_init.commandPool(context, .{ .reset_command_buffer_bit = true }, context.graphics_queue.family); // TODO the reset flag is temp
    defer context.vkd.destroyCommandPool(context.device, command_pool, null);

    const command_buffers = try vk_init.commandBuffers(allocator, context, command_pool, .primary, framebuffers.len);
    defer allocator.free(command_buffers); // destroys the handles only. The subsequent call to destroyCommandPool will clear up the data.

    // sync
    // const fence = try context.vkd.createFence(context.device, &.{ .flags = .{ .signaled_bit = true }, }, null);
    const render_fence = try vk_init.fence(context, .{ .signaled_bit = true });
    defer context.vkd.destroyFence(context.device, render_fence, null);

    const image_acquired_semaphore = try vk_init.semaphore(context);
    defer context.vkd.destroySemaphore(context.device, image_acquired_semaphore, null);

    const render_complete_semaphore = try vk_init.semaphore(context);
    defer context.vkd.destroySemaphore(context.device, render_complete_semaphore, null);

    var frame_num: f32 = 0;

    while (!window.shouldClose()) {
        try glfw.pollEvents();
        frame_num += 1; // TODO overflow check stuff

        //------------- render loop ----------------
        const timeout = std.math.maxInt(u64); // TODO change timeout?
        _ = try context.vkd.waitForFences(context.device, 1, @ptrCast([*]const vk.Fence, &render_fence), vk.TRUE, timeout);
        _ = try context.vkd.resetFences(context.device, 1, @ptrCast([*]const vk.Fence, &render_fence));

        const result = try context.vkd.acquireNextImageKHR(context.device, swapchain.handle, timeout, image_acquired_semaphore, .null_handle);
        const swapchain_image_index = result.image_index;

        const test_cmd_buf = command_buffers[swapchain_image_index];

        {
            try context.vkd.resetCommandBuffer(test_cmd_buf, .{});
            try context.vkd.beginCommandBuffer(test_cmd_buf, &.{
                .flags = .{ .one_time_submit_bit = true },
                .p_inheritance_info = null, // for secondary command buffers
            });

            const flash: f32 = std.math.sin(frame_num / 120);
            const clear_value = vk.ClearValue{
                .color = .{ .float_32 = .{ 0, 0, flash, 1 } },
            };

            const render_area = vk.Rect2D{
                .offset = .{ .x = 0, .y = 0 },
                .extent = swapchain.extent,
            };

            const render_pass_begin_info = vk.RenderPassBeginInfo{
                .render_pass = render_pass,
                .framebuffer = framebuffers[swapchain_image_index], // temp
                .render_area = render_area,
                .clear_value_count = 1,
                .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear_value),
            };
            {
                // render pass
                context.vkd.cmdBeginRenderPass(test_cmd_buf, &render_pass_begin_info, .@"inline");
                defer context.vkd.cmdEndRenderPass(test_cmd_buf);

                context.vkd.cmdBindPipeline(test_cmd_buf, vk.PipelineBindPoint.graphics, pipeline);
                context.vkd.cmdDraw(test_cmd_buf, 3, 1, 0, 0);
            } // end of render pass

            try context.vkd.endCommandBuffer(test_cmd_buf);
        } // end of command buffer

        const pipeline_wait_stage: vk.PipelineStageFlags = vk.PipelineStageFlags{ .color_attachment_output_bit = true };

        const submit_info = vk.SubmitInfo{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &image_acquired_semaphore),
            .p_wait_dst_stage_mask = @ptrCast([*]const vk.PipelineStageFlags, &pipeline_wait_stage),
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &test_cmd_buf),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &render_complete_semaphore),
        };

        try context.vkd.queueSubmit(context.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info), render_fence);

        // TODO THIS IS TEMP
        try context.vkd.queueWaitIdle(context.graphics_queue.handle);

        const present_info = vk.PresentInfoKHR{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &render_complete_semaphore),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &swapchain.handle),
            .p_image_indices = @ptrCast([*]const u32, &swapchain_image_index),
            .p_results = null,
        };

        _ = try context.vkd.queuePresentKHR(context.present_queue.handle, &present_info);
    }

    try context.vkd.deviceWaitIdle(context.device);
}
