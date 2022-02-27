const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

fn addShaders(b: *Builder, exe: *LibExeObjStep) void {
    const zigvulkan = @import("vendor/vulkan-zig/build.zig");

    const res = zigvulkan.ResourceGenStep.init(b, "resources.zig");
    res.addShader("tri_vert", "shaders/tri.vert");
    res.addShader("tri_frag", "shaders/tri.frag");
    exe.addPackage(res.package);
}

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("penguin-engine", "src/main.zig");
    // const exe = b.addExecutable("penguin-engine", "src/templ_main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    addGlfw(b, exe);
    addVulkanZig(b, exe);
    addShaders(b, exe);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn addGlfw(b: *Builder, exe: *LibExeObjStep) void {
    const glfw = @import("vendor/mach-glfw/build.zig");

    exe.addPackagePath("glfw", "vendor/mach-glfw/src/main.zig");
    glfw.link(b, exe, .{});
}

fn addVulkanZig(b: *Builder, exe: *LibExeObjStep) void {
    // generate bindings
    const vkgen = @import("vendor/vulkan-zig/generator/index.zig");

    const gen = vkgen.VkGenerateStep.init(b, "vendor/vulkan-zig/examples/vk.xml", "vk.zig");
    exe.addPackage(gen.package);
}
