///! Vulkan type wrappers that take advantage of Zig's slices.
const vk = @import("vulkan");

pub const RenderPassCreateInfo = struct {
    p_next: ?*anyopaque = null,
    flags: vk.RenderPassCreateFlags,
    attachments: []const vk.AttachmentDescription,
    subpasses: []const vk.SubpassDescription,
    subpass_dependencies: []const vk.SubpassDependency,

    pub fn raw(self: RenderPassCreateInfo) vk.RenderPassCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = self.flags,
            .attachment_count = @intCast(u32, self.attachments.len),
            .p_attachments = @ptrCast([*]const vk.AttachmentDescription, self.attachments.ptr),
            .subpass_count = @intCast(u32, self.subpasses.len),
            .p_subpasses = @ptrCast([*]const vk.SubpassDescription, self.subpasses.ptr),
            .dependency_count = @intCast(u32, self.subpass_dependencies.len),
            .p_dependencies = @ptrCast([*]const vk.SubpassDependency, self.subpass_dependencies.ptr),
        };
    }
};

pub const SubpassDescription = struct {
    flags: vk.SubpassDescriptionFlags,
    pipeline_bind_point: vk.PipelineBindPoint,
    input_attachment_refs: []const vk.AttachmentReference,
    color_attachment_refs: []const vk.AttachmentReference,
    depth_attachment_ref: ?*const vk.AttachmentReference,
    resolve_attachment_refs: []const vk.AttachmentReference, // optional
    preserve_attachments: []const u32, // optional

    pub fn raw(self: SubpassDescription) vk.SubpassDescription {
        return .{
            .flags = self.flags,
            .pipeline_bind_point = self.pipeline_bind_point,
            .input_attachment_count = @intCast(u32, self.input_attachment_refs.len),
            .p_input_attachments = @ptrCast([*]const vk.AttachmentReference, self.input_attachment_refs.ptr),
            .color_attachment_count = @intCast(u32, self.color_attachment_refs.len),
            .p_color_attachments = @ptrCast([*]const vk.AttachmentReference, self.color_attachment_refs.ptr),
            .p_resolve_attachments = @ptrCast([*]const vk.AttachmentReference, self.resolve_attachment_refs.ptr),
            .p_depth_stencil_attachment = self.depth_attachment_ref,
            .preserve_attachment_count = @intCast(u32, self.preserve_attachments.len),
            .p_preserve_attachments = @ptrCast([*]const u32, self.preserve_attachments.ptr),
        };
    }
};

pub const DescriptorSetLayoutCreateInfo = struct {
    p_next: ?*const anyopaque = null,
    flags: vk.DescriptorSetLayoutCreateFlags,
    bindings: []const vk.DescriptorSetLayoutBinding,

    pub fn raw(self: DescriptorSetLayoutCreateInfo) vk.DescriptorSetLayoutCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = self.flags,
            .binding_count = @intCast(u32, self.bindings.len),
            .p_bindings = @ptrCast([*]const vk.DescriptorSetLayoutBinding, self.bindings.ptr),
        };
    }
};

pub const DescriptorPoolCreateInfo = struct {
    p_next: ?*const anyopaque = null,
    flags: vk.DescriptorPoolCreateFlags,
    max_sets: usize,
    pool_sizes: []const vk.DescriptorPoolSize,

    pub fn raw(self: DescriptorPoolCreateInfo) vk.DescriptorPoolCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = self.flags,
            .max_sets = @intCast(u32, self.max_sets),
            .pool_size_count = @intCast(u32, self.pool_sizes.len),
            .p_pool_sizes = @ptrCast([*]const vk.DescriptorPoolSize, self.pool_sizes.ptr),
        };
    }
};

pub const DescriptorSetAllocateInfo = struct {
    p_next: ?*const anyopaque = null,
    descriptor_pool: vk.DescriptorPool,
    set_layouts: []const vk.DescriptorSetLayout,

    pub fn raw(self: DescriptorSetAllocateInfo) vk.DescriptorSetAllocateInfo {
        return .{
            .p_next = self.p_next,
            .descriptor_pool = self.descriptor_pool,
            .descriptor_set_count = @intCast(u32, self.set_layouts.len),
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, self.set_layouts.ptr),
        };
    }
};

pub const PipelineLayoutCreateInfo = struct {
    p_next: ?*const anyopaque = null,
    flags: vk.PipelineLayoutCreateFlags,
    set_layouts: []const vk.DescriptorSetLayout,
    push_constant_ranges: []const vk.PushConstantRange,

    pub fn raw(self: PipelineLayoutCreateInfo) vk.PipelineLayoutCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = self.flags,
            .set_layout_count = @intCast(u32, self.set_layouts.len),
            .p_set_layouts = @ptrCast([*]const vk.DescriptorSetLayout, self.set_layouts.ptr),
            .push_constant_range_count = @intCast(u32, self.push_constant_ranges.len),
            .p_push_constant_ranges = @ptrCast([*]const vk.PushConstantRange, self.push_constant_ranges.ptr),
        };
    }
};

pub const FrameBufferCreateInfo = struct {
    p_next: ?*const anyopaque = null,
    flags: vk.FramebufferCreateFlags,
    render_pass: vk.RenderPass,
    attachments: []const vk.ImageView,
    extent: vk.Extent2D,
    layer_count: u32, // number of layers in the image arrays

    pub fn raw(self: FrameBufferCreateInfo) vk.FramebufferCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = .{},
            .render_pass = self.render_pass,
            .attachment_count = @intCast(u32, self.attachments.len),
            .p_attachments = @ptrCast([*]const vk.ImageView, self.attachments.ptr),
            .width = self.extent.width,
            .height = self.extent.height,
            .layers = self.layer_count,
        };
    }
};

pub const BufferCreateInfo = struct {
    p_next: ?*const anyopaque = null,
    flags: vk.BufferCreateFlags,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    sharing_mode: vk.SharingMode,
    queue_family_indices: []const u32,

    pub fn raw(self: BufferCreateInfo) vk.BufferCreateInfo {
        return .{
            .p_next = self.p_next,
            .flags = self.flags,
            .size = self.size,
            .usage = self.usage,
            .sharing_mode = self.sharing_mode,
            .queue_family_index_count = @intCast(u32, self.queue_family_indices.len),
            .p_queue_family_indices = @ptrCast([*]const u32, self.queue_family_indices.ptr),
        };
    }
};
