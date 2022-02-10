const glfw = @import("glfw");


pub fn main() !void {

    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(800, 600, "Penguin Engine", null, null, .{});
    defer window.destroy();

    while (!window.shouldClose()) {
        try glfw.pollEvents();


    }


}
