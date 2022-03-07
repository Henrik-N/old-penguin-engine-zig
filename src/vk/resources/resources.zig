const vk = @import("vulkan");
const vk_mem = @import("../vk_memory.zig");
const vk_cmd = @import("../vk_cmd.zig");
const VkContext = @import("../VkContext.zig");
const DescriptorResource = @import("../vk_descriptor_sets.zig").DescriptorResource;

const m = @import("../../math.zig");

// https://developer.nvidia.com/vulkan-shader-resource-binding

// Resources bound for each shader: pipeline, shader control values
pub const shader_resources = struct {
    pub const shader_source = @import("resources");

    const max_shader_object_count = 1000;
    pub const ShaderStorageBufferData = packed struct {
        some_data: m.Mat4,
    };

    pub fn baseInstanceIndex(frame_index: usize) usize {
        return frame_index * max_shader_object_count;
    }

    // TODO try with offsets in a single buffer
    // TODO try with several buffers

    pub fn initShaderStorageBuffer(context: VkContext, frames_count: usize) !vk_mem.AllocatedBuffer {
        const storage_buffer_size = context.padStorageBufferSize(@sizeOf(ShaderStorageBufferData)) * frames_count * max_shader_object_count;
        const storage_buffer = try context.createBufferGraphicsQueue(storage_buffer_size, .{ .storage_buffer_bit = true });
        errdefer context.destroyBuffer(storage_buffer);

        const storage_buffer_memory = try context.allocateBufferMemory(storage_buffer, .cpu_gpu_visible);
        errdefer context.freeMemory(storage_buffer_memory);

        return vk_mem.AllocatedBuffer{
            .buffer = storage_buffer,
            .memory = storage_buffer_memory,
        };
    }

    pub fn initDescriptorSets(
        context: VkContext,
        shader_storage_buffer: vk.Buffer,
        descriptor_resource: *DescriptorResource,
        handles: []vk.DescriptorSet,
    ) !vk.DescriptorSetLayout {
        var descriptor_set_layout: vk.DescriptorSetLayout = undefined;

        for (handles) |*set, image_index| {
            const shader_storage_range = context.padStorageBufferSize(@sizeOf(ShaderStorageBufferData));
            const shader_storage_offset = shader_storage_range * image_index;

            const buffer_info = vk.DescriptorBufferInfo{
                .buffer = shader_storage_buffer,
                .offset = shader_storage_offset,
                .range = shader_storage_range,
            };

            var descriptor_builder = try descriptor_resource.beginDescriptorSetBuilder(1);
            set.* = try descriptor_builder.build(.{
                .{
                    // uniform buffer binding
                    .buffer_binding = .{
                        .binding = 0,
                        .buffer_info = buffer_info,
                        .descriptor_type = .storage_buffer,
                        .stage_flags = .{ .vertex_bit = true },
                    },
                },
            }, &descriptor_set_layout);
        }

        return descriptor_set_layout;
    }

    pub const UpdateShaderResourcesParams = struct {
        image_index: usize,
        storage_buffer_memory: vk.DeviceMemory,
        data: *const ShaderStorageBufferData,
    };

    pub fn updateShaderResources(context: VkContext, params: UpdateShaderResourcesParams) !void {
        const buffer_range = context.padStorageBufferSize(@sizeOf(ShaderStorageBufferData));
        const buffer_offset = buffer_range * params.image_index;

        const data: [*]ShaderStorageBufferData = try context.mapMemoryAligned(.{
            .memory = params.storage_buffer_memory,
            .size = buffer_range,
            .offset = buffer_offset,
        }, ShaderStorageBufferData);

        data[0] = params.data.*;

        context.unmapMemory(params.storage_buffer_memory);
    }

    pub fn bindShaderResources(cmd: vk_cmd.CommandBufferRecorder, pipeline_layout: vk.PipelineLayout, descriptor_sets: []const vk.DescriptorSet) void {
        cmd.bindDescriptorSets(.{
            .bind_point = .graphics,
            .pipeline_layout = pipeline_layout,
            .first_set = 1, // descriptor set 1
            .descriptor_sets = descriptor_sets,
            .dynamic_offsets = &.{},
        });
    }
};

// Resources bound for each view (image view/framebuffer): camera, environment, etc.
pub const view_resources = struct {
    pub const Vertex = struct {
        pos: [2]f32,
        color: [3]f32,

        pub const binding_descriptions = [_]vk.VertexInputBindingDescription{.{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .input_rate = .vertex,
        }};

        pub const attribute_descriptions = [_]vk.VertexInputAttributeDescription{
            .{
                .binding = 0,
                .location = 0,
                .format = .r32g32_sfloat,
                .offset = @offsetOf(Vertex, "pos"),
            },
            .{
                .binding = 0,
                .location = 1,
                .format = .r32g32b32_sfloat,
                .offset = @offsetOf(Vertex, "color"),
            },
        };
    };

    pub const VertexIndex = u32;

    pub fn initVertexIndexBuffer(context: VkContext, vertices: []const Vertex, indices: []const VertexIndex) !vk_mem.AllocatedBuffer {
        const vertices_size = @sizeOf(Vertex) * vertices.len;
        const indices_size = @sizeOf(VertexIndex) * indices.len;
        const buffer_size = vertices_size + indices_size;

        const vertex_index_buffer = try context.createBufferGraphicsQueue(buffer_size, .{
            .vertex_buffer_bit = true,
            .index_buffer_bit = true,
            .transfer_dst_bit = true,
        });
        errdefer context.destroyBuffer(vertex_index_buffer);

        const vertex_index_buffer_memory = try context.allocateBufferMemory(vertex_index_buffer, .gpu_only);
        errdefer context.freeMemory(vertex_index_buffer_memory);

        try vk_mem.immediateUpload(context, Vertex, .{
            .buffer = vertex_index_buffer,
            .offset = 0,
            .upload_data = vertices,
        });
        try vk_mem.immediateUpload(context, VertexIndex, .{
            .buffer = vertex_index_buffer,
            .offset = vertices_size,
            .upload_data = indices,
        });

        return vk_mem.AllocatedBuffer{
            .buffer = vertex_index_buffer,
            .memory = vertex_index_buffer_memory,
        };
    }

    pub const UniformBufferData = packed struct {
        model: m.Mat4,
        view: m.Mat4,
        projection: m.Mat4,

        const Self = @This();

        pub fn descriptorSetLayoutBinding(binding: u32) vk.DescriptorSetLayoutBinding {
            return .{
                .binding = binding,
                .descriptor_type = .uniform_buffer,
                .descriptor_count = 1,
                .stage_flags = .{ .vertex_bit = true },
                .p_immutable_samplers = null, // only relevant for image sampling related descriptors
            };
        }

        pub fn descriptorbufferInfo(buffer: vk.Buffer, offset: usize) vk.DescriptorBufferInfo {
            return .{
                .buffer = buffer,
                .offset = @intCast(u32, offset),
                .range = @sizeOf(UniformBufferData),
            };
        }
    };

    pub fn initUniformBuffer(context: VkContext, frames_count: usize) !vk_mem.AllocatedBuffer {
        const uniform_buffer_size = context.padUniformBufferSize(@sizeOf(view_resources.UniformBufferData)) * frames_count;
        const uniform_buffer_buffer = try context.createBufferGraphicsQueue(uniform_buffer_size, .{ .uniform_buffer_bit = true });
        errdefer context.destroyBuffer(uniform_buffer_buffer);
        const uniform_buffer_memory = try context.allocateBufferMemory(uniform_buffer_buffer, .cpu_gpu_visible);
        errdefer context.freeMemory(uniform_buffer_memory);

        const uniform_buffer = vk_mem.AllocatedBuffer{ .buffer = uniform_buffer_buffer, .memory = uniform_buffer_memory };

        return uniform_buffer;
    }

    pub fn initDescriptorSets(context: VkContext, uniform_buffer: vk.Buffer, descriptor_resource: *DescriptorResource, handles: []vk.DescriptorSet) !vk.DescriptorSetLayout {
        var descriptor_set_layout: vk.DescriptorSetLayout = undefined;

        for (handles) |*set, image_index| {
            const uniform_buffer_range = context.padUniformBufferSize(@sizeOf(UniformBufferData));
            const uniform_buffer_offset = uniform_buffer_range * image_index;

            const uniform_buffer_info = vk.DescriptorBufferInfo{
                .buffer = uniform_buffer,
                .offset = uniform_buffer_offset,
                .range = uniform_buffer_range,
            };

            var descriptor_builder = try descriptor_resource.beginDescriptorSetBuilder(1);
            set.* = try descriptor_builder.build(.{
                .{
                    // uniform buffer binding
                    .buffer_binding = .{
                        .binding = 0,
                        .buffer_info = uniform_buffer_info,
                        .descriptor_type = .uniform_buffer,
                        .stage_flags = .{ .vertex_bit = true },
                    },
                },
            }, &descriptor_set_layout);
        }

        return descriptor_set_layout;
    }

    pub const UpdateBindViewResourcesParams = struct {
        current_image_index: usize,
        uniform_buffer: struct {
            memory: vk.DeviceMemory,
            data: *const UniformBufferData,
        },
        pipeline_layout: vk.PipelineLayout,
        descriptor_sets: []const vk.DescriptorSet,
    };

    pub const UpdateViewResourcesParams = struct {
        image_index: usize,
        uniform_buffer_memory: vk.DeviceMemory,
        data: *const UniformBufferData,
    };

    pub fn updateViewResources(context: VkContext, params: UpdateViewResourcesParams) !void {
        const uniform_buffer_range = context.padUniformBufferSize(@sizeOf(UniformBufferData));
        const uniform_buffer_offset = uniform_buffer_range * params.image_index;

        const data: [*]view_resources.UniformBufferData = try context.mapMemoryAligned(.{
            .memory = params.uniform_buffer_memory,
            .size = uniform_buffer_range,
            .offset = uniform_buffer_offset,
        }, view_resources.UniformBufferData);

        data[0] = params.data.*;

        context.unmapMemory(params.uniform_buffer_memory);
    }

    pub fn bindViewResources(cmd: vk_cmd.CommandBufferRecorder, pipeline_layout: vk.PipelineLayout, descriptor_sets: []const vk.DescriptorSet) void {
        cmd.bindDescriptorSets(.{
            .bind_point = .graphics,
            .pipeline_layout = pipeline_layout,
            .first_set = 0,
            .descriptor_sets = descriptor_sets,
            .dynamic_offsets = &.{},
        });
    }
};
