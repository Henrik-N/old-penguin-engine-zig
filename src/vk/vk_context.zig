const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");

const is_debug_mode: bool = builtin.mode == std.builtin.Mode.Debug;

const Allocator = std.mem.Allocator;

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceLayerProperties = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .destroySurfaceKHR = true,
    .createDebugUtilsMessengerEXT = true,
    .destroyDebugUtilsMessengerEXT = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getDeviceProcAddr = true,
    .createDevice = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getPhysicalDeviceFeatures = true,
});

const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .getSwapchainImagesKHR = true,
    .createSemaphore = true,
    .destroySemaphore = true,
    .createFence = true,
    .destroyFence = true,
    .resetFences = true,
    .createImageView = true,
    .destroyImageView = true,
    .waitForFences = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .acquireNextImageKHR = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .resetCommandBuffer = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .cmdBindPipeline = true,
    .queueWaitIdle = true, // temp
    .deviceWaitIdle = true,
    .cmdDraw = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .getBufferMemoryRequirements2 = true,
    .allocateMemory = true,
    .freeMemory = true,
});

pub const VkContext = struct {
    vki: InstanceDispatch,
    vkd: DeviceDispatch,
    //
    instance: vk.Instance,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    physical_device: vk.PhysicalDevice,
    device: vk.Device,
    //
    graphics_queue: DeviceQueue,
    present_queue: DeviceQueue,

    pub fn init(app_name: [*:0]const u8, window: glfw.Window, allocator: Allocator) !VkContext {
        const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfw.getInstanceProcAddress);
        const base_dispatch = try BaseDispatch.load(vk_proc);

        const instance_layers = switch (is_debug_mode) {
            true => [_][:0]const u8{"VK_LAYER_KHRONOS_validation"},
            false => [_][:0]const u8{},
        };

        if (!try areLayersSupported(allocator, base_dispatch, instance_layers[0..])) {
            return error.VkRequiredLayersNotSupported;
        }

        const platform_extensions: [][*:0]const u8 = try glfw.getRequiredInstanceExtensions();
        const debug_extensions = [_][*:0]const u8{vk.extension_info.ext_debug_utils.name};
        const instance_extensions: [][*:0]const u8 = try std.mem.concat(allocator, [*:0]const u8, &.{ platform_extensions, debug_extensions[0..] });
        defer allocator.free(instance_extensions);

        const instance = try initInstance(base_dispatch, app_name, instance_layers[0..], instance_extensions[0..]);
        const vki = try InstanceDispatch.load(instance, vk_proc);
        errdefer vki.destroyInstance(instance, null);

        const debug_messenger: ?vk.DebugUtilsMessengerEXT = switch (is_debug_mode) {
            true => try initDebugMessenger(vki, instance),
            false => null,
        };
        errdefer if (is_debug_mode) vki.destroyDebugUtilsMessengerEXT(instance, debug_messenger.?, null);

        const surface = try initSurface(instance, window);
        errdefer vki.destroySurfaceKHR(instance, surface, null);

        const required_device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};
        const physical_device = try physical_device_selector.selectPhysicalDevice(vki, instance, allocator, surface, required_device_extensions[0..]);

        const queue_family_indices = try QueueFamilyIndices.find(vki, physical_device, surface, allocator);

        const device = try initDevice(vki, physical_device, required_device_extensions[0..], queue_family_indices);
        const vkd = try DeviceDispatch.load(device, vki.dispatch.vkGetDeviceProcAddr);
        errdefer vkd.destroyDevice(device, null);

        const graphics_queue = DeviceQueue.init(vkd, device, queue_family_indices.graphics);
        const present_queue = DeviceQueue.init(vkd, device, queue_family_indices.present);

        return VkContext{
            .vki = vki,
            .vkd = vkd,
            .instance = instance,
            .debug_messenger = debug_messenger,
            .surface = surface,
            .physical_device = physical_device,
            .device = device,
            .graphics_queue = graphics_queue,
            .present_queue = present_queue,
        };
    }

    pub fn deinit(self: VkContext) void {
        self.vkd.destroyDevice(self.device, null);
        self.vki.destroySurfaceKHR(self.instance, self.surface, null);
        if (self.debug_messenger) |debug_messenger| self.vki.destroyDebugUtilsMessengerEXT(self.instance, debug_messenger, null);
        self.vki.destroyInstance(self.instance, null);
    }
};

fn areLayersSupported(allocator: Allocator, vkb: BaseDispatch, required_layers: []const []const u8) !bool {
    var layer_count: u32 = undefined;
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, null);

    var available_layers: []vk.LayerProperties = try allocator.alloc(vk.LayerProperties, layer_count);
    defer allocator.free(available_layers);
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, @ptrCast([*]vk.LayerProperties, available_layers));

    var matches: usize = 0;
    for (required_layers) |required_layer| {
        for (available_layers) |available_layer| {
            const available_layer_slice: []const u8 = std.mem.span(@ptrCast([*:0]const u8, &available_layer.layer_name));

            if (std.mem.eql(u8, available_layer_slice, required_layer)) {
                matches += 1;
            }
        }
    }

    return matches == required_layers.len;
}

fn initInstance(vkb: BaseDispatch, app_name: [*:0]const u8, layers: []const [:0]const u8, extensions: []const [*:0]const u8) !vk.Instance {
    const app_info = vk.ApplicationInfo{ .p_application_name = app_name, .application_version = vk.makeApiVersion(0, 0, 0, 0), .p_engine_name = app_name, .engine_version = vk.makeApiVersion(0, 0, 0, 0), .api_version = vk.API_VERSION_1_2 };

    const instance_create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(u32, layers.len),
        .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.ptr),
        .enabled_extension_count = @intCast(u32, extensions.len),
        .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, extensions.ptr),
    };

    const instance = try vkb.createInstance(&instance_create_info, null);
    return instance;
}

fn initSurface(instance: vk.Instance, window: glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    const result = try glfw.createWindowSurface(instance, window, null, &surface);

    if (result != @enumToInt(vk.Result.success)) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

fn debugMessengerCallback(
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT.IntType,
    message_types: vk.DebugUtilsMessageSeverityFlagsEXT.IntType,
    p_callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(vk.vulkan_call_conv) vk.Bool32 {
    _ = message_types;
    _ = p_user_data;

    if (p_callback_data) |callback_data| {
        const severity = vk.DebugUtilsMessageSeverityFlagsEXT.fromInt(message_severity);
        const prefix = "[VK_VALIDATION]: ";
        const msg = callback_data.p_message;

        if (severity.contains(.{ .info_bit_ext = true })) {
            std.log.info("{s}{s}", .{ prefix, msg });
        } else if (severity.contains(.{ .warning_bit_ext = true })) {
            std.log.warn("{s}{s}", .{ prefix, msg });
        } else if (severity.contains(.{ .error_bit_ext = true })) {
            std.log.err("{s}{s}", .{ prefix, msg });
        } else {
            std.log.err("(Unknown severity) {s}{s}", .{ prefix, callback_data.p_message });
        }
    }

    return vk.FALSE;
}

fn initDebugMessenger(vki: InstanceDispatch, instance: vk.Instance) !?vk.DebugUtilsMessengerEXT {
    const create_info = vk.DebugUtilsMessengerCreateInfoEXT{
        .flags = .{},
        .message_severity = .{
            // .verbose_bit_ext = true,
            .info_bit_ext = true,
            .warning_bit_ext = true,
            .error_bit_ext = true,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
        },
        .pfn_user_callback = debugMessengerCallback,
        .p_user_data = null,
    };

    return try vki.createDebugUtilsMessengerEXT(instance, &create_info, null);
}

const physical_device_selector = struct {
    fn selectPhysicalDevice(
        vki: InstanceDispatch,
        instance: vk.Instance,
        allocator: Allocator,
        surface: vk.SurfaceKHR,
        required_extensions: []const [*:0]const u8,
    ) !vk.PhysicalDevice {
        var physical_device_count: u32 = undefined;
        _ = try vki.enumeratePhysicalDevices(instance, &physical_device_count, null);

        const physical_devices = try allocator.alloc(vk.PhysicalDevice, physical_device_count);
        defer allocator.free(physical_devices);
        _ = try vki.enumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr);

        var highest_suitability_rating: i32 = -1;
        var highest_suitabliity_rating_index: ?usize = null;

        for (physical_devices) |pd, index| {
            ensureExtensionsSupported(vki, pd, allocator, required_extensions) catch continue;
            ensureHasSurfaceSupport(vki, pd, surface) catch continue;

            const props = vki.getPhysicalDeviceProperties(pd);

            const suitability_rating: i32 = switch (props.device_type) {
                .virtual_gpu => 0,
                .integrated_gpu => 1,
                .discrete_gpu => 2,
                else => -1,
            };

            if (suitability_rating > highest_suitability_rating) {
                highest_suitability_rating = suitability_rating;
                highest_suitabliity_rating_index = index;
            }
        }

        if (highest_suitabliity_rating_index) |index| {
            const selected_pd = physical_devices[index];
            std.log.info("Using physical device: {s}", .{vki.getPhysicalDeviceProperties(selected_pd).device_name});
            return selected_pd;
        } else {
            return error.NoSuitableDevice;
        }
    }

    fn ensureExtensionsSupported(vki: InstanceDispatch, pd: vk.PhysicalDevice, allocator: Allocator, extensions: []const [*:0]const u8) !void {
        // enumerate extensions
        var ext_prop_count: u32 = undefined;
        _ = try vki.enumerateDeviceExtensionProperties(pd, null, &ext_prop_count, null);

        const pd_ext_props = try allocator.alloc(vk.ExtensionProperties, ext_prop_count);
        defer allocator.free(pd_ext_props);
        _ = try vki.enumerateDeviceExtensionProperties(pd, null, &ext_prop_count, pd_ext_props.ptr);

        // check if required extensions are in the physical device's list of supported extensions
        for (extensions) |required_ext_name| {
            for (pd_ext_props) |pd_ext| {
                const pd_ext_name = @ptrCast([*:0]const u8, &pd_ext.extension_name);

                if (std.mem.eql(u8, std.mem.span(required_ext_name), std.mem.span(pd_ext_name))) {
                    break;
                }
            } else {
                return error.ExtensionsNotSupported;
            }
        }
    }

    fn ensureHasSurfaceSupport(vki: InstanceDispatch, pd: vk.PhysicalDevice, surface: vk.SurfaceKHR) !void {
        var format_count: u32 = undefined;
        _ = try vki.getPhysicalDeviceSurfaceFormatsKHR(pd, surface, &format_count, null);

        var present_mode_count: u32 = undefined;
        _ = try vki.getPhysicalDeviceSurfacePresentModesKHR(pd, surface, &present_mode_count, null);

        if (format_count < 1 or present_mode_count < 1) {
            return error.NoSurfaceSupport;
        }
    }
};

const QueueFamilyIndices = struct {
    graphics: u32,
    present: u32,

    fn find(vki: InstanceDispatch, pd: vk.PhysicalDevice, surface: vk.SurfaceKHR, allocator: Allocator) !QueueFamilyIndices {
        var family_count: u32 = undefined;
        vki.getPhysicalDeviceQueueFamilyProperties(pd, &family_count, null);

        const family_properties = try allocator.alloc(vk.QueueFamilyProperties, family_count);
        defer allocator.free(family_properties);
        vki.getPhysicalDeviceQueueFamilyProperties(pd, &family_count, family_properties.ptr);

        var graphics_family: ?u32 = null;
        var present_family: ?u32 = null;

        for (family_properties) |family_props, index| {
            if (graphics_family == null and family_props.queue_flags.graphics_bit) {
                graphics_family = @intCast(u32, index);

                // Since we're currenly only using explicit sharing mode for queues in the swapchain if the queue families are the same,
                //  it's preferable to use the graphics queue as the present queue as well, if it has present support.
                // TODO This may change in the future, once the transfer between queues is explicit.
                const present_supported = vk.TRUE == try vki.getPhysicalDeviceSurfaceSupportKHR(pd, graphics_family.?, surface);
                if (present_supported) {
                    present_family = graphics_family;
                    break;
                }
            }

            if (present_family == null and (try vki.getPhysicalDeviceSurfaceSupportKHR(pd, @intCast(u32, index), surface)) == vk.TRUE) {
                present_family = @intCast(u32, index);
            }
        }

        if (graphics_family == null or present_family == null) {
            return error.CouldNotFindQueueFamilies;
        }

        return QueueFamilyIndices{
            .graphics = graphics_family.?,
            .present = present_family.?,
        };
    }
};

fn initDevice(vki: InstanceDispatch, pd: vk.PhysicalDevice, device_extensions: []const [*:0]const u8, queue_family_indices: QueueFamilyIndices) !vk.Device {
    const queue_priority = [_]f32{1};
    const queues_create_info = [_]vk.DeviceQueueCreateInfo{ .{
        .flags = .{},
        .queue_family_index = queue_family_indices.graphics,
        .queue_count = 1,
        .p_queue_priorities = &queue_priority,
    }, .{
        .flags = .{},
        .queue_family_index = queue_family_indices.present,
        .queue_count = 1,
        .p_queue_priorities = &queue_priority,
    } };

    const queue_count: u32 = if (queue_family_indices.graphics == queue_family_indices.present) 1 else 2;

    std.log.info("device extensions count: {}", .{device_extensions.len});

    for (device_extensions) |ext| {
        std.log.info("required device extensions: {s}", .{ext});
    }

    const create_info = vk.DeviceCreateInfo{
        .flags = .{},
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &queues_create_info,
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
        .enabled_extension_count = @intCast(u32, device_extensions.len),
        .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, device_extensions.ptr),
        .p_enabled_features = null,
    };

    return try vki.createDevice(pd, &create_info, null);
}

pub const DeviceQueue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(vkd: DeviceDispatch, device: vk.Device, family: u32) DeviceQueue {
        return .{
            .handle = vkd.getDeviceQueue(device, family, 0),
            .family = family,
        };
    }
};
