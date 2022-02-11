const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");
const builtin = @import("builtin");

const isDebugModeEnabled: bool = builtin.mode == std.builtin.Mode.Debug;

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
});

const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .destroySurfaceKHR = true,
});

const VkContext = struct {
    vki: InstanceDispatch,
    instance: vk.Instance,
    surface: vk.SurfaceKHR,

    fn init(allocator: Allocator, app_name: [*:0]const u8, window: glfw.Window) !VkContext {
        const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfw.getInstanceProcAddress);
        const base_dispatch = try BaseDispatch.load(vk_proc);

        const required_layers = switch (isDebugModeEnabled) {
            true => [_][]const u8{"VK_LAYER_KHRONOS_validation"},
            false => [_][]const u8{},
        };

        if (!try areLayersSupported(allocator, base_dispatch, &required_layers)) {
            return error.VkRequiredLayersNotSupported;
        }

        const instance = try initInstance(base_dispatch, app_name, &required_layers);
        const instance_dispatch = try InstanceDispatch.load(instance, vk_proc);
        errdefer instance_dispatch.destroyInstance(instance, null);

        const surface = try initSurface(instance, window);
        errdefer instance_dispatch.destroySurfaceKHR(instance, surface, null);

        return VkContext{
            .vki = instance_dispatch,
            .instance = instance,
            .surface = surface,
        };
    }

    fn deinit(self: VkContext) void {
        self.vki.destroySurfaceKHR(self.instance, self.surface, null);
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

fn initInstance(vkb: BaseDispatch, app_name: [*:0]const u8, layers: []const []const u8) !vk.Instance {
    const instance_extensions: [][*:0]const u8 = try glfw.getRequiredInstanceExtensions();

    const app_info = vk.ApplicationInfo{ .p_application_name = app_name, .application_version = vk.makeApiVersion(0, 0, 0, 0), .p_engine_name = app_name, .engine_version = vk.makeApiVersion(0, 0, 0, 0), .api_version = vk.API_VERSION_1_2 };

    const instance_create_info = vk.InstanceCreateInfo{
        .flags = .{},
        .p_application_info = &app_info,
        .enabled_layer_count = @intCast(u32, layers.len),
        .pp_enabled_layer_names = @ptrCast([*]const [*:0]const u8, layers.ptr),
        .enabled_extension_count = @intCast(u32, instance_extensions.len),
        .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, instance_extensions.ptr),
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
