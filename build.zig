const std = @import("std");


pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("penguin-engine", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    addGlfw(b, exe);
    addVulkanZig(b, exe);



    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addGlfw(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const glfw = @import("vendor/mach-glfw/build.zig");

    exe.addPackagePath("glfw", "vendor/mach-glfw/src/main.zig");
    glfw.link(b, exe, .{});
}

fn addVulkanZig(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    // generate bindings
    const vkgen = @import("vendor/vulkan-zig/generator/index.zig");
    
    const gen = vkgen.VkGenerateStep.init(b, "vendor/vulkan-zig/examples/vk.xml", "vk.zig");
    exe.addPackage(gen.package);
}
