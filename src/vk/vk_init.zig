const vk = @import("vulkan");
const zk = @import("zulkan.zig");
const VkContext = @import("VkContext.zig");

const Swapchain = @import("Swapchain.zig");

const Allocator = @import("std").mem.Allocator;
const vk_mem = @import("vk_memory.zig");

const vk_init = @This();

pub const SimpleImageCreateInfo = struct {
    extent: vk.Extent3D,
    format: vk.Format,
    tiling: vk.ImageTiling,
    usage: vk.ImageUsageFlags,

    pub fn raw(self: SimpleImageCreateInfo) vk.ImageCreateInfo {
        return vk.ImageCreateInfo{
            .flags = .{},
            .image_type = .@"2d",
            .format = self.format,
            .extent = self.extent,
            .mip_levels = 1,
            .array_layers = 1,
            .samples = .{ .@"1_bit" = true },
            .tiling = self.tiling,
            .usage = self.usage,
            .sharing_mode = .exclusive,
            // these are for if sharing_mode is concurrent
            .queue_family_index_count = 0,
            .p_queue_family_indices = undefined,
            .initial_layout = .@"undefined",
        };
    }
};

pub const SimpleImageViewCreateInfo = struct {
    image: vk.Image,
    format: vk.Format,
    aspect_mask: vk.ImageAspectFlags,

    pub fn raw(self: SimpleImageViewCreateInfo) vk.ImageViewCreateInfo {
        return .{
            .flags = .{},
            .image = self.image,
            .view_type = .@"2d",
            .format = self.format,
            .components = .{
                .r = .identity,
                .g = .identity,
                .b = .identity,
                .a = .identity,
            },
            .subresource_range = .{
                .aspect_mask = self.aspect_mask,
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };
    }
};

pub fn defaultRenderPass(context: VkContext, surface_format: vk.Format, depth_format: vk.Format) !vk.RenderPass {
    const attachments = [_]vk.AttachmentDescription{
        // color attachment
        .{
            .flags = .{},
            .format = surface_format,
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
        // depth attachment
        .{
            .flags = .{},
            .format = depth_format,
            .samples = .{ .@"1_bit" = true },
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
            .stencil_store_op = .dont_care,
            .initial_layout = .@"undefined",
            .final_layout = .depth_stencil_attachment_optimal,
        },
    };

    return try context.createRenderPass(.{
        .flags = .{},
        .attachments = &attachments,
        .subpasses = &.{
            (zk.SubpassDescription{
                .flags = .{},
                .pipeline_bind_point = .graphics,
                .input_attachment_refs = &.{},
                .color_attachment_refs = &.{.{
                    .attachment = 0,
                    .layout = .color_attachment_optimal,
                }},
                .depth_attachment_ref = &.{
                    .attachment = 1,
                    .layout = .depth_stencil_attachment_optimal,
                },
                //depth_attachment_ref,
                .resolve_attachment_refs = &.{},
                .preserve_attachments = &.{},
            }).raw(),
        },
        .subpass_dependencies = &.{
            .{ // color depedency subpass 0
                .src_subpass = vk.SUBPASS_EXTERNAL, // the implicit subpass before or after the subpass (depending on if it's in src or dst)
                .dst_subpass = 0,
                //
                .src_stage_mask = .{ .color_attachment_output_bit = true },
                .src_access_mask = .{},
                //
                .dst_stage_mask = .{ .color_attachment_output_bit = true },
                .dst_access_mask = .{ .color_attachment_write_bit = true },
                //
                .dependency_flags = .{},
            },
            .{ // depth depedency subpass 0
                .src_subpass = vk.SUBPASS_EXTERNAL,
                .dst_subpass = 0,
                //
                .src_stage_mask = .{ .early_fragment_tests_bit = true }, // .late_fragment_tests_bit = true },
                .src_access_mask = .{},
                //
                .dst_stage_mask = .{ .early_fragment_tests_bit = true },
                .dst_access_mask = .{ .depth_stencil_attachment_write_bit = true },
                //
                .dependency_flags = .{},
            },
        },
    });
}

pub const ColorBlendingConfig = enum {
    no_blending,
    alpha_blending,
};

pub const PipelineConfig = struct {
    shader_modules: struct {
        vertex: vk.ShaderModule,
        fragment: vk.ShaderModule,
    },
    vertex_input: struct {
        input_bindings: []const vk.VertexInputBindingDescription,
        input_attributes: []const vk.VertexInputAttributeDescription,
    },
    topology: vk.PrimitiveTopology,
    polygon_mode: vk.PolygonMode,
    color_blending: ColorBlendingConfig,
};

pub fn pipeline(context: VkContext, config: PipelineConfig, pipeline_layout: vk.PipelineLayout, render_pass: vk.RenderPass) !vk.Pipeline {
    const create_info = @import("vk_pipeline_stages.zig");

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        create_info.shaderStage(.{ .vertex_bit = true }, config.shader_modules.vertex),
        create_info.shaderStage(.{ .fragment_bit = true }, config.shader_modules.fragment),
    };

    const vertex_input = create_info.vertexInputState(config.vertex_input.input_bindings, config.vertex_input.input_attributes);

    const input_assembly = create_info.inputAssemblyState(config.topology);

    // const tessellation =

    const viewport_ = create_info.viewportStateDynamic();

    const rasterization = create_info.rasterizationState(config.polygon_mode);

    const multisampling = create_info.multisampleState();

    const depth_stencil = create_info.depthStencilState(.{
        .depth_test_enable = true,
        .depth_write_enable = true,
        .compare_op = .less_or_equal,
    });

    const color_blend_attachments = [_]vk.PipelineColorBlendAttachmentState{create_info.colorBlendAttachmentState(config.color_blending)};
    const color_blend = create_info.colorBlendState(&color_blend_attachments);

    // binding the viewport & scissor dynamically for now - this way there's no need to recreate the pipeline
    // when the screen resolution changes
    const dynamic_states = [_]vk.DynamicState{ .viewport, .scissor };
    const dynamic_state = create_info.dynamicState(&dynamic_states);

    const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
        .flags = .{},
        .stage_count = @intCast(u32, shader_stages.len),
        .p_stages = @ptrCast([*]const vk.PipelineShaderStageCreateInfo, &shader_stages),
        .p_vertex_input_state = &vertex_input,
        .p_input_assembly_state = &input_assembly,
        .p_tessellation_state = null,
        .p_viewport_state = &viewport_,
        .p_rasterization_state = &rasterization,
        .p_multisample_state = &multisampling,
        //.p_depth_stencil_state = null,
        .p_depth_stencil_state = &depth_stencil,
        .p_color_blend_state = &color_blend,
        .p_dynamic_state = &dynamic_state,
        //
        .layout = pipeline_layout,
        .render_pass = render_pass,
        .subpass = 0,
        .base_pipeline_handle = .null_handle,
        .base_pipeline_index = -1,
    };

    const pipeline_cache = vk.PipelineCache.null_handle;

    return try context.createGraphicsPipeline(pipeline_create_info, pipeline_cache);
}

pub fn viewport(extent: vk.Extent2D) vk.Viewport {
    return .{
        .x = 0,
        .y = 0,
        .width = @intToFloat(f32, extent.width),
        .height = @intToFloat(f32, extent.height),
        .min_depth = 0,
        .max_depth = 1,
    };
}

pub fn scissor(extent: vk.Extent2D) vk.Rect2D {
    return .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };
}
