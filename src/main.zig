const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");

const is_debug_mode: bool = builtin.mode == std.builtin.Mode.Debug;

pub fn main() !void {
    try glfw.init(.{});
    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    const app_name = "Penguin Engine";

    const window = try glfw.Window.create(extent.width, extent.height, app_name, null, null, .{
        .client_api = .no_api, // don't create an OpenGL context
    });
    defer window.destroy();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const context = try VkContext.init(allocator, app_name, window);
    defer context.deinit();

    while (!window.shouldClose()) {
        try glfw.pollEvents();
    }
}

const Allocator = std.mem.Allocator;

const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceLayerProperties = true,
    //.debug_utils_messenger_create_info_ext = true,
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .destroySurfaceKHR = true,
    .createDebugUtilsMessengerEXT = true,
    .destroyDebugUtilsMessengerEXT = true,
});

const VkContext = struct {
    vki: InstanceDispatch,
    instance: vk.Instance,
    debug_messenger: ?vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,

    fn init(allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !VkContext {
        const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfw.getInstanceProcAddress);
        const base_dispatch = try BaseDispatch.load(vk_proc);

        const layers = switch (is_debug_mode) {
            true => [_][:0]const u8{"VK_LAYER_KHRONOS_validation"},
            false => [_][:0]const u8{},
        };

        if (!try areLayersSupported(allocator, base_dispatch, &layers)) {
            return error.VkRequiredLayersNotSupported;
        }

        const platform_extensions: [][*:0]const u8 = try glfw.getRequiredInstanceExtensions();
        const debug_extensions = [_][*:0]const u8{"VK_EXT_debug_utils"};
        const extensions: [][*:0]const u8 = try std.mem.concat(allocator, [*:0]const u8, &.{ platform_extensions, debug_extensions[0..] });
        defer allocator.destroy(&extensions);

        const instance = try initInstance(base_dispatch, app_name, layers[0..], extensions[0..]);
        const vki = try InstanceDispatch.load(instance, vk_proc);
        errdefer vki.destroyInstance(instance, null);

        const debug_messenger: ?vk.DebugUtilsMessengerEXT = switch (is_debug_mode) {
            true => try initDebugMessenger(vki, instance),
            false => null,
        };
        errdefer if (is_debug_mode) vki.destroyDebugUtilsMessengerEXT(instance, debug_messenger.?, null);

        const surface = try initSurface(instance, window);
        errdefer vki.destroySurfaceKHR(instance, surface, null);

        return VkContext{
            .vki = vki,
            .instance = instance,
            .debug_messenger = debug_messenger,
            .surface = surface,
        };
    }

    fn deinit(self: VkContext) void {
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

fn initInstance(vkb: BaseDispatch, app_name: [*:0]const u8, layers: []const []const u8, extensions: []const [*:0]const u8) !vk.Instance {
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
    _ = message_severity;
    _ = message_types;
    _ = p_callback_data;
    _ = p_user_data;

    if (p_callback_data) |callback_data| {
        std.log.warn("debug message: {s}", .{callback_data.p_message});
    }

    return vk.FALSE;
}

fn initDebugMessenger(vki: InstanceDispatch, instance: vk.Instance) !?vk.DebugUtilsMessengerEXT {
    const create_info = vk.DebugUtilsMessengerCreateInfoEXT{
        .flags = .{},
        .message_severity = .{
            .verbose_bit_ext = true,
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
