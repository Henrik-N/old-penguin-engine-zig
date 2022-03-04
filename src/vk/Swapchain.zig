const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const VkContext = @import("VkContext.zig");
const mem = std.mem;

const vk_init = @import("vk_init.zig");
const vk_mem = @import("vk_memory.zig");
const vk_enumerate = @import("vk_enumerate.zig");

const max_timeout = std.math.maxInt(u64);

// TODO fix swapchain recreation bug
const Swapchain = @This();

handle: vk.SwapchainKHR,
surface_format: vk.SurfaceFormatKHR,
extent: vk.Extent2D,

images: []SwapImage,
current_image_index: usize,

depth_image: DepthImage,

// Semaphore that will get signaled once we've gotten the next image from the swapchain.
// We signal this when getting the image and then set it as the semaphore for the current image.
next_image_acquired_semaphore: vk.Semaphore,

render_commands_pool: vk.CommandPool,
render_command_buffers: []vk.CommandBuffer,

pub fn init(allocator: mem.Allocator, context: VkContext, window: glfw.Window) !Swapchain {
    return try initInner(allocator, context, window, .null_handle);
}

// Initializes everything about the swapchain except the command pool and the command buffers.
fn initInner(
    allocator: mem.Allocator,
    context: VkContext,
    window: glfw.Window,
    // when recreating the swapchain, this can be used as an extra parameter to do so faster
    old_swapchain_handle: vk.SwapchainKHR,
) !Swapchain {
    const surface_capabilities = try context.vki.getPhysicalDeviceSurfaceCapabilitiesKHR(context.physical_device, context.surface);
    const true_extent = try findTrueExtent(surface_capabilities, window);

    if (true_extent.width == 0 or true_extent.height == 0) {
        return error.InvalidExtentSize;
    }

    const surface_format = try findSurfaceFormat(context, allocator);
    const present_mode = try findPresentMode(context, allocator);

    const recommended_image_count = surface_capabilities.min_image_count + 1;
    const has_maximum_value = surface_capabilities.max_image_count > 0;
    const image_count = switch (has_maximum_value) {
        true => std.math.min(recommended_image_count, surface_capabilities.max_image_count),
        false => recommended_image_count,
    };

    const queue_family_indices = [_]u32{ context.graphics_queue.family, context.present_queue.family };
    const sharing_mode = switch (queue_family_indices[0] == queue_family_indices[1]) {
        // best performance, but requires explicit transfer of the image between the queue families if they are different
        // TODO Explicit transfer between queues. Exclusive mode should always be used for the best performance.
        true => vk.SharingMode.exclusive,
        // worse performance, but you can use different queue families without explicit transfer between them.
        false => vk.SharingMode.concurrent,
    };

    const create_info = vk.SwapchainCreateInfoKHR{
        .flags = .{},
        .surface = context.surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = true_extent,
        .image_array_layers = 1,
        .image_usage = .{ .color_attachment_bit = true, .transfer_dst_bit = true },
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = queue_family_indices.len,
        .p_queue_family_indices = &queue_family_indices,
        .pre_transform = surface_capabilities.current_transform,
        .composite_alpha = .{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = vk.TRUE,
        .old_swapchain = old_swapchain_handle,
    };

    const swapchain = try context.vkd.createSwapchainKHR(context.device, &create_info, null);
    errdefer context.vkd.destroySwapchainKHR(context.device, swapchain, null);

    var images = try initSwapchainImages(allocator, context, swapchain, surface_format.format);
    errdefer {
        for (images) |image| image.deinit(context);
        allocator.free(images);
    }

    const depth_image = try DepthImage.init(context, true_extent);
    errdefer depth_image.deinit(context);

    // By acquiring the first image here, we can simplify the interface of the swapchain.
    //
    // If you want to reference the current image while rendering, at the beginning of the
    // application's run loop you first have to aquire an image from the swapchain, submit render commands to it,
    // and then pass it to the swapchain.
    //
    // If you use an extra semaphore, you can instead opt to get the next image at the
    // end of the application loop. This allows you to reference the current image directly
    // from the swapchain struct. The current_image_index field on the swapchain is always going to be one that we
    // submit to when we call submitPresentCommandBuffer.
    //

    // Acquire first image
    //
    var next_image_acquired_semaphore = try context.createSemaphore();
    errdefer context.destroySemaphore(next_image_acquired_semaphore);

    const result = try context.vkd.acquireNextImageKHR(context.device, swapchain, max_timeout, next_image_acquired_semaphore, .null_handle);

    // When we later submit the command buffer with the render commands, we need the
    // execution of them to wait for the semaphore signaled when acquiring the image,
    // as we shouldn't try to write colors to the image before it's available.
    //
    //
    // Since we can't know which image index we are going to use for the next frame
    // at the point of getting it, we can't set it's image_acquired_semaphore until we have
    // the image index.

    // set current image's image_acquired_semaphore
    const current_image_index = result.image_index;
    std.mem.swap(vk.Semaphore, &images[current_image_index].image_acquired_semaphore, &next_image_acquired_semaphore);

    // setup command pool
    const render_commands_pool = try context.createCommandPool(.{}, context.graphics_queue.family);
    errdefer context.destroyCommandPool(render_commands_pool);

    const render_command_buffers = try context.allocateCommandBufferHandles(images.len);
    errdefer context.freeCommandBufferHandles(render_command_buffers);
    try context.allocateCommandBuffers(render_commands_pool, .primary, render_command_buffers);

    return Swapchain{
        .handle = swapchain,
        .surface_format = surface_format,
        .extent = true_extent,
        .images = images,
        .current_image_index = current_image_index,
        .depth_image = depth_image,
        .next_image_acquired_semaphore = next_image_acquired_semaphore,
        .render_commands_pool = render_commands_pool,
        .render_command_buffers = render_command_buffers,
    };
}

pub fn deinit(self: Swapchain, allocator: mem.Allocator, context: VkContext) void {
    self.deinitExceptHandle(allocator, context);

    context.vkd.destroySwapchainKHR(context.device, self.handle, null);
}

pub fn recreate(self: *Swapchain, allocator: mem.Allocator, context: VkContext, window: glfw.Window) !void {
    const old_handle = self.handle;

    self.deinitExceptHandle(allocator, context);
    self.* = try initInner(allocator, context, window, old_handle);
}

fn deinitExceptHandle(self: Swapchain, allocator: mem.Allocator, context: VkContext) void {
    self.depth_image.deinit(context);

    context.freeCommandBuffers(self.render_commands_pool, self.render_command_buffers);
    context.freeCommandBufferHandles(self.render_command_buffers);

    context.destroyCommandPool(self.render_commands_pool);

    for (self.images) |image| image.deinit(context);
    allocator.free(self.images);

    context.destroySemaphore(self.next_image_acquired_semaphore);
}

pub fn newRenderCommandsBuffer(self: Swapchain, context: VkContext) !vk.CommandBuffer {
    // return context.createcomm
    return context.allocateCommandBuffer(self.render_commands_pool, .primary);
}

pub fn submitPresentCommandBuffer(self: *Swapchain, context: VkContext, command_buffer: vk.CommandBuffer) !PresentState {
    const current_image: SwapImage = self.images[self.current_image_index];
    try context.waitForFence(current_image.render_frame_fence);
    try context.resetFence(current_image.render_frame_fence);

    // free command buffer we just finished rendering to
    const just_used_command_buffer = self.render_command_buffers[self.current_image_index];
    context.freeCommandBuffer(self.render_commands_pool, just_used_command_buffer);
    self.render_command_buffers[self.current_image_index] = command_buffer;

    // Submit command buffer to graphics queue
    try self.submitPresent(context, command_buffer, current_image);

    // acquire next image
    //
    const acquire_result = try context.vkd.acquireNextImageKHR(context.device, self.handle, max_timeout, self.next_image_acquired_semaphore, .null_handle);
    self.current_image_index = acquire_result.image_index;

    // set semaphore for this image
    std.mem.swap(vk.Semaphore, &self.images[self.current_image_index].image_acquired_semaphore, &self.next_image_acquired_semaphore);

    return switch (acquire_result.result) {
        .success => .optimal,
        .suboptimal_khr => .suboptimal,
        else => unreachable,
    };
}

fn submitPresent(self: Swapchain, context: VkContext, command_buffer: vk.CommandBuffer, image: SwapImage) !void {
    // Ensure render pass doesn't begin until the image is available.
    // TODO It may be faster to wait for the color attachment output stage in the render pass instead, through using a subpass dependency.
    const wait_stage = [_]vk.PipelineStageFlags{.{ .color_attachment_output_bit = true }};

    try context.vkd.queueSubmit(context.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
        // wait for image acquisition before executing this command buffer
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &image.image_acquired_semaphore),
        .p_wait_dst_stage_mask = &wait_stage,
        //
        .command_buffer_count = 1,
        .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &command_buffer),
        // signal render finished semaphore
        .signal_semaphore_count = 1,
        .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &image.render_completed_semaphore),
    }}, image.render_frame_fence);

    // present
    //
    _ = try context.vkd.queuePresentKHR(context.present_queue.handle, &.{
        // wait until rendering is complete
        .wait_semaphore_count = 1,
        .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &image.render_completed_semaphore),
        // present image at current index
        .swapchain_count = 1,
        .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &self.handle),
        .p_image_indices = @ptrCast([*]const u32, &self.current_image_index),
        .p_results = null,
    });
}

pub fn waitForAllFences(self: Swapchain, context: VkContext) !void {
    for (self.images) |image| {
        try context.waitForFence(image.render_frame_fence);
        //try vk_sync.waitForFence(context, image.render_frame_fence);
    }
}

pub const PresentState = enum {
    optimal,
    suboptimal,
};

pub const SwapImage = struct {
    image: vk.Image,
    image_view: vk.ImageView,
    image_acquired_semaphore: vk.Semaphore,
    render_completed_semaphore: vk.Semaphore,
    render_frame_fence: vk.Fence, // signaled when the frame has finished rendering

    fn init(context: VkContext, image: vk.Image, format: vk.Format) !SwapImage {
        const image_view = try context.createImageView((vk_init.SimpleImageViewCreateInfo{
            .image = image,
            .format = format,
            .aspect_mask = .{ .color_bit = true },
        }).raw());
        errdefer context.destroyImageView(image_view);

        const image_acquired_semaphore = try context.createSemaphore();
        errdefer context.destroySemaphore(image_acquired_semaphore);

        const render_completed_semaphore = try context.createSemaphore();
        errdefer context.destroySemaphore(render_completed_semaphore);

        const render_frame_fence = try context.createFence(.{ .signaled_bit = true });
        errdefer context.destroyFence(render_frame_fence);

        return SwapImage{
            .image = image,
            .image_view = image_view,
            .image_acquired_semaphore = image_acquired_semaphore,
            .render_completed_semaphore = render_completed_semaphore,
            .render_frame_fence = render_frame_fence,
        };
    }

    fn deinit(self: SwapImage, context: VkContext) void {
        context.waitForFence(self.render_frame_fence) catch {
            std.log.err("SwapImage couldn't wait for fence!", .{});
        };

        context.vkd.destroyFence(context.device, self.render_frame_fence, null);
        context.vkd.destroySemaphore(context.device, self.render_completed_semaphore, null);
        context.vkd.destroySemaphore(context.device, self.image_acquired_semaphore, null);
        context.vkd.destroyImageView(context.device, self.image_view, null);
    }
};

pub const DepthImage = struct {
    image: vk.Image,
    image_memory: vk.DeviceMemory,
    image_view: vk.ImageView,
    format: vk.Format,

    const Self = @This();

    fn init(context: VkContext, extent: vk.Extent2D) !Self {
        // ordered from most desirable to least desirable
        // NOTE The order of this should change if using a stencil component is desired.
        const format_priorities = [_]vk.Format{
            .d32_sfloat,
            .d32_sfloat_s8_uint,
            .d24_unorm_s8_uint,
        };

        const tiling: vk.ImageTiling = .optimal;

        const depth_format = try findSupportedFormat(context, &format_priorities, tiling, .{ .depth_stencil_attachment_bit = true });

        const image_create_info: vk.ImageCreateInfo = (vk_init.SimpleImageCreateInfo{
            .extent = .{
                .width = extent.width,
                .height = extent.height,
                .depth = 1,
            },
            .format = depth_format,
            .tiling = tiling,
            .usage = .{ .depth_stencil_attachment_bit = true },
        }).raw();
        const image = try context.createImage(image_create_info);
        errdefer context.destroyImage(image);

        const memory = try context.allocateImageMemory(image, .gpu_only);
        errdefer context.freeMemory(memory);

        const image_view = try context.createImageView((vk_init.SimpleImageViewCreateInfo{
            .image = image,
            .format = depth_format,
            .aspect_mask = .{ .depth_bit = true },
        }).raw());
        errdefer context.destroyImageView(image_view);

        return Self{
            .image = image,
            .image_memory = memory,
            .image_view = image_view,
            .format = depth_format,
        };
    }

    fn deinit(self: Self, context: VkContext) void {
        context.destroyImageView(self.image_view);
        context.destroyImage(self.image);
        context.freeMemory(self.image_memory);
    }

    fn findSupportedFormat(context: VkContext, format_priority_list: []const vk.Format, tiling: vk.ImageTiling, features: vk.FormatFeatureFlags) !vk.Format {
        for (format_priority_list) |format| {
            const pd_format_properties: vk.FormatProperties = context.vki.getPhysicalDeviceFormatProperties(context.physical_device, format);

            const is_supported = switch (tiling) {
                .optimal => pd_format_properties.optimal_tiling_features.contains(features),
                .linear => pd_format_properties.linear_tiling_features.contains(features),
                else => unreachable,
            };

            if (is_supported) {
                return format;
            }
        }

        return error.NoSupportedFormat;
    }
};

fn initSwapchainImages(allocator: mem.Allocator, context: VkContext, swapchain: vk.SwapchainKHR, format: vk.Format) ![]SwapImage {
    const swapchain_images = try vk_enumerate.getSwapchainImagesKHR(allocator, context, swapchain);
    defer allocator.free(swapchain_images);

    const swap_images = try allocator.alloc(SwapImage, swapchain_images.len);

    var allocated_count: usize = 0;
    errdefer for (swap_images[0..allocated_count]) |allocated_image| allocated_image.deinit(context);

    for (swapchain_images) |image, index| {
        swap_images[index] = try SwapImage.init(context, image, format);
        allocated_count += 1;
    }

    return swap_images;
}

/// Swapchain extent == the resolution of the swap images.
fn findTrueExtent(surface_capabilities: vk.SurfaceCapabilitiesKHR, window: glfw.Window) !vk.Extent2D {
    // current_extent.width/height == max u32 => window manager allows custom resolution and Vulkan didn't set it automatically.
    if (surface_capabilities.current_extent.width != std.math.maxInt(u32)) {
        return surface_capabilities.current_extent;
    }

    // The one specified earlier is in screen coords doesn't apply to high DPI-displays, as the
    //  screen coordinates won't be 1:1 with the pixel coords. High DPI-displays have more pixels which will make
    //  everything look small if we don't adjust for it.
    const framebuffer_size: glfw.Window.Size = try window.getFramebufferSize();

    return vk.Extent2D{
        .width = std.math.clamp(framebuffer_size.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
        .height = std.math.clamp(framebuffer_size.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
    };
}

/// Finds the best supported format and colors space for the surface.
/// Format: color channels and types (for example RGBA)
/// Color space: linear or non-linear (SRGB)
fn findSurfaceFormat(context: VkContext, allocator: mem.Allocator) !vk.SurfaceFormatKHR {
    const surface_formats = try vk_enumerate.getPhysicalDeviceSurfaceFormatsKHR(allocator, context);
    defer allocator.free(surface_formats);

    const preferred_surface_format = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_srgb, // RGBA SRGB
        .color_space = .srgb_nonlinear_khr, // nonlinear color space
    };

    // use preferred format if it exists
    for (surface_formats) |surface_format| {
        if (std.meta.eql(surface_format, preferred_surface_format)) {
            return preferred_surface_format;
        }
    }

    // otherwise just use the first available format
    if (surface_formats.len == 0) {
        return error.FailedToFindSurfaceFormats;
    }

    return surface_formats[0];
}

/// Finds the best supported presentation mode for the Swapchain.
/// The presentation mode decides the conditions for an image to presented to the screen.
fn findPresentMode(context: VkContext, allocator: mem.Allocator) !vk.PresentModeKHR {
    const available_present_modes = try vk_enumerate.getPhysicalDeviceSurfacePresentModesKHR(allocator, context);
    defer allocator.free(available_present_modes);

    const preferred_present_modes = [_]vk.PresentModeKHR{
        // Like fifo but doesn't block when the queue is full. Instead, it replaces the queued images with newer ones.
        //  Can be used to render frames fast but still avoids tearing (triple buffering).
        .mailbox_khr,
        // Images submitted are transferred to the screen right away. Fast, but may cause tearing.
        .immediate_khr,
    };

    for (preferred_present_modes) |preferred_mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, available_present_modes, preferred_mode) != null) {
            return preferred_mode;
        }
    }

    // First-in, first-out queue. Blocks and waits for more images once the queue is full. Guaranteed to be available, similar to v-sync.
    return .fifo_khr;
}
