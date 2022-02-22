const std = @import("std");
const vk = @import("vulkan");
const glfw = @import("glfw");
const VkContext = @import("vk_context.zig").VkContext;
const vk_init = @import("vk_init.zig");

const Allocator = std.mem.Allocator;

const vk_memory = @import("vk_memory.zig");

const max_frames_in_flight: usize = 2;
const max_timeout = std.math.maxInt(u64);


pub const Swapchain = struct {
    handle: vk.SwapchainKHR,
    surface_format: vk.SurfaceFormatKHR,
    extent: vk.Extent2D,
    //
    images: []SwapImage,
    current_image_index: usize,
    // Semaphore that will get signaled once we've gotten the next image from the swapchain.
    // We signal this when getting the image and then set it as the semaphore for the current image.
    next_image_acquired_semaphore: vk.Semaphore, 

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
        var next_image_acquired_semaphore = try vk_init.semaphore(context);
        errdefer context.vkd.destroySemaphore(context.device, next_image_acquired_semaphore, null);

        const result = try context.vkd.acquireNextImageKHR(
            context.device, 
            swapchain, 
            max_timeout, 
            next_image_acquired_semaphore,
            .null_handle
        );

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

        return Swapchain{
            .handle = swapchain,
            .surface_format = surface_format,
            .extent = true_extent,
            .images = images,
            .current_image_index = 0,
            .next_image_acquired_semaphore = next_image_acquired_semaphore,
        };
    }


    pub fn deinit(self: Swapchain, context: VkContext, allocator: Allocator) void {
        for (self.images) |image| image.deinit(context);
        allocator.free(self.images);
        context.vkd.destroySemaphore(context.device, self.next_image_acquired_semaphore, null);
        context.vkd.destroySwapchainKHR(context.device, self.handle, null);
    }

    pub fn currentImage(self: Swapchain) *const SwapImage {
        return &self.images[self.current_image_index];
    }

    pub fn submitPresentCommandBuffer(self: *Swapchain, context: VkContext, command_buffer: vk.CommandBuffer) !void {
        // Ensure this frame has finished being rendered to the screen (if not, wait for it to finish).
        const current_image: *const SwapImage = self.currentImage();
        try current_image.waitForRenderFrameFence(context); // wait for signal from fence saying that the rendering is complete
        try context.vkd.resetFences(context.device, 1, @ptrCast([*]const vk.Fence, &current_image.render_frame_fence)); // reset fence to unsignaled state

        // Submit command buffer to graphics queue
        //
        
        // Ensure render passes don't begin until the image is available.
        // TODO It may be faster to wait for the color attachment output stage in the render pass instead, through using a subpass dependency.
        const wait_stage = [_]vk.PipelineStageFlags{ .{ .top_of_pipe_bit = true }}; // TODO: color attachment bit?

        try context.vkd.queueSubmit(context.graphics_queue.handle, 1, &[_]vk.SubmitInfo{.{
            // wait for image acquisition before executing this command buffer
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &current_image.image_acquired_semaphore),
            .p_wait_dst_stage_mask = &wait_stage,
            //
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &command_buffer),
            // signal render finished semaphore
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast([*]const vk.Semaphore, &current_image.render_completed_semaphore),
        }}, current_image.render_frame_fence);

        // Present queue
        // 
        _ = try context.vkd.queuePresentKHR(context.present_queue.handle, &.{
            // wait until rendering is complete
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast([*]const vk.Semaphore, &current_image.render_completed_semaphore),
            // present image at current index
            .swapchain_count = 1,
            .p_swapchains = @ptrCast([*]const vk.SwapchainKHR, &self.handle),
            .p_image_indices = @ptrCast([*]const u32, &self.current_image_index),
            .p_results = null,
        });

        // acquire next image
        //
        const result = try context.vkd.acquireNextImageKHR(
            context.device, 
            self.handle, 
            max_timeout, 
            self.next_image_acquired_semaphore, 
            .null_handle
        );
        self.current_image_index = result.image_index;

        switch (result.result) {
            .suboptimal_khr => std.log.debug("swapchain suboptimal", .{}),
            .error_out_of_date_khr => std.log.debug("swapchain out of date", .{}),
            else => {},
        }

        std.mem.swap(vk.Semaphore, &self.images[self.current_image_index].image_acquired_semaphore, &self.next_image_acquired_semaphore);
    }
};

pub const SwapImage = struct {
    image: vk.Image,
    image_view: vk.ImageView,
    image_acquired_semaphore: vk.Semaphore,
    render_completed_semaphore: vk.Semaphore,
    render_frame_fence: vk.Fence, // signaled when the frame has finished rendering

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

        const image_acquired_semaphore = try vk_init.semaphore(context);
        errdefer context.vkd.destroySemaphore(context.device, image_acquired_semaphore, null);

        const render_completed_semaphore = try vk_init.semaphore(context);
        errdefer context.vkd.destroySemaphore(context.device, render_completed_semaphore, null);

        const render_frame_fence = try vk_init.fence(context, .{ .signaled_bit = true });
        errdefer context.vkd.destroyFence(context.device, render_frame_fence, null);

        return SwapImage{
            .image = image,
            .image_view = image_view,
            .image_acquired_semaphore = image_acquired_semaphore,
            .render_completed_semaphore = render_completed_semaphore,
            .render_frame_fence = render_frame_fence,
        };
    }

    fn deinit(self: SwapImage, context: VkContext) void {
        self.waitForRenderFrameFence(context) catch {
            std.log.err("SwapImage couldn't wait for fence!", .{});
            return;
        };
        context.vkd.destroyFence(context.device, self.render_frame_fence, null);
        context.vkd.destroySemaphore(context.device, self.render_completed_semaphore, null);
        context.vkd.destroySemaphore(context.device, self.image_acquired_semaphore, null);
        context.vkd.destroyImageView(context.device, self.image_view, null);
    }

    fn waitForRenderFrameFence(self: SwapImage, context: VkContext) !void {
        const timeout = std.math.maxInt(u64);
        _ = try context.vkd.waitForFences(context.device, 1, @ptrCast([*]const vk.Fence, &self.render_frame_fence), vk.TRUE, timeout);
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
