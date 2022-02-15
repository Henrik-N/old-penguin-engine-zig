const vk = @import("vulkan");
const VkContext = @import("vk_context.zig").VkContext;

pub fn shaderModule(context: VkContext, comptime shader_source: []const u8) !vk.ShaderModule {
    const shader_module = try context.vkd.createShaderModule(context.device, &.{
        .flags = .{},
        .code_size = shader_source.len,
        .p_code = @ptrCast([*]const u32, shader_source),
    }, null);
    return shader_module;
}


pub const pipeline = struct {
    pub fn shaderStageCreateInfo(stage_flags: vk.ShaderStageFlags, shader_module: vk.ShaderModule) vk.PipelineShaderStageCreateInfo {
        return .{
            .flags = .{},
            .stage = stage_flags,
            .module = shader_module,
            .p_name = "main",
            .p_specialization_info = null,
        };
    }
};

