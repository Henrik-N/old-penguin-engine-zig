const std = @import("std");
const glfw = @import("glfw");
const m = @import("math.zig");

const Input = @This();

const DirectionalInputState = struct {
    x: i8,
    y: i8,

    fn inputAxis2D(self: Input) m.Vec2 {
        return m.init.vec2(@intToFloat(f32, self.x), @intToFloat(f32, self.y)).normalized(); // TODO normalize
    }
};
var input = DirectionalInputState{ .x = 0, .y = 0 }; // input state
var window: ?*const glfw.Window = undefined;

pub fn inputAxis2D() m.Vec2 {
    return input.inputAxis2D();
}

pub fn initInputState(window_: *const glfw.Window) void {
    window_.setKeyCallback(keyCallback);
    window = window_;
}

pub fn keyCallback(win: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
    _ = win;
    _ = scancode;
    _ = mods;

    if (action == .press) {
        if (key == .w) input.y += 1;
        if (key == .a) input.x -= 1;
        if (key == .s) input.y -= 1;
        if (key == .d) input.x += 1;
        if (key == .escape) if (window) |w| w.setShouldClose(true);
    } else if (action == .release) {
        if (key == .w) input.y -= 1;
        if (key == .a) input.x += 1;
        if (key == .s) input.y += 1;
        if (key == .d) input.x -= 1;
    }
}
