const std = @import("std");
const glfw = @import("glfw");
const vk = @import("vulkan");



pub fn main() !void {

    try glfw.init(.{});
    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };
    const app_name = "Penguin Engine";

    const window = try glfw.Window.create(extent.width, extent.height, app_name, null, null, .{
        .client_api = .no_api, // don't create an OpenGL context
    });
    defer window.destroy();


    var context = try VkContext.init(app_name);
    defer context.deinit();



    while (!window.shouldClose()) {
        try glfw.pollEvents();


    }
}


const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
});


const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
});


const alloc_callback: ?*const vk.AllocationCallbacks = null;


const VkContext = struct {
    vki: InstanceDispatch,
    instance: vk.Instance,

    fn init(app_name: [*:0]const u8) !VkContext {
        const vk_proc = @ptrCast(fn (instance: vk.Instance, procname: [*:0]const u8) callconv(.C) vk.PfnVoidFunction, glfw.getInstanceProcAddress);
        const base_dispatch = try BaseDispatch.load(vk_proc);

        const instance_extensions: [][*:0]const u8 = try glfw.getRequiredInstanceExtensions();

        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = vk.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = app_name,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0),
            .api_version = vk.API_VERSION_1_2             
        };

        const instance_create_info = vk.InstanceCreateInfo{
            .flags = .{},
            .p_application_info = &app_info,
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
            .enabled_extension_count = @intCast(u32, instance_extensions.len),
            .pp_enabled_extension_names = @ptrCast([*]const [*:0]const u8, &instance_extensions[0]),
        };

        const instance = try base_dispatch.createInstance(&instance_create_info, null);
        const instance_dispatch = try InstanceDispatch.load(instance, vk_proc);
        errdefer instance_dispatch.destroyInstance(instance, null);

        return VkContext{
            .vki = instance_dispatch,
            .instance = instance,
        };
    }

    fn deinit(self: *VkContext) void {
        self.vki.destroyInstance(self.instance, null);
    }
};
