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

const Vertex = @import("vk/Vertex.zig");
const VertexIndex = u32;
const VertexIndexBuffer = resources.VertexIndexBuffer(Vertex, VertexIndex);

const UniformBufferData = resources.UniformBufferData;
const UniformBuffer = resources.UniformBuffer(UniformBufferData);

const ShaderStorageBufferData = resources.ShaderStorageBufferData;
const ShaderStorageBuffer = resources.ShaderStorageBuffer(ShaderStorageBufferData);

const MeshView = struct {
    vertices: []const Vertex, // TODO slice of memory from bigger buffer
    indices: []const VertexIndex, // TODO slice of memory from bigger buffer

    pub fn new(vertices: []const Vertex, indices: []const VertexIndex) MeshView {
        return MeshView{ .vertices = vertices, .indices = indices };
    }
};

// cube
const cube_mesh = struct {
    // vertex entry
    fn ve(pos: [3]f32, color: [3]f32) Vertex {
        return .{ .pos = pos, .color = color };
    }

    const red = [_]f32{ 1, 0, 0 };
    const green = [_]f32{ 0, 1, 0 };
    const blue = [_]f32{ 0, 0, 1 };
    const white = [_]f32{ 1, 1, 1 };

    const vertices = [_]Vertex{
        // top
        ve(.{ -1, 1, -1 }, red),
        ve(.{ 1, 1, -1 }, green),
        ve(.{ -1, 1, 1 }, blue),
        ve(.{ 1, 1, 1 }, white),
        // bottom
        ve(.{ -1, -1, -1 }, red),
        ve(.{ 1, -1, -1 }, green),
        ve(.{ -1, -1, 1 }, blue),
        ve(.{ 1, -1, 1 }, white),
        // front
        ve(.{ -1, 1, 1 }, red),
        ve(.{ 1, 1, 1 }, green),
        ve(.{ -1, -1, 1 }, blue),
        ve(.{ 1, -1, 1 }, white),
        // back
        ve(.{ -1, 1, -1 }, red),
        ve(.{ 1, 1, -1 }, green),
        ve(.{ -1, -1, -1 }, blue),
        ve(.{ 1, -1, -1 }, white),
        // left
        ve(.{ -1, 1, 1 }, red),
        ve(.{ -1, 1, -1 }, green),
        ve(.{ -1, -1, 1 }, blue),
        ve(.{ -1, -1, -1 }, white),
        // right
        ve(.{ 1, 1, 1 }, red),
        ve(.{ 1, 1, -1 }, green),
        ve(.{ 1, -1, 1 }, blue),
        ve(.{ 1, -1, -1 }, white),
    };

    fn side(a: VertexIndex, b: VertexIndex, c: VertexIndex) [3]VertexIndex {
        return .{ a, b, c };
    }

    const indices = [_]VertexIndex{
        //top
        0,  1,  2,
        //
        2,  3,  1,
        // bottom
        4,  5,  6,
        //
        6,  7,  5,
        // front
        8,  9,  10,
        //
        10, 11, 9,
        // back
        12, 13, 14,
        //
        14, 15, 13,
        // left
        16, 17, 18,
        //
        18, 19, 17,
        // right
        20, 21, 22,
        //
        22, 23, 21,
    };
};

// triangle
const mesh = struct {
    const vertices = [_]Vertex{
        .{ .pos = .{ -0.5, -0.5, 0.0 }, .color = .{ 1, 0, 0 } },
        .{ .pos = .{ 0.5, -0.5, 0.0 }, .color = .{ 0, 1, 0 } },
        .{ .pos = .{ 0.5, 0.5, 0.0 }, .color = .{ 0, 0, 1 } },
        .{ .pos = .{ -0.5, 0.5, 0.0 }, .color = .{ 1, 1, 1 } },
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

    // BUFFERS
    //
    const vertex_index_buffer = try VertexIndexBuffer.init(context, mesh_view.vertices[0..], mesh_view.indices[0..]);
    defer vertex_index_buffer.deinit(context);

    const uniform_buffer = try UniformBuffer.init(allocator, context, &descriptor_resource, swapchain.images.len);
    defer uniform_buffer.deinit(allocator, context);

    const ssb = try ShaderStorageBuffer.init(allocator, context, &descriptor_resource, swapchain.images.len);
    defer ssb.deinit(allocator, context);

    const draw_indirect_buffer = try resources.DrawIndexedIndirectCommandsBuffer.init(context, swapchain.images.len); // TODO frames count
    defer draw_indirect_buffer.deinit(context);

    const pipeline_layout = try context.createPipelineLayout(.{
        .flags = .{},
        .set_layouts = &.{ uniform_buffer.descriptor_layout, ssb.descriptor_layout },
        .push_constant_ranges = &.{},
    });
    defer context.destroyPipelineLayout(pipeline_layout);

    const vert = try context.createShaderModule(resources.shader_source.tri_vert);
    const frag = try context.createShaderModule(resources.shader_source.tri_frag);

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

    context.destroyShaderModule(vert);
    context.destroyShaderModule(frag);

    var framebuffers = try context.allocateFramebufferHandles(swapchain);
    defer context.freeFramebufferHandles(framebuffers);
    try context.createFramebuffers(swapchain, render_pass, framebuffers);
    defer context.destroyFramebuffers(framebuffers);

    var transform = m.Mat4.identity();
    transform = transform.mul(m.translation(m.vec3(0.5, 0.0, 0.0)));
    transform = transform.mul(m.scale(m.vec3(0.3, 0.3, 0.3)));

    var frame_count: f32 = 30;

    while (!window.shouldClose()) {
        frame_count += 1.0;

        // spin spin
        transform = transform.mul(m.rotZ(frame_count));

        {
            try uniform_buffer.updateMemory(context, UniformBufferData{
                .translation = transform,
                // .model = m.Mat4.identity(),
                // .view = m.Mat4.identity(),
                // .projection = m.Mat4.identity(),
            }, swapchain.current_image_index);

            try ssb.updateMemory(context, ShaderStorageBufferData{
                .some_data = m.Mat4.identity(),
            }, swapchain.current_image_index);

            try draw_indirect_buffer.updateMemory(context, vk.DrawIndexedIndirectCommand{
                .index_count = mesh.indices.len,
                .instance_count = 1,
                .first_index = 0,
                .vertex_offset = 0,
                .first_instance = @intCast(u32, swapchain.current_image_index),
            }, swapchain.current_image_index);
        }

        // upload render commands
        const command_buffer = try swapchain.newRenderCommandsBuffer(context);
        {
            const cmd = try context.beginRecordCommandBuffer(command_buffer, .{ .one_time_submit_bit = true });

            recordViewFrequencyCommands(cmd, .{
                .viewport = vk_init.viewport(swapchain.extent),
                .scissor = vk_init.scissor(swapchain.extent),
                .pipeline = pipeline,
                .pipeline_layout = pipeline_layout,
                .vertex_index_buffer = vertex_index_buffer.buffer,
                .descriptor_sets = &.{
                    uniform_buffer.getDescriptorSet(swapchain.current_image_index),
                    ssb.getDescriptorSet(swapchain.current_image_index),
                },
            });

            recordRenderPass(cmd, .{
                .extent = swapchain.extent,
                .render_pass = render_pass,
                .framebuffer = framebuffers[swapchain.current_image_index],
                .draw_indirect_commands_buffer = draw_indirect_buffer.buffer,
            });

            try cmd.end();
        }

        // submit render commands
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

pub const RecordViewFrequencyCommands = struct {
    viewport: vk.Viewport,
    scissor: vk.Rect2D,

    pipeline: vk.Pipeline,
    pipeline_layout: vk.PipelineLayout,

    vertex_index_buffer: vk.Buffer,
    descriptor_sets: []const vk.DescriptorSet,
};

// commands will be run once per view
fn recordViewFrequencyCommands(cmd: vk_cmd.CommandBufferRecorder, params: RecordViewFrequencyCommands) void {
    cmd.setViewport(params.viewport);
    cmd.setScissor(params.scissor);

    const vertex_index_buffer = params.vertex_index_buffer;

    // every view
    {
        cmd.bindVertexBuffers(.{ .first_binding = 0, .vertex_buffers = &.{vertex_index_buffer}, .offsets = &.{0} });
        const index_buffer_offset = @sizeOf(Vertex) * mesh.vertices.len;
        cmd.bindIndexBuffer(vertex_index_buffer, index_buffer_offset, .uint32);

        cmd.bindDescriptorSets(.{
            .bind_point = .graphics,
            .pipeline_layout = params.pipeline_layout,
            .first_set = 0,
            .descriptor_sets = params.descriptor_sets,
            .dynamic_offsets = &.{},
        });

        cmd.bindPipeline(params.pipeline, .graphics);
    }
}

pub const RecordRenderPassParams = struct {
    extent: vk.Extent2D,
    render_pass: vk.RenderPass,
    framebuffer: vk.Framebuffer,
    draw_indirect_commands_buffer: vk.Buffer,
};

fn recordRenderPass(cmd: vk_cmd.CommandBufferRecorder, params: RecordRenderPassParams) void {
    cmd.beginRenderPass(.{
        .extent = params.extent,
        .clear_values = &.{
            .{ .color = .{ .float_32 = .{ 0, 0, 0, 1 } } },
            .{ .depth_stencil = .{ .depth = 1, .stencil = undefined } },
        },
        .render_pass = params.render_pass,
        .framebuffer = params.framebuffer,
    });

    cmd.drawIndexedIndirect(.{
        .buffer = params.draw_indirect_commands_buffer,
        .offset = 0,
        .draw_count = 1,
        .stride = 0,
    });

    cmd.endRenderPass();
}
