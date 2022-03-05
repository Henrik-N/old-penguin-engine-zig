const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");
const mem = @import("std").mem;

const shader_resources = @import("resources");

const VkContext = @import("vk/VkContext.zig");
const Swapchain = @import("vk/Swapchain.zig");
const Vertex = @import("vk/Vertex.zig");

const vk_mem = @import("vk/vk_memory.zig");
const vk_init = @import("vk/vk_init.zig");
const vk_cmd = @import("vk/vk_cmd.zig");
const vk_desc_sets = @import("vk/vk_descriptor_sets.zig");

const input = @import("input.zig");

const DescriptorLayoutCache = vk_desc_sets.DescriptorLayoutCache;
const DescriptorAllocator = vk_desc_sets.DescriptorAllocator;
const DescriptorBuilder = vk_desc_sets.DescriptorBuilder;

const m = @import("math.zig");

const MeshView = struct {
    vertices: []const Vertex, // TODO slice of memory from bigger buffer
    indices: []const u32, // TODO slice of memory from bigger buffer

    pub fn new(vertices: []const Vertex, indices: []const u32) MeshView {
        return MeshView{ .vertices = vertices, .indices = indices };
    }

    pub fn verticesSize(self: MeshView) usize {
        return @sizeOf(Vertex) * self.vertices.len;
    }

    pub fn indicesSize(self: MeshView) usize {
        return @sizeOf(u32) * self.indices.len;
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

    const indices = [_]u32{ 0, 1, 2, 2, 3, 0 };
};
const mesh_view = MeshView.new(&mesh.vertices, &mesh.indices);

const UniformBufferData = packed struct {
    model: m.Mat4,
    view: m.Mat4,
    projection: m.Mat4,

    const Self = @This();

    fn descriptorSetLayoutBinding(binding: u32) vk.DescriptorSetLayoutBinding {
        return .{
            .binding = binding,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .vertex_bit = true },
            .p_immutable_samplers = null, // only relevant for image sampling related descriptors
        };
    }

    fn descriptorbufferInfo(buffer: vk.Buffer) vk.DescriptorBufferInfo {
        return .{
            .buffer = buffer,
            .offset = 0,
            .range = @sizeOf(UniformBufferData),
        };
    }
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
    input.initInputState(&window);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const context = try VkContext.init(allocator, window, app_name);
    defer context.deinit();

    var swapchain = try Swapchain.init(allocator, context, window);
    defer swapchain.deinit(allocator, context);

    const render_pass = try vk_init.defaultRenderPass(context, swapchain.surface_format.format, swapchain.depth_image.format);
    defer context.destroyRenderPass(render_pass);

    var desc_layout_cache = try DescriptorLayoutCache.init(allocator, &context);
    defer desc_layout_cache.deinit();

    const descriptor_set_layout = try desc_layout_cache.createDescriptorSetLayout(.{
        .flags = .{},
        .bindings = &.{
            UniformBufferData.descriptorSetLayoutBinding(0),
        },
    });

    var desc_allocator = try DescriptorAllocator.init(allocator, &context);
    defer desc_allocator.deinit();

    var descriptor_builder = try DescriptorBuilder.init(allocator, &desc_layout_cache, &desc_allocator);
    defer descriptor_builder.deinit();

    const pipeline_layout = try context.createPipelineLayout(.{
        .flags = .{},
        .set_layouts = &.{descriptor_set_layout},
        .push_constant_ranges = &.{},
    });
    defer context.destroyPipelineLayout(pipeline_layout);

    const vert = try context.createShaderModule(shader_resources.tri_vert);
    defer context.destroyShaderModule(vert);

    const frag = try context.createShaderModule(shader_resources.tri_frag);
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

    // begin buffers
    const vertex_index_buffer_size = mesh_view.verticesSize() + mesh_view.indicesSize();

    const vertex_index_buffer = try context.createBufferGraphicsQueue(vertex_index_buffer_size, .{
        .vertex_buffer_bit = true,
        .index_buffer_bit = true,
        .transfer_dst_bit = true,
    });
    defer context.destroyBuffer(vertex_index_buffer);
    const vertex_index_buffer_memory = try context.allocateBufferMemory(vertex_index_buffer, .gpu_only);
    defer context.freeMemory(vertex_index_buffer_memory);

    try vk_mem.immediateUpload(context, Vertex, .{
        .buffer = vertex_index_buffer,
        .offset = 0,
        .upload_data = mesh_view.vertices,
    });
    try vk_mem.immediateUpload(context, u32, .{
        .buffer = vertex_index_buffer,
        .offset = mesh_view.verticesSize(),
        .upload_data = mesh_view.indices,
    });

    const uniform_buffers = try context.allocateUniformBuffers(UniformBufferData, swapchain.images.len);
    defer context.freeUniformBuffers(uniform_buffers);
    // end buffers

    // command pool
    const command_pool = try context.createCommandPool(.{}, context.graphics_queue.family);
    defer context.destroyCommandPool(command_pool);

    while (!window.shouldClose()) {
        const command_buffer = try swapchain.newRenderCommandsBuffer(context);

        try recordCommands(context, command_buffer, .{
            .render_pass = render_pass,
            .framebuffer = framebuffers[swapchain.current_image_index],
            .pipeline = pipeline,
            .pipeline_layout = pipeline_layout,
            .extent = swapchain.extent,
            .uniform_buffer = uniform_buffers[swapchain.current_image_index],
            .descriptor_builder = &descriptor_builder,
            .vertex_index_buffer = vertex_index_buffer,
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
    uniform_buffer: vk_mem.AllocatedBuffer,
    descriptor_builder: *DescriptorBuilder,
    vertex_index_buffer: vk.Buffer,
};

fn recordCommands(context: VkContext, command_buffer: vk.CommandBuffer, params: RecordCommandsParams) !void {
    const viewport = vk_init.viewport(params.extent);
    const scissor = vk_init.scissor(params.extent);

    const cmd = try context.beginRecordCommandBuffer(command_buffer, .{ .one_time_submit_bit = true });

    cmd.setViewport(viewport);
    cmd.setScissor(scissor);

    cmd.beginRenderPass(.{
        .extent = params.extent,
        .clear_values = &.{
            .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
            .{ .depth_stencil = .{ .depth = 1, .stencil = undefined } },
        },
        .render_pass = params.render_pass,
        .framebuffer = params.framebuffer,
    });

    // bind pipeline
    cmd.bindPipeline(params.pipeline, .graphics);

    cmd.bindVertexBuffers(.{ .first_binding = 0, .vertex_buffers = &.{params.vertex_index_buffer}, .offsets = &.{0} });
    const index_offset = @sizeOf(Vertex) * mesh.vertices.len;
    cmd.bindIndexBuffer(params.vertex_index_buffer, index_offset, .uint32);

    const cam_pos = m.init.vec3(0, 0, 2);
    const view = m.init.translationMat4(cam_pos);
    _ = view;

    const data: [*]UniformBufferData = try context.mapMemoryAligned(.{
        .memory = params.uniform_buffer.memory,
        .size = vk.WHOLE_SIZE,
        .offset = 0,
    }, UniformBufferData);
    data[0] = UniformBufferData{
        .model = m.Mat4.identity(),
        .view = m.Mat4.identity(),
        .projection = m.Mat4.identity(),
    };
    context.unmapMemory(params.uniform_buffer.memory);

    var uniform_buffer_builder = params.descriptor_builder.begin();
    try uniform_buffer_builder.bindBuffer(.{
        .binding = 0,
        .buffer_info = UniformBufferData.descriptorbufferInfo(params.uniform_buffer.buffer),
        .descriptor_type = .uniform_buffer,
        .stage_flags = .{ .vertex_bit = true },
    });
    const uniform_buffer_descriptor_set = try uniform_buffer_builder.build(context, null);

    cmd.bindDescriptorSets(.{
        .bind_point = .graphics,
        .pipeline_layout = params.pipeline_layout,
        .descriptor_sets = &.{uniform_buffer_descriptor_set},
        .dynamic_offsets = &.{},
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
