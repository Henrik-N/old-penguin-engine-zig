const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const is_debug_mode: bool = builtin.mode == std.builtin.Mode.Debug;

const vk_dispatch = @import("vk_dispatch.zig");
const BaseDispatch = vk_dispatch.BaseDispatch;
const InstanceDispatch = vk_dispatch.InstanceDispatch;
const DeviceDispatch = vk_dispatch.DeviceDispatch;

const vk_mem = @import("vk_memory.zig");
const vk_enumerate = @import("vk_enumerate.zig");

const VkContext = @This();

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
upload_context: UploadContext,
//

pub fn init(allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !VkContext {
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

    // const instance = try VkInstance.init(app_name, allocator);
    // errdefer instance.deinit();

    const debug_messenger: ?vk.DebugUtilsMessengerEXT = switch (is_debug_mode) {
        true => try initDebugMessenger(instance, vki),
        false => null,
    };
    errdefer if (is_debug_mode) vki.destroyDebugUtilsMessengerEXT(instance, debug_messenger.?, null);

    const surface = try createSurface(instance, window);
    errdefer vki.destroyInstance(instance, null);

    const required_device_extensions = [_][*:0]const u8{vk.extension_info.khr_swapchain.name};
    const physical_device = try physical_device_selector.selectPhysicalDevice(instance, vki, surface, required_device_extensions[0..], allocator);

    const queue_family_indices = try QueueFamilyIndices.find(allocator, vki, physical_device, surface);

    const device = try initDevice(vki, physical_device, required_device_extensions[0..], queue_family_indices);
    const vkd = try DeviceDispatch.load(device, vki.dispatch.vkGetDeviceProcAddr);

    const graphics_queue = DeviceQueue.init(vkd, device, queue_family_indices.graphics);
    const present_queue = DeviceQueue.init(vkd, device, queue_family_indices.present);

    var self = VkContext{
        .vki = vki,
        .vkd = vkd,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
        .upload_context = undefined,
    };

    const upload_context = try UploadContext.init(self, graphics_queue);
    self.upload_context = upload_context;

    return self;
}

pub fn deinit(self: VkContext) void {
    self.upload_context.deinit(self);

    self.vkd.destroyDevice(self.device, null);
    self.vki.destroySurfaceKHR(self.instance, self.surface, null);
    if (self.debug_messenger) |debug_messenger| self.vki.destroyDebugUtilsMessengerEXT(self.instance, debug_messenger, null);
    self.vki.destroyInstance(self.instance, null);
}

pub fn immediateSubmitBegin(self: VkContext) !vk.CommandBuffer {
    return try self.upload_context.immediateSubmitBegin(self);
}

pub fn immediateSubmitEnd(self: VkContext) !void {
    try self.upload_context.immediateSubmitEnd(self);
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

const vk_cmd = @import("vk_cmd.zig");
const vk_sync = @import("vk_sync.zig");
const vk_init = @import("vk_init.zig");

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

fn areLayersSupported(allocator: Allocator, vkb: BaseDispatch, required_layers: []const []const u8) !bool {
    const available_layers = try vk_enumerate.enumerateInstanceLayerProperties(allocator, vkb);
    defer allocator.free(available_layers);

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

fn initDebugMessenger(instance: vk.Instance, vki: InstanceDispatch) !vk.DebugUtilsMessengerEXT {
    return try vki.createDebugUtilsMessengerEXT(instance, &.{
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
    }, null);
}

pub fn createSurface(instance: vk.Instance, window: glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    const result = try glfw.createWindowSurface(instance, window, null, &surface);

    if (result != @enumToInt(vk.Result.success)) {
        return error.SurfaceInitFailed;
    }

    return surface;
}

const physical_device_selector = struct {
    fn selectPhysicalDevice(
        instance: vk.Instance,
        vki: InstanceDispatch,
        surface: vk.SurfaceKHR,
        required_extensions: []const [*:0]const u8,
        allocator: Allocator,
    ) !vk.PhysicalDevice {
        const physical_devices = try vk_enumerate.enumeratePhysicalDevices(allocator, vki, instance);
        defer allocator.free(physical_devices);

        var highest_suitability_rating: i32 = -1;
        var highest_suitabliity_rating_index: ?usize = null;

        for (physical_devices) |pd, index| {
            ensureExtensionsSupported(vki, pd, required_extensions, allocator) catch continue;
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

    fn ensureExtensionsSupported(vki: InstanceDispatch, pd: vk.PhysicalDevice, extensions: []const [*:0]const u8, allocator: Allocator) !void {
        // enumerate extensions
        const pd_ext_props = try vk_enumerate.enumerateDeviceExtensionProperties(allocator, vki, pd);
        defer allocator.free(pd_ext_props);

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

    fn hasSurfaceSupport(vki: InstanceDispatch, pd: vk.PhysicalDevice, queue_family: u32, surface: vk.SurfaceKHR) !bool {
        return (try vki.getPhysicalDeviceSurfaceSupportKHR(pd, queue_family, surface)) == vk.TRUE;
    }

    fn find(allocator: Allocator, vki: InstanceDispatch, pd: vk.PhysicalDevice, surface: vk.SurfaceKHR) !QueueFamilyIndices {
        const family_properties = try vk_enumerate.getPhysicalDeviceQueueFamilyProperties(allocator, vki, pd);
        defer allocator.free(family_properties);

        var graphics_family: ?u32 = null;
        var present_family: ?u32 = null;

        for (family_properties) |family_props, index| {
            if (graphics_family == null and family_props.queue_flags.graphics_bit) {
                graphics_family = @intCast(u32, index);

                // Since we're currenly only using explicit sharing mode for queues in the swapchain if the queue families are the same,
                //  it's preferable to use the graphics queue as the present queue as well, if it has present support.
                // TODO This may change in the future, once the transfer between queues is explicit.
                const present_supported = try hasSurfaceSupport(vki, pd, graphics_family.?, surface);
                if (present_supported) {
                    present_family = graphics_family;
                    break;
                }
            }

            if (present_family == null and try hasSurfaceSupport(vki, pd, @intCast(u32, index), surface)) {
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

pub const UploadContext = struct {
    upload_fence: vk.Fence,
    command_pool: vk.CommandPool,
    command_buffer: vk.CommandBuffer,
    queue: DeviceQueue,

    const Self = @This();

    // TODO maybe use a transfer queue on a seperate thread in the future rather than the graphics queue
    fn init(context: VkContext, queue: DeviceQueue) !Self {
        const fence = try vk_init.fence(context, .{});

        const command_pool = try vk_init.commandPool(context, .{ .reset_command_buffer_bit = true }, queue.family);
        const command_buffer = try vk_init.commandBuffer(context, command_pool, .primary);

        return Self{
            .upload_fence = fence,
            .command_pool = command_pool,
            .command_buffer = command_buffer,
            .queue = queue,
        };
    }

    fn deinit(self: Self, context: VkContext) void {
        vk_init.destroyCommandPool(context, self.command_pool); // buffers get destroyed with the pool
        vk_init.destroyFence(context, self.upload_fence);
    }

    pub fn immediateSubmitBegin(self: Self, context: VkContext) !vk.CommandBuffer {
        try vk_cmd.beginCommandBuffer(context, self.command_buffer, .{ .one_time_submit_bit = true });

        return self.command_buffer;
    }

    pub fn immediateSubmitEnd(self: Self, context: VkContext) !void {
        const cmd_buf = self.command_buffer;

        try vk_cmd.endCommandBuffer(context, cmd_buf);

        const submit_info = vk.SubmitInfo{
            .wait_semaphore_count = 0,
            .p_wait_semaphores = undefined,
            .p_wait_dst_stage_mask = undefined,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast([*]const vk.CommandBuffer, &cmd_buf),
            .signal_semaphore_count = 0,
            .p_signal_semaphores = undefined,
        };

        try context.vkd.queueSubmit(self.queue.handle, 1, @ptrCast([*]const vk.SubmitInfo, &submit_info), self.upload_fence);

        try vk_sync.waitForFence(context, self.upload_fence);
        try vk_sync.resetFence(context, self.upload_fence);

        try context.vkd.resetCommandBuffer(self.command_buffer, .{});
    }
};
