#version 460

layout(location = 0) in vec2 i_pos;
layout(location = 1) in vec3 i_color;

layout(location = 0) out vec3 o_color;

layout(set = 0, binding = 0) uniform UniformBufferData {
    mat4 translation;
    // mat4 model;
    // mat4 view;
    // mat4 projection;
} ub;

struct ShaderStorageBufferData {
    mat4 some_data;
};

layout(std140, set = 1, binding = 0) readonly buffer ShaderStorageBuffer {
    ShaderStorageBufferData objects[];
} ssb;

void main() {
    mat4 some_mat = ssb.objects[gl_BaseInstance].some_data;

    gl_Position = ub.translation * vec4(i_pos, 0.0, 1.0);


    //gl_Position = some_mat * ub.projection * ub.view * ub.model * vec4(i_pos, 0.0, 1.0);
    //gl_Position = ub.projection * ub.view * ub.model * vec4(i_pos, 0.0, 1.0);
    // gl_Position = vec4(i_pos, 0.0, 1.0);
    o_color = i_color;
}


