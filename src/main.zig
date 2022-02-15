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

    _ = vert_shader_module;
    _ = frag_shader_module;

    const shader_stages = [_]vk.PipelineShaderStageCreateInfo{
        vk_init.pipeline.shaderStageCreateInfo(.{ .vertex_bit = true }, vert_shader_module),
        vk_init.pipeline.shaderStageCreateInfo(.{ .fragment_bit = true }, frag_shader_module),
    };

    const vertex_input_state = vk_init.pipeline.vertexInputStateCreateInfo();
    const input_assembly_state = vk_init.pipeline.inputAssemblyStateCreateInfo(vk.PrimitiveTopology.triangle_list);
    const viewport_state = vk_init.pipeline.viewportStateCreateInfo();
    const rasterization_state = vk_init.pipeline.rasterizationStateCreateInfo(vk.PolygonMode.fill); // .line, .point
    const multisample_state = vk_init.pipeline.multisampleStateCreateInfo();
    const depth_stencil_state = null; // TODO depth/stencil state
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

    _ = shader_stages;
    _ = vertex_input_state;
    _ = input_assembly_state;
    _ = viewport_state;
    _ = rasterization_state;
    _ = multisample_state;
    _ = depth_stencil_state;
    _ = color_blend_state;
    _ = dynamic_state;
    _ = pipeline_layout;

    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}
