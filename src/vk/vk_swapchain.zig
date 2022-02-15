const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const VkContext = @import("vk_context.zig").VkContext;

const Allocator = std.mem.Allocator;

pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    images: []SwapImage,
    surface_format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,

    pub fn init(context: VkContext, window: glfw.Window, allocator: Allocator) !Swapchain {
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
            .old_swapchain = .null_handle, // TODO swapchain recreation
        };

        const swapchain = try context.vkd.createSwapchainKHR(context.device, &create_info, null);
        errdefer context.vkd.destroySwapchainKHR(context.device, swapchain, null);

        const images = try initSwapchainImages(context, swapchain, surface_format.format, allocator);
        errdefer {
            for (images) |image| image.deinit(context);
            allocator.free(images);
        }

        return Swapchain{
            .handle = swapchain,
            .images = images,
            .surface_format = surface_format,
            .extent = true_extent,
        };
    }

    pub fn deinit(self: Swapchain, context: VkContext, allocator: Allocator) void {
        for (self.images) |image| image.deinit(context);
        allocator.free(self.images);
        context.vkd.destroySwapchainKHR(context.device, self.handle, null);
    }
};

pub const SwapImage = struct {
    image: vk.Image,
    image_view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_completed: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(context: VkContext, image: vk.Image, format: vk.Format) !SwapImage {
        const image_view_create_info = vk.ImageViewCreateInfo{
            .flags = .{},
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        const image_view = try context.vkd.createImageView(context.device, &image_view_create_info, null);
        errdefer context.vkd.destroyImageView(context.device, image_view, null);

        const image_acquired_semaphore = try context.vkd.createSemaphore(context.device, &.{ .flags = .{} }, null);
        errdefer context.vkd.destroySemaphore(context.device, image_acquired_semaphore, null);

        const render_completed_semaphore = try context.vkd.createSemaphore(context.device, &.{ .flags = .{} }, null);
        errdefer context.vkd.destroySemaphore(context.device, render_completed_semaphore, null);

        const frame_fence = try context.vkd.createFence(context.device, &.{ .flags = .{ .signaled_bit = true } }, null);
        errdefer context.vkd.destroyFence(context.device, frame_fence, null);

        return SwapImage{
            .image = image,
            .image_view = image_view,
            .image_acquired = image_acquired_semaphore,
            .render_completed = render_completed_semaphore,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapImage, context: VkContext) void {
        self.waitForFrameFence(context) catch {
            std.log.err("SwapImage couldn't wait for fence!", .{});
            return;
        };
        context.vkd.destroyFence(context.device, self.frame_fence, null);
        context.vkd.destroySemaphore(context.device, self.render_completed, null);
        context.vkd.destroySemaphore(context.device, self.image_acquired, null);
        context.vkd.destroyImageView(context.device, self.image_view, null);
    }

    fn waitForFrameFence(self: SwapImage, context: VkContext) !void {
        _ = try context.vkd.waitForFences(context.device, 1, @ptrCast([*]const vk.Fence, &self.frame_fence), vk.TRUE, std.math.maxInt(u64));
    }
};

// @lifetime The caller owns the returned memory.
fn initSwapchainImages(context: VkContext, swapchain: vk.SwapchainKHR, format: vk.Format, allocator: Allocator) ![]SwapImage {
    var image_count: u32 = undefined;
    _ = try context.vkd.getSwapchainImagesKHR(context.device, swapchain, &image_count, null);

    const swapchain_images = try allocator.alloc(vk.Image, image_count);
    defer allocator.free(swapchain_images);
    _ = try context.vkd.getSwapchainImagesKHR(context.device, swapchain, &image_count, swapchain_images.ptr);

    const swap_images = try allocator.alloc(SwapImage, image_count);

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
    _ = framebuffer_size;

    return vk.Extent2D{
        .width = std.math.clamp(framebuffer_size.width, surface_capabilities.min_image_extent.width, surface_capabilities.max_image_extent.width),
        .height = std.math.clamp(framebuffer_size.height, surface_capabilities.min_image_extent.height, surface_capabilities.max_image_extent.height),
    };
}

/// Finds the best supported format and colors space for the surface.
/// Format: color channels and types (for example RGBA)
/// Color space: linear or non-linear (SRGB)
fn findSurfaceFormat(context: VkContext, allocator: Allocator) !vk.SurfaceFormatKHR {
    var surface_format_count: u32 = undefined;
    _ = try context.vki.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device, context.surface, &surface_format_count, null);

    const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, surface_format_count);
    defer allocator.free(surface_formats);
    _ = try context.vki.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device, context.surface, &surface_format_count, surface_formats.ptr);

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
fn findPresentMode(context: VkContext, allocator: Allocator) !vk.PresentModeKHR {
    var count: u32 = undefined;
    _ = try context.vki.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device, context.surface, &count, null);

    const available_present_modes = try allocator.alloc(vk.PresentModeKHR, count);
    defer allocator.free(available_present_modes);
    _ = try context.vki.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device, context.surface, &count, available_present_modes.ptr);

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
