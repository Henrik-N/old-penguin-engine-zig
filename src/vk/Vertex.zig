const vk = @import("vulkan");

const Vertex = @This();

pos: [3]f32,
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
        //.format = .r32g32_sfloat,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Vertex, "pos"),
    },
    .{
        .binding = 0,
        .location = 1,
        .format = .r32g32b32_sfloat,
        .offset = @offsetOf(Vertex, "color"),
    },
};
