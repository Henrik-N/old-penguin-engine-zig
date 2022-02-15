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
    const viewport_state = vk_init.pipeline.viewportStateCreateInfo();
    const rasterization_state = vk_init.pipeline.rasterizationStateCreateInfo(vk.PolygonMode.fill); // .line, .point
    const multisample_state = vk_init.pipeline.multisampleStateCreateInfo();
    // const depth_stencil_state: ?vk.PipelineDepthStencilStateCreateInfo = null;
    const color_blend_attachment_states = [_]vk.PipelineColorBlendAttachmentState{
        vk_init.pipeline.colorBlendAttachmentState(.alpha_blending),
    };
    const color_blend_state = vk_init.pipeline.colorBlendStateCreateInfo(color_blend_attachment_states[0..]);
    const dynamic_states_to_enable = [_]vk.DynamicState{ .viewport, .scissor, .line_width };
    const dynamic_state = vk_init.pipeline.dynamicStateCreateInfo(dynamic_states_to_enable[0..]);

    const pipeline_layout = try context.vkd.createPipelineLayout(context.device, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer context.vkd.destroyPipelineLayout(context.device, pipeline_layout, null);

    const render_pass = try initDefaultRenderPass(context, swapchain);
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
        .p_dynamic_state = &dynamic_state,
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

    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}

fn initDefaultRenderPass(context: VkContext, swapchain: Swapchain) !vk.RenderPass {
    const attachments = [_]vk.AttachmentDescription{
        // color attachment
        .{
            .flags = .{},
            .format = swapchain.surface_format.format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear, // what to do with the data before rendering, clear framebuffer
            .store_op = .store, // what to do with the data after rendering, store framebuffer (as we want to see the contents on the screen)
            //
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            //
            .initial_layout = .@"undefined", // we clear it anyway
            .final_layout = .present_src_khr, // ready image for presentation in the swapchain
        },
    };

    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0,
        .layout = .color_attachment_optimal,
    };

    const subpasses = [_]vk.SubpassDescription{
    // color subpass
    .{
        .flags = .{},
        .pipeline_bind_point = .graphics,
        .input_attachment_count = 0,
        .p_input_attachments = undefined,
        .color_attachment_count = 1,
        .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, &color_attachment_ref),
        .p_resolve_attachments = null,
        .p_depth_stencil_attachment = null,
        .preserve_attachment_count = 0,
        .p_preserve_attachments = undefined,
    }};

    const render_pass_create_info = vk.RenderPassCreateInfo{
        .flags = .{},
        .attachment_count = @intCast(u32, attachments.len),
        .p_attachments = @ptrCast([*]const vk.AttachmentDescription, &attachments),
        .subpass_count = @intCast(u32, subpasses.len),
        .p_subpasses = @ptrCast([*]const vk.SubpassDescription, &subpasses),
        .dependency_count = 0,
        .p_dependencies = undefined,
    };

    return try context.vkd.createRenderPass(context.device, &render_pass_create_info, null);
}
