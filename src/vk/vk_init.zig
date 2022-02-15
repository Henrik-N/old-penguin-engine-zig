const vk = @import("vulkan");
const VkContext = @import("vk_context.zig").VkContext;
const Swapchain = @import("vk_swapchain.zig").Swapchain;
const Allocator = @import("std").mem.Allocator;

pub fn shaderModule(context: VkContext, comptime shader_source: []const u8) !vk.ShaderModule {
    const shader_module = try context.vkd.createShaderModule(context.device, &.{
        .flags = .{},
        .code_size = shader_source.len,
        .p_code = @ptrCast([*]const u32, shader_source),
    }, null);
    return shader_module;
}

/// default structures and convenience functions for initializing a pipeline
pub const pipeline = struct {
    /// Information about a single shader stage in a pipeline.
    pub fn shaderStageCreateInfo(stage_flags: vk.ShaderStageFlags, shader_module: vk.ShaderModule) vk.PipelineShaderStageCreateInfo {
        return .{
            .flags = .{},
            .stage = stage_flags,
            .module = shader_module,
            .p_name = "main",
            .p_specialization_info = null,
        };
    }

    // TODO fill out, returning an empty for now
    /// Configuration for the vertex shader input format.
    pub fn vertexInputStateCreateInfo() vk.PipelineVertexInputStateCreateInfo {
        return .{
            .flags = .{},
            .vertex_binding_description_count = 0,
            .p_vertex_binding_descriptions = undefined,
            .vertex_attribute_description_count = 0,
            .p_vertex_attribute_descriptions = undefined,
        };
    }

    /// Configuration for how the vertex input will be read, 
    /// i.e. what geometry will be drawn from the vertex input.
    pub fn inputAssemblyStateCreateInfo(topology: vk.PrimitiveTopology) vk.PipelineInputAssemblyStateCreateInfo {
        return .{
            .flags = .{},
            .topology = topology,
            // Primitive restart == load vertices from the vertex buffer in a custom order.
            .primitive_restart_enable = vk.FALSE,
        };
    }

    /// Details about the regions of the framebuffer we'll render to. 
    /// Penguin Engine will only use one viewport that covers the entire screen, at least for now.
    pub fn viewportStateCreateInfo() vk.PipelineViewportStateCreateInfo {
        return .{
            .flags = .{},
            .viewport_count = 1,
            .p_viewports = undefined, // setting this dynamically in command buffer.
            .scissor_count = 1,
            .p_scissors = undefined, // setting this dynamically in command buffer.
        };
    }

    /// Configuration regarding how to turn the geometry into fragments (basically pixels) for the fragment shader.
    pub fn rasterizationStateCreateInfo(polygon_mode: vk.PolygonMode) vk.PipelineRasterizationStateCreateInfo {
        return .{
            .flags = .{},
            .depth_clamp_enable = vk.FALSE, // clamp fragments outside of the depth to the min/max planes. Requires enabling additional gpu feature.
            .rasterizer_discard_enable = vk.FALSE, // disables throughput through this state - true == no output to framebuffer
            .polygon_mode = polygon_mode,
            .line_width = 1,
            .cull_mode = .{ .back_bit = true },
            .front_face = .clockwise,
            .depth_bias_enable = vk.FALSE, // alter depth values in the rasterizer, used for shadow mapping
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        };
    }

    /// Configuration for multisampling, one of the ways to achieve anti-aliasing. Not used for now.
    pub fn multisampleStateCreateInfo() vk.PipelineMultisampleStateCreateInfo {
        return .{
            .flags = .{},
            .sample_shading_enable = vk.FALSE,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = vk.FALSE,
            .alpha_to_one_enable = vk.FALSE,
        };
    }

    // TODO depth/stencil tests configuration

    pub const Blending = enum {
        no_blending,
        alpha_blending,
    };

    /// Framebuffer-specific configuration for how to blend the color returned from a fragment shader with the color already present in the framebuffer.
    /// Either mix the colors or completely replace the one that is already there.
    pub fn colorBlendAttachmentState(blending: Blending) vk.PipelineColorBlendAttachmentState {
        const rgba_mask = vk.ColorComponentFlags{ .r_bit = true, .g_bit = true, .b_bit = true, .a_bit = true };

        switch (blending) {
            .no_blending => return .{
                .color_write_mask = rgba_mask,
                .blend_enable = vk.FALSE, // no blending, just replace the color
                // values below are ignored
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
            },
            .alpha_blending => return .{
                .color_write_mask = rgba_mask,
                .blend_enable = vk.TRUE,
                // color
                .src_color_blend_factor = .src_alpha,
                .dst_color_blend_factor = .one_minus_src_alpha,
                .color_blend_op = .add,
                // alpha
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
            },
        }
    }

    /// Global (references the array of structs for all the framebuffers) configuration for color blending. 
    /// Here you attach the framebuffer-specific configuration and set blend constants to use in vk.PipelineColorBlendAttachmentStateCreateInfo.
    /// @lifetime color_blend_attachments must outlive the returned struct.
    pub fn colorBlendStateCreateInfo(color_blend_attachments: []const vk.PipelineColorBlendAttachmentState) vk.PipelineColorBlendStateCreateInfo {
        return .{
            .flags = .{},
            .logic_op_enable = vk.FALSE, // for if you want to use bitwise combination blending
            .logic_op = .copy, // bitwise combination blending op (if enabled)
            .attachment_count = @intCast(u32, color_blend_attachments.len),
            .p_attachments = @ptrCast([*]const vk.PipelineColorBlendAttachmentState, color_blend_attachments),
            .blend_constants = [_]f32{ 0, 0, 0, 0 }, // not using these right now
        };
    }

    /// Some configurations may be changed dynamically after pipeline creation.
    /// dynamic_states defines which configurations to enable dynamic state for.
    /// @lifetime dynamic_states must outlive the returned struct
    pub fn dynamicStateCreateInfo(dynamic_states: []const vk.DynamicState) vk.PipelineDynamicStateCreateInfo {
        return .{
            .flags = .{},
            .dynamic_state_count = @intCast(u32, dynamic_states.len),
            .p_dynamic_states = @ptrCast([*]const vk.DynamicState, dynamic_states),
        };
    }
};

pub fn defaultRenderPass(context: VkContext, swapchain: Swapchain) !vk.RenderPass {
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

pub fn frameBuffers(allocator: Allocator, context: VkContext, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers = try allocator.alloc(vk.Framebuffer, swapchain.images.len);
    errdefer allocator.free(framebuffers);

    var initialized_count: usize = 0;
    errdefer for (framebuffers[0..initialized_count]) |framebuffer| context.vkd.destroyFramebuffer(context.device, framebuffer, null);

    const framebuffer_width = swapchain.extent.width;
    const framebuffer_height = swapchain.extent.height;

    for (swapchain.images) |swap_image| {
        const framebuffer_create_info = vk.FramebufferCreateInfo{
            .flags = .{},
            .render_pass = render_pass,
            .attachment_count = 1,
            .p_attachments = @ptrCast([*]const vk.ImageView, &swap_image.image_view),
            .width = framebuffer_width,
            .height = framebuffer_height,
            .layers = 1, // number of layers in the image arrays
        };

        framebuffers[initialized_count] = try context.vkd.createFramebuffer(context.device, &framebuffer_create_info, null);
        initialized_count += 1;
    }

    return framebuffers;
}

pub fn commandPool(context: VkContext, flags: vk.CommandPoolCreateFlags, queue_family_index: u32) !vk.CommandPool {
    return try context.vkd.createCommandPool(context.device, &.{
        .flags = flags,
        .queue_family_index = queue_family_index,
    }, null);
}

pub fn commandBuffers(allocator: Allocator, context: VkContext, command_pool: vk.CommandPool, level: vk.CommandBufferLevel, count: usize) ![]vk.CommandBuffer {
    const command_buffers = try allocator.alloc(vk.CommandBuffer, count);
    errdefer allocator.free(command_buffers);

    const command_buffers_allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = level,
        .command_buffer_count = @intCast(u32, count),
    };
    try context.vkd.allocateCommandBuffers(context.device, &command_buffers_allocate_info, command_buffers.ptr);
    // destroyed on command pool destruction
    return command_buffers;
}
