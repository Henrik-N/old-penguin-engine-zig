const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");

const VkContext = @import("vk/VkContext.zig");
const Swapchain = @import("vk/Swapchain.zig");
const Vertex = @import("vk/Vertex.zig");

const vk_mem = @import("vk/vk_memory.zig");
const shader_resources = @import("resources");

const vk_init = @import("vk/vk_init.zig");
const vk_cmd = @import("vk/vk_cmd.zig");

// triangle
const mesh = [_]Vertex{
    .{ .pos = .{ 0, -0.5 }, .color = .{ 1, 0, 0 } },
    .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 1, 0 } },
    .{ .pos = .{ -0.5, 0.5 }, .color = .{ 0, 0, 1 } },
};

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

    const context = try VkContext.init(allocator, app_name, window);
    defer context.deinit();

    var swapchain = try Swapchain.init(allocator, context, window);
    defer swapchain.deinit(allocator, context);

    const render_pass = try vk_init.defaultRenderPass(context, swapchain.surface_format.format);
    defer vk_init.destroyRenderPass(context, render_pass);

    const pipeline_layout = try context.vkd.createPipelineLayout(context.device, &.{
        .flags = .{},
        .set_layout_count = 0,
        .p_set_layouts = undefined,
        .push_constant_range_count = 0,
        .p_push_constant_ranges = undefined,
    }, null);
    defer context.vkd.destroyPipelineLayout(context.device, pipeline_layout, null);

    const vert = try vk_init.shaderModule(context, shader_resources.tri_vert);
    defer vk_init.destroyShaderModule(context, vert);

    const frag = try vk_init.shaderModule(context, shader_resources.tri_frag);
    defer vk_init.destroyShaderModule(context, frag);

    const pipeline = try vk_init.pipeline(context, .{
        .shader_modules = .{
            .vertex = vert,
            .fragment = frag,
        },
        .vertex_input = .{
            .input_bindings = &Vertex.binding_descriptions,
            .input_attributes = &Vertex.attribute_descriptions,
        },
        .topology = .triangle_list,
        .polygon_mode = .fill,
        .color_blending = .alpha_blending,
    }, pipeline_layout, render_pass);
    defer vk_init.destroyPipeline(context, pipeline);

    var framebuffers = try vk_init.framebuffers(allocator, context, render_pass, swapchain);
    defer vk_init.destroyFramebuffers(allocator, context, framebuffers);

    const vertex_buffer = try vk_mem.createBuffer(context, @sizeOf(Vertex) * mesh.len, .{ .vertex_buffer_bit = true, .transfer_dst_bit = true });
    const vertex_memory = try vk_mem.allocateBufferMemory(context, vertex_buffer, .gpu_only);
    defer vk_mem.destroyBuffer(context, vertex_buffer);
    defer vk_mem.freeMemory(context, vertex_memory);

    try vk_mem.immediateUpload(context, vertex_buffer, Vertex, &mesh);

    const command_pool = try vk_init.commandPool(context, .{}, context.graphics_queue.family);
    defer vk_init.destroyCommandPool(context, command_pool);

    while (!window.shouldClose()) {
        const command_buffer = try swapchain.newRenderCommandsBuffer(context);

        try recordCommands(context, command_buffer, .{
            .render_pass = render_pass,
            .framebuffer = framebuffers[swapchain.current_image_index],
            .pipeline = pipeline,
            .vertex_buffer = vertex_buffer,
            .extent = swapchain.extent,
        });

        const present_state = swapchain.submitPresentCommandBuffer(context, command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => return err, // unknown error
        };

        if (present_state == .suboptimal) {
            // recreate swapchain
            try swapchain.recreate(allocator, context, window);
            vk_init.destroyFramebuffers(allocator, context, framebuffers);
            framebuffers = try vk_init.framebuffers(allocator, context, render_pass, swapchain);
        }

        try glfw.pollEvents();
    }

    try swapchain.waitForAllFences(context);
}

const RecordCommandsParams = struct {
    render_pass: vk.RenderPass,
    framebuffer: vk.Framebuffer,
    pipeline: vk.Pipeline,
    vertex_buffer: vk.Buffer,
    extent: vk.Extent2D,
};

fn recordCommands(context: VkContext, command_buffer: vk.CommandBuffer, params: RecordCommandsParams) !void {
    const viewport = vk_init.viewport(params.extent);
    const scissor = vk_init.scissor(params.extent);

    const cmd = try vk_cmd.CommandBufferRecorder.begin(context, command_buffer, .{ .one_time_submit_bit = true });

    cmd.setViewport(viewport);
    cmd.setScissor(scissor);

    cmd.beginRenderPass(.{
        .extent = params.extent,
        .clear_color = [_]f32{ 0, 0, 0, 1 },
        .render_pass = params.render_pass,
        .framebuffer = params.framebuffer,
    });

    cmd.bindPipeline(params.pipeline, .graphics);

    cmd.bindVertexBuffers(.{ .first_binding = 0, .vertex_buffers = &.{params.vertex_buffer}, .offsets = &.{0} });

    cmd.draw(.{
        .vertex_count = mesh.len,
        .instance_count = 1,
        .first_vertex = 0,
        .first_instance = 0,
    });

    cmd.endRenderPass();

    try cmd.end();
}
