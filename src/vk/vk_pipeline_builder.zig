const vk = @import("vulkan");
const vk_init = @import("vk_init.zig");
const VkContext = @import("vk_context.zig").VkContext;

pub const PipelineBuilderConfig = struct {
    shader_stage_count: usize,
    color_blend_attachment_state_count: usize,
};

pub fn PipelineBuilder(comptime config: PipelineBuilderConfig) type {
    return struct {
        shader_stages: [config.shader_stage_count]vk.PipelineShaderStageCreateInfo,
        vertex_input_state: vk.PipelineVertexInputStateCreateInfo,
        input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo,
        tesselation_state: ?vk.PipelineTessellationStateCreateInfo,
        viewport: vk.Viewport,
        scissor: vk.Rect2D,
        // viewport state (created from the viewport and scissor)
        rasterization_state: vk.PipelineRasterizationStateCreateInfo,
        multisample_state: vk.PipelineMultisampleStateCreateInfo,
        depth_stencil_state: ?vk.PipelineDepthStencilStateCreateInfo,
        dynamic_state: ?vk.PipelineDynamicStateCreateInfo,
        color_blend_attachment_states: [config.color_blend_attachment_state_count]vk.PipelineColorBlendAttachmentState,
        // color blend state (created from the color_blend_attachment_states)
        pipeline_layout: vk.PipelineLayout,
        render_pass: vk.RenderPass,

        pub fn init_pipeline(self: PipelineBuilder(config), context: VkContext) !vk.Pipeline {
            const viewport_state = vk_init.pipeline.viewportStateCreateInfo(self.viewport, self.scissor);
            const color_blend_state = vk_init.pipeline.colorBlendStateCreateInfo(self.color_blend_attachment_states[0..]);

            const pipeline_create_info = vk.GraphicsPipelineCreateInfo{
                .flags = .{},
                .stage_count = @intCast(u32, self.shader_stages.len),
                .p_stages = @ptrCast([*]const vk.PipelineShaderStageCreateInfo, &self.shader_stages),
                .p_vertex_input_state = &self.vertex_input_state,
                .p_input_assembly_state = &self.input_assembly_state,
                .p_tessellation_state = if (self.tesselation_state) |tessellation_state| &tessellation_state else null,
                .p_viewport_state = &viewport_state,
                .p_rasterization_state = &self.rasterization_state,
                .p_multisample_state = &self.multisample_state,
                .p_depth_stencil_state = if (self.depth_stencil_state) |depth_stencil_state| &depth_stencil_state else null,
                .p_color_blend_state = &color_blend_state,
                .p_dynamic_state = if (self.dynamic_state) |dynamic_state| &dynamic_state else null,
                //null, //@ptrCast(?[*]const vk.PipelineDynamicStateCreateInfo, &self.dynamic_state),
                .layout = self.pipeline_layout,
                // NOTE It is possible to use other render passes with this pipeline instance than the one set here,
                // provided they are a compatible renderpass.
                // More info here: https://www.khronos.org/registry/vulkan/specs/1.3-extensions/html/chap8.html#renderpass-compatibility
                .render_pass = self.render_pass,
                .subpass = 0, // the index of the subpass in the render pass where this pipeline will be used
                //
                .base_pipeline_handle = .null_handle,
                .base_pipeline_index = -1,
            };

            const pipeline_cache: vk.PipelineCache = .null_handle;
            var pipeline: vk.Pipeline = undefined;
            _ = try context.vkd.createGraphicsPipelines(context.device, pipeline_cache, 1, @ptrCast([*]const vk.GraphicsPipelineCreateInfo, &pipeline_create_info), null, @ptrCast([*]vk.Pipeline, &pipeline));

            return pipeline;
        }
    };
}
