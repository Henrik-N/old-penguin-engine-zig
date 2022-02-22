const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");

const VkContext = @import("vk/vk_context.zig").VkContext;
const Swapchain = @import("vk/vk_swapchain.zig").Swapchain;
const PipelineBuilder = @import("vk/vk_pipeline_builder.zig").PipelineBuilder;

const vk_mem = @import("vk/vk_memory.zig");

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

    var swapchain = try Swapchain.init(context, window, allocator);
    defer swapchain.deinit(context, allocator);

    const vert_shader_module = try vk_init.shaderModule(context, ShaderResources.tri_vert);
    defer context.vkd.destroyShaderModule(context.device, vert_shader_module, null);

    const frag_shader_module = try vk_init.shaderModule(context, ShaderResources.tri_frag);
    defer context.vkd.destroyShaderModule(context.device, frag_shader_module, null);

    // pipeline
    //

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

    const pipeline_builder = PipelineBuilder(.{
        .shader_stage_count = 2,
        .color_blend_attachment_state_count = 1,
    }){
        .shader_stages = .{
            vk_init.pipeline.shaderStageCreateInfo(.{ .vertex_bit = true }, vert_shader_module),
            vk_init.pipeline.shaderStageCreateInfo(.{ .fragment_bit = true }, frag_shader_module),
        },
        .vertex_input_state = vk_init.pipeline.vertexInputStateCreateInfo(),
        .input_assembly_state = vk_init.pipeline.inputAssemblyStateCreateInfo(vk.PrimitiveTopology.triangle_list),
        .tesselation_state = null,
        .viewport = vk_init.pipeline.viewport(swapchain.extent),
        .scissor = vk_init.pipeline.scissor(swapchain.extent),
        .rasterization_state = vk_init.pipeline.rasterizationStateCreateInfo(vk.PolygonMode.fill), // .line, .point
        .multisample_state = vk_init.pipeline.multisampleStateCreateInfo(),
        .depth_stencil_state = null,
        .dynamic_state = null,
        .color_blend_attachment_states = .{
            vk_init.pipeline.colorBlendAttachmentState(.alpha_blending),
        },
        .pipeline_layout = pipeline_layout,
        .render_pass = render_pass,
    };
    const pipeline = try pipeline_builder.init_pipeline(context);
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
    // const render_fence = try vk_init.fence(context, .{ .signaled_bit = true });
    // defer context.vkd.destroyFence(context.device, render_fence, null);

    // const image_acquired_semaphore = try vk_init.semaphore(context);
    // defer context.vkd.destroySemaphore(context.device, image_acquired_semaphore, null);

    // const render_complete_semaphore = try vk_init.semaphore(context);
    // defer context.vkd.destroySemaphore(context.device, render_complete_semaphore, null);


    const buffer = try vk_mem.createBuffer(context, @sizeOf(u32), .{ .vertex_buffer_bit = true });
    defer vk_mem.destroyBuffer(context, buffer);

    var frame_num: f32 = 0;

    while (!window.shouldClose()) {
        try glfw.pollEvents();
        frame_num += 1; // TODO overflow check stuff

        const command_buffer = command_buffers[swapchain.current_image_index];

        {
            std.log.info("Frame num: {d}, resetting command buffer", .{@trunc(frame_num)});
            try context.vkd.resetCommandBuffer(command_buffer, .{ .release_resources_bit = true });
            try context.vkd.beginCommandBuffer(command_buffer, &.{
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

            // render pass
            context.vkd.cmdBeginRenderPass(command_buffer, &.{
                .render_pass = render_pass,
                .framebuffer = framebuffers[swapchain.current_image_index], // temp
                .render_area = render_area,
                .clear_value_count = 1,
                .p_clear_values = @ptrCast([*]const vk.ClearValue, &clear_value),
            }, .@"inline");

            context.vkd.cmdBindPipeline(command_buffer, vk.PipelineBindPoint.graphics, pipeline);
            context.vkd.cmdDraw(command_buffer, 3, 1, 0, 0);

            context.vkd.cmdEndRenderPass(command_buffer);

            try context.vkd.endCommandBuffer(command_buffer);
        }

        // create for each swapchain image

        try swapchain.submitPresentCommandBuffer(context, command_buffer);

        // const pipeline_wait_stage: vk.PipelineStageFlags = vk.PipelineStageFlags{ .color_attachment_output_bit = true };

        // const submit_info = vk.SubmitInfo{
        //     .wait_semaphore_count = 1,
        //     .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &image_acquired_semaphore),
        //     .p_wait_dst_stage_mask = @ptrCast([*]const vk.PipelineStageFlags, &pipeline_wait_stage),
        //     .command_buffer_count = 1,
        //     .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &test_cmd_buf),
        //     .signal_semaphore_count = 1,
        //     .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &render_complete_semaphore),
        // };

        // try context.vkd.queueSubmit(context.graphics_queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info), render_fence);

        // // TODO THIS IS TEMP
        // try context.vkd.queueWaitIdle(context.graphics_queue.handle);

        // const present_info = vk.PresentInfoKHR{
        //     .wait_semaphore_count = 1,
        //     .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &render_complete_semaphore),
        //     .swapchain_count = 1,
        //     .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &swapchain.handle),
        //     .p_image_indices = @ptrCast([*]const u32, &swapchain_image_index),
        //     .p_results = null,
        // };

        // _ = try context.vkd.queuePresentKHR(context.present_queue.handle, &present_info);
    }

    try context.vkd.deviceWaitIdle(context.device);
}
