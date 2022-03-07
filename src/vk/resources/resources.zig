const vk = @import("vulkan");
const vk_mem = @import("../vk_memory.zig");
const vk_cmd = @import("../vk_cmd.zig");
const VkContext = @import("../VkContext.zig");
const DescriptorResource = @import("../vk_descriptor_sets.zig").DescriptorResource;
const Allocator = @import("std").mem.Allocator;
const m = @import("../../math.zig");

// Resources bound for each shader: pipeline, shader control values
pub const shader_source = @import("resources");

// https://developer.nvidia.com/vulkan-shader-resource-binding

pub const DrawIndexedIndirectCommandsBuffer = struct {
    buffer: vk.Buffer,
    memory: vk.DeviceMemory,

    const Self = @This();

    pub fn init(context: VkContext, frames_count: usize) !Self {
        const draw_indirect_buffer = try context.createBufferGraphicsQueue(frames_count * @sizeOf(vk.DrawIndexedIndirectCommand), .{
            // read and write from shaders
            //.transfer_dst_bit = true,
            //.storage_buffer_bit = true,
            // indirect drawing
            .indirect_buffer_bit = true,
        });
        errdefer context.destroyBuffer(draw_indirect_buffer);

        const draw_indirect_memory = try context.allocateBufferMemory(draw_indirect_buffer, .cpu_gpu_visible);
        errdefer context.freeMemory(draw_indirect_memory);

        return Self{
            .buffer = draw_indirect_buffer,
            .memory = draw_indirect_memory,
        };
    }

    pub fn deinit(self: Self, context: VkContext) void {
        context.destroyBuffer(self.buffer);
        context.freeMemory(self.memory);
    }

    pub fn updateMemory(self: Self, context: VkContext, data: vk.DrawIndexedIndirectCommand, data_index: usize) !void {
        const buffer_range = @sizeOf(vk.DrawIndexedIndirectCommand);
        const buffer_offset = buffer_range * data_index;

        const draw_commands_data: [*]vk.DrawIndexedIndirectCommand = try context.mapMemoryAligned(.{
            .memory = self.memory,
            .offset = buffer_offset,
            .size = buffer_range,
        }, vk.DrawIndexedIndirectCommand);

        draw_commands_data[0] = data;

        context.unmapMemory(self.memory);
    }
};

pub const ShaderStorageBufferData = packed struct {
    some_data: m.Mat4,
};

pub fn ShaderStorageBuffer(comptime BufferDataType: type) type {
    return struct {
        buffer: vk.Buffer,
        memory: vk.DeviceMemory,
        descriptor_sets: []vk.DescriptorSet,
        descriptor_layout: vk.DescriptorSetLayout,

        const Self = @This();

        pub fn init(allocator: Allocator, context: VkContext, descriptor_resource: *DescriptorResource, data_count: usize) !Self {
            const buffer_size = context.padStorageBufferSize(@sizeOf(BufferDataType)) * data_count;
            const ssb_buffer = try context.createBufferGraphicsQueue(buffer_size, .{ .storage_buffer_bit = true });
            errdefer context.destroyBuffer(ssb_buffer);

            const ssb_memory = try context.allocateBufferMemory(ssb_buffer, .cpu_gpu_visible);
            errdefer context.freeMemory(ssb_memory);

            const ssb_desc_sets = try allocator.alloc(vk.DescriptorSet, data_count);
            const ssb_desc_layout = try initDescriptorSets(context, ssb_buffer, descriptor_resource, ssb_desc_sets);
            errdefer allocator.free(ssb_desc_sets);

            return Self{
                .buffer = ssb_buffer,
                .memory = ssb_memory,
                .descriptor_sets = ssb_desc_sets,
                .descriptor_layout = ssb_desc_layout,
            };
        }

        pub fn deinit(self: Self, allocator: Allocator, context: VkContext) void {
            context.destroyBuffer(self.buffer);
            context.freeMemory(self.memory);
            // free heap allocated handles, descriptor allocator in DescriptorResource frees the actual sets and the descriptor layout
            allocator.free(self.descriptor_sets);
        }

        fn initDescriptorSets(
            context: VkContext,
            buffer: vk.Buffer,
            descriptor_resource: *DescriptorResource,
            handles: []vk.DescriptorSet,
        ) !vk.DescriptorSetLayout {
            var descriptor_set_layout: vk.DescriptorSetLayout = undefined;

            for (handles) |*set, image_index| {
                const shader_storage_range = context.padStorageBufferSize(@sizeOf(BufferDataType));
                const shader_storage_offset = shader_storage_range * image_index;

                const buffer_info = vk.DescriptorBufferInfo{
                    .buffer = buffer,
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

        pub fn updateMemory(self: Self, context: VkContext, data: BufferDataType, data_index: usize) !void {
            const buffer_range = context.padStorageBufferSize(@sizeOf(BufferDataType));
            const buffer_offset = buffer_range * data_index;

            const mapped_data: [*]BufferDataType = try context.mapMemoryAligned(.{
                .memory = self.memory,
                .size = buffer_range,
                .offset = buffer_offset,
            }, BufferDataType);

            mapped_data[0] = data;

            context.unmapMemory(self.memory);
        }

        pub fn getDescriptorSet(self: Self, data_index: usize) vk.DescriptorSet {
            return self.descriptor_sets[data_index];
        }
    };
}

// Resources bound for each view (image view/framebuffer): camera, environment, etc.
pub fn VertexIndexBuffer(comptime VertexType: type, comptime IndexType: type) type {
    return struct {
        buffer: vk.Buffer,
        memory: vk.DeviceMemory,

        const Self = @This();

        pub fn init(context: VkContext, vertices: []const VertexType, indices: []const IndexType) !Self {
            const vertices_size = @sizeOf(VertexType) * vertices.len;
            const indices_size = @sizeOf(IndexType) * indices.len;
            const buffer_size = vertices_size + indices_size;

            const vertex_index_buffer = try context.createBufferGraphicsQueue(buffer_size, .{
                .vertex_buffer_bit = true,
                .index_buffer_bit = true,
                .transfer_dst_bit = true,
            });
            errdefer context.destroyBuffer(vertex_index_buffer);

            const vertex_index_buffer_memory = try context.allocateBufferMemory(vertex_index_buffer, .gpu_only);
            errdefer context.freeMemory(vertex_index_buffer_memory);

            try vk_mem.immediateUpload(context, VertexType, .{
                .buffer = vertex_index_buffer,
                .offset = 0,
                .upload_data = vertices,
            });
            try vk_mem.immediateUpload(context, IndexType, .{
                .buffer = vertex_index_buffer,
                .offset = vertices_size,
                .upload_data = indices,
            });

            return Self{
                .buffer = vertex_index_buffer,
                .memory = vertex_index_buffer_memory,
            };
        }

        pub fn deinit(self: Self, context: VkContext) void {
            context.destroyBuffer(self.buffer);
            context.freeMemory(self.memory);
        }
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

pub fn UniformBuffer(comptime BufferDataType: type) type {
    return struct {
        buffer: vk.Buffer,
        memory: vk.DeviceMemory,
        descriptor_sets: []vk.DescriptorSet,
        descriptor_layout: vk.DescriptorSetLayout,

        const Self = @This();

        pub fn init(allocator: Allocator, context: VkContext, descriptor_resource: *DescriptorResource, data_count: usize) !Self {
            const uniform_buffer_size = context.padUniformBufferSize(@sizeOf(BufferDataType)) * data_count;
            const uniform_buffer = try context.createBufferGraphicsQueue(uniform_buffer_size, .{ .uniform_buffer_bit = true });
            errdefer context.destroyBuffer(uniform_buffer);
            const uniform_buffer_memory = try context.allocateBufferMemory(uniform_buffer, .cpu_gpu_visible);
            errdefer context.freeMemory(uniform_buffer_memory);

            const ub_desc_sets = try allocator.alloc(vk.DescriptorSet, data_count);
            const ub_desc_layout = try initDescriptorSets(context, uniform_buffer, descriptor_resource, ub_desc_sets);
            errdefer allocator.free(ub_desc_sets);

            return Self{
                .buffer = uniform_buffer,
                .memory = uniform_buffer_memory,
                .descriptor_sets = ub_desc_sets,
                .descriptor_layout = ub_desc_layout,
            };
        }

        pub fn deinit(self: Self, allocator: Allocator, context: VkContext) void {
            context.destroyBuffer(self.buffer);
            context.freeMemory(self.memory);
            // free heap allocated handles, descriptor allocator in DescriptorResource frees the actual sets and the descriptor layout
            allocator.free(self.descriptor_sets);
        }

        pub fn updateMemory(self: Self, context: VkContext, data: BufferDataType, data_index: usize) !void {
            const buffer_range = context.padUniformBufferSize(@sizeOf(BufferDataType));
            const buffer_offset = buffer_range * data_index;

            const mapped_data: [*]BufferDataType = try context.mapMemoryAligned(.{
                .memory = self.memory,
                .size = buffer_range,
                .offset = buffer_offset,
            }, BufferDataType);

            mapped_data[0] = data;

            context.unmapMemory(self.memory);
        }

        pub fn getDescriptorSet(self: Self, data_index: usize) vk.DescriptorSet {
            return self.descriptor_sets[data_index];
        }

        fn initDescriptorSets(
            context: VkContext,
            uniform_buffer: vk.Buffer,
            descriptor_resource: *DescriptorResource,
            handles: []vk.DescriptorSet,
        ) !vk.DescriptorSetLayout {
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
    };
}
