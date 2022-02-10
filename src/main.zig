const glfw = @import("glfw");
const vk = @import("vulkan");


pub fn main() !void {

    try glfw.init(.{});
    defer glfw.terminate();

    const extent = vk.Extent2D{ .width = 800, .height = 600 };

    const window = try glfw.Window.create(extent.width, extent.height, "Penguin Engine", null, null, .{});
    defer window.destroy();


    while (!window.shouldClose()) {
        try glfw.pollEvents();


    }


}
