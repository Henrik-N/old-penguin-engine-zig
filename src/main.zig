const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");
const mem = @import("std").mem;

const VkContext = @import("vk/VkContext.zig");
const Swapchain = @import("vk/Swapchain.zig");

const vk_mem = @import("vk/vk_memory.zig");
const vk_init = @import("vk/vk_init.zig");
const vk_cmd = @import("vk/vk_cmd.zig");
const vk_desc_sets = @import("vk/vk_descriptor_sets.zig");

const input = @import("input.zig");
const DescriptorResource = vk_desc_sets.DescriptorResource;

const m = @import("math.zig");

const resources = @import("vk/resources/resources.zig");
const view_resources = resources.view_resources;
const shader_resources = resources.shader_resources;

const Vertex = view_resources.Vertex;
const VertexIndex = view_resources.VertexIndex;

const MeshView = struct {
    vertices: []const Vertex, // TODO slice of memory from bigger buffer
    indices: []const VertexIndex, // TODO slice of memory from bigger buffer

    pub fn new(vertices: []const Vertex, indices: []const VertexIndex) MeshView {
        return MeshView{ .vertices = vertices, .indices = indices };
    }
};

// triangle
const mesh = struct {
    const vertices = [_]Vertex{
        .{ .pos = .{ -0.5, -0.5 }, .color = .{ 1, 0, 0 } },
        .{ .pos = .{ 0.5, -0.5 }, .color = .{ 0, 1, 0 } },
        .{ .pos = .{ 0.5, 0.5 }, .color = .{ 0, 0, 1 } },
        .{ .pos = .{ -0.5, 0.5 }, .color = .{ 1, 1, 1 } },
    };

    const indices = [_]VertexIndex{ 0, 1, 2, 2, 3, 0 };
};
const mesh_view = MeshView.new(&mesh.vertices, &mesh.indices);

pub fn main() !void {
    // WINDOW
    //
    try glfw.init(.{});
    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    const app_name = "Penguin Engine";

    const window = try glfw.Window.create(extent.width, extent.height, app_name, null, null, .{
        .client_api = .no_api, // don't create an OpenGL context
    });
    defer window.destroy();

    // INPUT
    //
    input.initInputState(&window);

    // HEAP MEMORY ALLOCATOR
    //
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // RENDERING BASE
    //
    const context = try VkContext.init(allocator, window, app_name);
    defer context.deinit();

    var swapchain = try Swapchain.init(allocator, context, window);
    defer swapchain.deinit(allocator, context);

    // RENDER PASS
    //
    const render_pass = try vk_init.defaultRenderPass(context, swapchain.surface_format.format, swapchain.depth_image.format);
    defer context.destroyRenderPass(render_pass);

    // DESCRIPTOR SETS RESOURCE - ALLOCATES DESCRIPTOR SETS AND DESCRIPTOR LAYOUTS
    //
    var descriptor_resource = try DescriptorResource.init(allocator, &context);
    defer descriptor_resource.deinit();

    // VIEW RESOURCES - BIND FREQUENCY: EVERY VIEW
    //
    const vertex_index_buffer = try view_resources.initVertexIndexBuffer(context, mesh_view.vertices[0..], mesh_view.indices[0..]);
    defer vertex_index_buffer.destroyFree(context);

    const uniform_buffer = try view_resources.initUniformBuffer(context, swapchain.images.len);
    defer uniform_buffer.destroyFree(context);

    const view_descriptor_sets = try allocator.alloc(vk.DescriptorSet, swapchain.images.len);
    const view_descriptor_set_layout = try view_resources.initDescriptorSets(context, uniform_buffer.buffer, &descriptor_resource, view_descriptor_sets);
    defer allocator.free(view_descriptor_sets);

    // SHADER RESOURCES - BIND FREQUENCY: EVERY SHADER
    //
    const shader_storage_buffer = try shader_resources.initShaderStorageBuffer(context, swapchain.images.len);
    defer shader_storage_buffer.destroyFree(context);

    const shader_descriptor_sets = try allocator.alloc(vk.DescriptorSet, swapchain.images.len);
    const shader_descriptor_set_layout = try shader_resources.initDescriptorSets(context, shader_storage_buffer.buffer, &descriptor_resource, shader_descriptor_sets);
    defer allocator.free(shader_descriptor_sets);

    // DESCRIPTOR SETS
    const pipeline_layout = try context.createPipelineLayout(.{
        .flags = .{},
        .set_layouts = &.{ view_descriptor_set_layout, shader_descriptor_set_layout },
        .push_constant_ranges = &.{},
    });
    defer context.destroyPipelineLayout(pipeline_layout);

    const vert = try context.createShaderModule(shader_resources.shader_source.tri_vert);
    defer context.destroyShaderModule(vert);

    const frag = try context.createShaderModule(shader_resources.shader_source.tri_frag);
    defer context.destroyShaderModule(frag);

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
    defer context.destroyPipeline(pipeline);

    var framebuffers = try context.allocateFramebufferHandles(swapchain);
    defer context.freeFramebufferHandles(framebuffers);
    try context.createFramebuffers(swapchain, render_pass, framebuffers);
    defer context.destroyFramebuffers(framebuffers);

    while (!window.shouldClose()) {
        const command_buffer = try swapchain.newRenderCommandsBuffer(context);

        try recordCommands(context, command_buffer, .{
            .render_pass = render_pass,
            .framebuffer = framebuffers[swapchain.current_image_index],
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,
            .extent = swapchain.extent,
            .descriptor_resource = &descriptor_resource,
            .current_image_index = swapchain.current_image_index,
            .view_binding = .{
                .vertex_index_buffer = vertex_index_buffer.buffer,
                .uniform_buffer = uniform_buffer,
                .descriptor_set = view_descriptor_sets[swapchain.current_image_index],
            },
            .shader_binding = .{
                .shader_storage_buffer = shader_storage_buffer,
                .descriptor_set = shader_descriptor_sets[swapchain.current_image_index],
            },
        });

        const present_state = swapchain.submitPresentCommandBuffer(context, command_buffer) catch |err| switch (err) {
            error.OutOfDateKHR => Swapchain.PresentState.suboptimal,
            else => return err, // unknown error
        };

        if (present_state == .suboptimal) {
            // recreate swapchain
            try swapchain.recreate(allocator, context, window);
            context.destroyFramebuffers(framebuffers);
            context.freeFramebufferHandles(framebuffers);
            framebuffers = try context.allocateFramebufferHandles(swapchain);
            try context.createFramebuffers(swapchain, render_pass, framebuffers);
        }

        try glfw.pollEvents();
    }

    try swapchain.waitForAllFences(context);
}

const RecordCommandsParams = struct {
    render_pass: vk.RenderPass,
    framebuffer: vk.Framebuffer,
    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,
    extent: vk.Extent2D,
    descriptor_resource: *DescriptorResource,
    current_image_index: usize,
    view_binding: struct {
        vertex_index_buffer: vk.Buffer,
        uniform_buffer: vk_mem.AllocatedBuffer,
        descriptor_set: vk.DescriptorSet,
    },
    shader_binding: struct {
        shader_storage_buffer: vk_mem.AllocatedBuffer,
        descriptor_set: vk.DescriptorSet,
    },
};

fn recordCommands(context: VkContext, command_buffer: vk.CommandBuffer, params: RecordCommandsParams) !void {
    const viewport = vk_init.viewport(params.extent);
    const scissor = vk_init.scissor(params.extent);

    const cmd = try context.beginRecordCommandBuffer(command_buffer, .{ .one_time_submit_bit = true });

    cmd.setViewport(viewport);
    cmd.setScissor(scissor);

    cmd.bindVertexBuffers(.{ .first_binding = 0, .vertex_buffers = &.{params.view_binding.vertex_index_buffer}, .offsets = &.{0} });
    const vertex_index_buffer_offset = @sizeOf(Vertex) * mesh.vertices.len;
    cmd.bindIndexBuffer(params.view_binding.vertex_index_buffer, vertex_index_buffer_offset, .uint32);

    cmd.bindPipeline(params.pipeline, .graphics);

    // view resources
    {
        const ub_data = view_resources.UniformBufferData{
            .model = m.Mat4.identity(),
            .view = m.Mat4.identity(),
            .projection = m.Mat4.identity(),
        };

        try view_resources.updateViewResources(context, .{
            .image_index = params.current_image_index,
            .uniform_buffer_memory = params.view_binding.uniform_buffer.memory,
            .data = &ub_data,
        });

        view_resources.bindViewResources(cmd, params.pipeline_layout, &.{params.view_binding.descriptor_set});
    }
    // shader resources
    {
        const ssbo_data = shader_resources.ShaderStorageBufferData{
            .some_data = m.Mat4.identity(),
        };

        try shader_resources.updateShaderResources(context, .{
            .image_index = params.current_image_index,
            .storage_buffer_memory = params.shader_binding.shader_storage_buffer.memory,
            .data = &ssbo_data,
        });

        shader_resources.bindShaderResources(cmd, params.pipeline_layout, &.{params.shader_binding.descriptor_set});
    }

    // render pass
    cmd.beginRenderPass(.{
        .extent = params.extent,
        .clear_values = &.{
            .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
            .{ .depth_stencil = .{ .depth = 1, .stencil = undefined } },
        },
        .render_pass = params.render_pass,
        .framebuffer = params.framebuffer,
    });

    cmd.drawIndexed(.{
        .index_count = mesh.indices.len,
        .instance_count = 1,
        .first_index = 0,
        .vertex_offset = 0,
        .first_instance = 0,
    });

    cmd.endRenderPass();

    try cmd.end();
}
