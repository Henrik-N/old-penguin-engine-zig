const vk = @import("vulkan");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn new(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }
};

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn new(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }
};

// pub fn vkFormat(comptime T: type) ?vk.Format {
//     comptime if (T == Vec3) {
//         return vk.Format.r32g32b32_sfloat;
//     };
//
//     return null;
// }
