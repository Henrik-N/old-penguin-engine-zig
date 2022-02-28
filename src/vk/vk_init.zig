const vk = @import("vulkan");
// const VkContext = @import("vk_context.zig").VkContext;
const VkContext = @import("VkContext.zig");

const Swapchain = @import("Swapchain.zig");

const Allocator = @import("std").mem.Allocator;
const vk_mem = @import("vk_memory.zig");

const vk_init = @This();

pub fn shaderModule(context: VkContext, comptime shader_source: []const u8) !vk.ShaderModule {
    const shader_module = try context.vkd.createShaderModule(context.device, &.{
        .flags = .{},
        .code_size = shader_source.len,
        .p_code = @ptrCast([*]const u32, shader_source),
    }, null);
    return shader_module;
}

pub fn destroyShaderModule(context: VkContext, shader_module: vk.ShaderModule) void {
    context.vkd.destroyShaderModule(context.device, shader_module, null);
}

pub const SubpassDescriptionParams = struct {
    flags: vk.SubpassDescriptionFlags,
    pipeline_bind_point: vk.PipelineBindPoint,
    input_attachment_refs: []const vk.AttachmentReference,
    color_attachment_refs: []const vk.AttachmentReference,
    depth_attachment_ref: ?*const vk.AttachmentReference,
    resolve_attachment_refs: []const vk.AttachmentReference, // optional
    preserve_attachments: []const u32,
};

pub fn subpassDescription(params: SubpassDescriptionParams) vk.SubpassDescription {
    return vk.SubpassDescription{
        .flags = params.flags,
        .pipeline_bind_point = params.pipeline_bind_point,
        .input_attachment_count = @intCast(u32, params.input_attachment_refs.len),
        .p_input_attachments = @ptrCast([*]const vk.AttachmentReference, params.input_attachment_refs.ptr),
        .color_attachment_count = @intCast(u32, params.color_attachment_refs.len),
        .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, params.color_attachment_refs.ptr),
        .p_resolve_attachments = @ptrCast([*]const vk.AttachmentReference, params.resolve_attachment_refs.ptr),
        .p_depth_stencil_attachment = params.depth_attachment_ref,
        .preserve_attachment_count = @intCast(u32, params.preserve_attachments.len),
        .p_preserve_attachments = @ptrCast([*]const u32, params.preserve_attachments.ptr),
    };
}

pub const InitRenderPassParams = struct {
    p_next: ?*anyopaque = null,
    flags: vk.RenderPassCreateFlags,
    attachments: []const vk.AttachmentDescription,
    subpasses: []const vk.SubpassDescription,
    subpass_dependencies: []const vk.SubpassDependency,
};

pub fn renderPass(context: VkContext, params: InitRenderPassParams) !vk.RenderPass {
    return try context.vkd.createRenderPass(context.device, &.{
        .p_next = params.p_next,
        .flags = params.flags,
        .attachment_count = @intCast(u32, params.attachments.len),
        .p_attachments = @ptrCast([*]const vk.AttachmentDescription, params.attachments.ptr),
        .subpass_count = @intCast(u32, params.subpasses.len),
        .p_subpasses = @ptrCast([*]const vk.SubpassDescription, params.subpasses.ptr),
        .dependency_count = @intCast(u32, params.subpass_dependencies.len),
        .p_dependencies = @ptrCast([*]const vk.SubpassDependency, params.subpass_dependencies.ptr),
    }, null);
}

pub fn destroyRenderPass(context: VkContext, render_pass: vk.RenderPass) void {
    context.vkd.destroyRenderPass(context.device, render_pass, null);
}

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

    const depth_attachment_ref = vk.AttachmentReference{
        .attachment = 1,
        .layout = .depth_stencil_attachment_optimal,
    };

    return try vk_init.renderPass(context, .{
        .flags = .{},
        .attachments = &attachments,
        .subpasses = &.{vk_init.subpassDescription(.{
            .flags = .{},
            .pipeline_bind_point = .graphics,
            .input_attachment_refs = &.{},
            .color_attachment_refs = &.{.{
                .attachment = 0,
                .layout = .color_attachment_optimal,
            }},
            .depth_attachment_ref = &depth_attachment_ref,
            .resolve_attachment_refs = &.{},
            .preserve_attachments = &.{},
        })},
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

pub const InitPipelineLayoutParams = struct {
    flags: vk.PipelineLayoutCreateFlags,
    set_layouts: []const vk.DescriptorSetLayout,
    push_constant_ranges: []const vk.PushConstantRange,
};

pub fn pipelineLayout(context: VkContext, params: InitPipelineLayoutParams) !vk.PipelineLayout {
    const create_info = vk.PipelineLayoutCreateInfo{
        .flags = params.flags,
        .set_layout_count = @intCast(u32, params.set_layouts.len),
        .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, params.set_layouts.ptr),
        .push_constant_range_count = @intCast(u32, params.push_constant_ranges.len),
        .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, params.push_constant_ranges.ptr),
    };
    return try context.vkd.createPipelineLayout(context.device, &create_info, null);
}

pub fn destroyPipelineLayout(context: VkContext, pipeline_layout: vk.PipelineLayout) void {
    context.vkd.destroyPipelineLayout(context.device, pipeline_layout, null);
}

pub const InitFramebufferParams = struct {
    flags: vk.FramebufferCreateFlags,
    render_pass: vk.RenderPass,
    attachments: []const vk.ImageView,
    extent: vk.Extent2D,
    layer_count: u32, // number of layers in the image arrays
};

pub fn framebuffer(context: VkContext, params: InitFramebufferParams) !vk.Framebuffer {
    return try context.vkd.createFramebuffer(context.device, &.{
        .flags = .{},
        .render_pass = params.render_pass,
        .attachment_count = @intCast(u32, params.attachments.len),
        .p_attachments = @ptrCast([*]const vk.ImageView, params.attachments.ptr),
        .width = params.extent.width,
        .height = params.extent.height,
        .layers = params.layer_count,
    }, null);
}

pub fn framebuffers(allocator: Allocator, context: VkContext, render_pass: vk.RenderPass, swapchain: Swapchain) ![]vk.Framebuffer {
    const framebuffers_ = try allocator.alloc(vk.Framebuffer, swapchain.images.len);
    errdefer allocator.free(framebuffers_);

    var initialized_count: usize = 0;
    errdefer for (framebuffers_[0..initialized_count]) |framebuffer_| context.vkd.destroyFramebuffer(context.device, framebuffer_, null);

    for (swapchain.images) |swap_image| {
        framebuffers_[initialized_count] = try vk_init.framebuffer(context, .{
            .flags = .{},
            .render_pass = render_pass,
            .attachments = &.{
                swap_image.image_view,
                swapchain.depth_image.image_view,
            },
            .extent = swapchain.extent,
            .layer_count = 1,
        });

        initialized_count += 1;
    }

    return framebuffers_;
}

pub fn destroyFramebuffers(allocator: Allocator, context: VkContext, framebuffers_: []const vk.Framebuffer) void {
    for (framebuffers_) |framebuffer_| context.vkd.destroyFramebuffer(context.device, framebuffer_, null);
    allocator.free(framebuffers_);
}

pub fn commandPool(context: VkContext, flags: vk.CommandPoolCreateFlags, queue_family_index: u32) !vk.CommandPool {
    return try context.vkd.createCommandPool(context.device, &.{
        .flags = flags,
        .queue_family_index = queue_family_index,
    }, null);
}

pub fn destroyCommandPool(context: VkContext, command_pool: vk.CommandPool) void {
    context.vkd.destroyCommandPool(context.device, command_pool, null);
}

pub fn commandBuffer(context: VkContext, command_pool: vk.CommandPool, level: vk.CommandBufferLevel) !vk.CommandBuffer {
    const command_buffers_allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = level,
        .command_buffer_count = 1,
    };
    var command_buffer: vk.CommandBuffer = undefined;
    try context.vkd.allocateCommandBuffers(context.device, &command_buffers_allocate_info, @ptrCast([*]vk.CommandBuffer, &command_buffer));

    return command_buffer;
}

pub fn freeCommandBuffer(context: VkContext, command_pool: vk.CommandPool, command_buffer: vk.CommandBuffer) void {
    context.vkd.freeCommandBuffers(context.device, command_pool, 1, @ptrCast([*]const vk.CommandBuffer, &command_buffer));
}

pub fn commandBuffers(allocator: Allocator, context: VkContext, command_pool: vk.CommandPool, level: vk.CommandBufferLevel, count: usize) ![]vk.CommandBuffer {
    const command_buffers_allocate_info = vk.CommandBufferAllocateInfo{
        .command_pool = command_pool,
        .level = level,
        .command_buffer_count = @intCast(u32, count),
    };

    const command_buffers = try allocator.alloc(vk.CommandBuffer, count);
    errdefer allocator.free(command_buffers);

    try context.vkd.allocateCommandBuffers(context.device, &command_buffers_allocate_info, command_buffers.ptr);

    // destroyed on command pool destruction
    return command_buffers;
}

pub fn fence(context: VkContext, flags: vk.FenceCreateFlags) !vk.Fence {
    return try context.vkd.createFence(context.device, &.{
        .flags = flags,
    }, null);
}

pub fn destroyFence(context: VkContext, fence_: vk.Fence) void {
    context.vkd.destroyFence(context.device, fence_, null);
}

pub fn semaphore(context: VkContext) !vk.Semaphore {
    return try context.vkd.createSemaphore(context.device, &.{ .flags = .{} }, null);
}

pub fn destroySemaphore(context: VkContext, semaphore_: vk.Semaphore) void {
    context.vkd.destroySemaphore(context.device, semaphore_, null);
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

    var pipeline_: vk.Pipeline = undefined;
    _ = try context.vkd.createGraphicsPipelines(context.device, pipeline_cache, 1, @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &pipeline_create_info), null, @ptrCast([*]vk.Pipeline, &pipeline_));

    return pipeline_;
}

pub fn destroyPipeline(context: VkContext, pipeline_: vk.Pipeline) void {
    context.vkd.destroyPipeline(context.device, pipeline_, null);
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

pub fn imageView(context: VkContext, image: vk.Image, format: vk.Format, aspect_mask: vk.ImageAspectFlags) !vk.ImageView {
    const create_info = vk.ImageViewCreateInfo{
        .flags = .{},
        .image = image,
        .view_type = .@"2d",
        .format = format,
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = .{
            .aspect_mask = aspect_mask,
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    };
    return try context.vkd.createImageView(context.device, &create_info, null);
}

pub fn destroyImageView(context: VkContext, image_view: vk.ImageView) void {
    context.vkd.destroyImageView(context.device, image_view, null);
}

// pub fn image(context: VkContext, format: vk.Format, usage: vk.ImageUsageFlags, extent: vk.Extent3D) !vk.Image {
//     context.vkd.createImage(device: Device, p_create_info: *const ImageCreateInfo, p_allocator: ?*const AllocationCallbacks)
//     context.vkd.createImage(context.device, &.{
//         .flags = .{},
//         .image_type = .@"2d",
//         .format = format,
//         .extent = extent,
//         .mip_levels = 1,
//         .array_layers = 1,
//         .samples = @"1_bit",
//         .tiling = .{ .tiling_optimal_bit = true }, // TODO check that the physical device supports optimal tiling
//         .usage = usage,
//         .sharing_mode = .exclusive,
//         .
//
//         s_type: StructureType = .image_create_info,
//         p_next: ?*const anyopaque = null,
//         flags: ImageCreateFlags,
//         image_type: ImageType,
//         format: Format,
//         extent: Extent3D,
//         mip_levels: u32,
//         array_layers: u32,
//         samples: SampleCountFlags,
//         tiling: ImageTiling,
//         usage: ImageUsageFlags,
//         sharing_mode: SharingMode,
//         queue_family_index_count: u32,
//         p_queue_family_indices: [*]const u32,
//         initial_layout: ImageLayout,
//     }, null);
// }
