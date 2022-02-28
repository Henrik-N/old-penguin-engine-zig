///! default structures and convenience functions for creating a pipeline
const vk = @import("vulkan");
const vk_init = @import("vk_init.zig");
//const VkContext = @import("vk_context.zig").VkContext;
const VkContext = @import("VkContext.zig");

/// Information about a single shader stage in a pipeline.
pub fn shaderStage(stage_flags: vk.ShaderStageFlags, shader_module: vk.ShaderModule) vk.PipelineShaderStageCreateInfo {
    return .{
        .flags = .{},
        .stage = stage_flags,
        .module = shader_module,
        .p_name = "main",
        .p_specialization_info = null,
    };
}

/// Configuration for the vertex shader input format.
pub fn vertexInputState(vertex_input_bindings: []const vk.VertexInputBindingDescription, vertex_attributes: []const vk.VertexInputAttributeDescription) vk.PipelineVertexInputStateCreateInfo {
    return .{
        .flags = .{},
        .vertex_binding_description_count = @intCast(u32, vertex_input_bindings.len),
        .p_vertex_binding_descriptions = @ptrCast([*]const vk.VertexInputBindingDescription, vertex_input_bindings.ptr),
        .vertex_attribute_description_count = @intCast(u32, vertex_attributes.len),
        .p_vertex_attribute_descriptions = @ptrCast([*]const vk.VertexInputAttributeDescription, vertex_attributes.ptr),
    };
}

/// Configuration for how the vertex input will be read, 
/// i.e. what geometry will be drawn from the vertex input.
pub fn inputAssemblyState(topology: vk.PrimitiveTopology) vk.PipelineInputAssemblyStateCreateInfo {
    return .{
        .flags = .{},
        .topology = topology,
        // Primitive restart == load vertices from the vertex buffer in a custom order.
        .primitive_restart_enable = vk.FALSE,
    };
}

/// Details about the regions of the framebuffer we'll render to. 
/// Penguin Engine will only use one viewport that covers the entire screen, at least for now.
pub fn viewportState(in_viewport: vk.Viewport, in_scissor: vk.Rect2D) vk.PipelineViewportStateCreateInfo {
    return .{ .flags = .{}, .viewport_count = 1, .p_viewports = @ptrCast([*]const vk.Viewport, &in_viewport), .scissor_count = 1, .p_scissors = @ptrCast([*]const vk.Rect2D, &in_scissor) };
}

/// Create info for the viewport state where the viewport and scissor is undefined on creation, when they are dynamically bound,
///    as they'll be bound anyway
pub fn viewportStateDynamic() vk.PipelineViewportStateCreateInfo {
    return .{
        .flags = .{},
        .viewport_count = 1,
        .p_viewports = undefined,
        .scissor_count = 1,
        .p_scissors = undefined,
    };
}

/// Configuration regarding how to turn the geometry into fragments (basically pixels) for the fragment shader.
pub fn rasterizationState(polygon_mode: vk.PolygonMode) vk.PipelineRasterizationStateCreateInfo {
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
pub fn multisampleState() vk.PipelineMultisampleStateCreateInfo {
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

pub const DepthStencilStateParams = struct {
    depth_test_enable: bool,
    depth_write_enable: bool,
    compare_op: ?vk.CompareOp, // necessary if enable_depth_test == true
};

pub fn depthStencilState(params: DepthStencilStateParams) vk.PipelineDepthStencilStateCreateInfo {
    // this isn't used at all, just need something to put in the create struct below
    const ignored_stencil_state = vk.StencilOpState{
        .fail_op = .zero,
        .pass_op = .zero,
        .depth_fail_op = .zero,
        .compare_op = .never,
        .compare_mask = 0,
        .write_mask = 0,
        .reference = 0,
    };

    return .{
        .flags = .{},
        .depth_test_enable = if (params.depth_test_enable) vk.TRUE else vk.FALSE,
        .depth_write_enable = if (params.depth_write_enable) vk.TRUE else vk.FALSE,
        .depth_compare_op = if (params.depth_test_enable) params.compare_op.? else vk.CompareOp.always,
        //
        .depth_bounds_test_enable = vk.FALSE,
        .stencil_test_enable = vk.FALSE,
        .front = ignored_stencil_state, // optional
        .back = ignored_stencil_state, // // optional
        .min_depth_bounds = 0, // optional
        .max_depth_bounds = 1, // optional
    };
}

/// Framebuffer-specific configuration for how to blend the color returned from a fragment shader with the color already present in the framebuffer.
/// Either mix the colors or completely replace the one that is already there.
pub fn colorBlendAttachmentState(blending: vk_init.ColorBlendingConfig) vk.PipelineColorBlendAttachmentState {
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
pub fn colorBlendState(color_blend_attachments: []const vk.PipelineColorBlendAttachmentState) vk.PipelineColorBlendStateCreateInfo {
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
pub fn dynamicState(dynamic_states: []const vk.DynamicState) vk.PipelineDynamicStateCreateInfo {
    return .{
        .flags = .{},
        .dynamic_state_count = @intCast(u32, dynamic_states.len),
        .p_dynamic_states = @ptrCast([*]const vk.DynamicState, dynamic_states),
    };
}
