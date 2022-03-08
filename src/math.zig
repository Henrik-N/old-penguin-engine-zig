const vk = @import("vulkan");
const std = @import("std");
const smath = std.math;

// Thanks to https://github.com/cshenton/learnopengl/blob/master/src/glm.zig for the inspiration.

pub const Vec2 = Vector(2);
pub const Vec3 = Vector(3);
pub const Vec4 = Vector(4);

pub const Mat2 = Matrix(2);
pub const Mat3 = Matrix(3);
pub const Mat4 = Matrix(4);

pub const cos = smath.cos;
pub const sin = smath.sin;
pub const pi = smath.pi;
pub const tau = smath.pi * 2.0;

pub fn vec2(x: f32, y: f32) Vec2 {
    return Vec2{ .values = .{ x, y } };
}

pub fn vec3(x: f32, y: f32, z: f32) Vec3 {
    return Vec3{ .values = .{ x, y, z } };
}

pub fn vec4(x: f32, y: f32, z: f32, w: f32) Vec4 {
    return Vec4{ .values = .{ x, y, z, w } };
}

pub fn translation(t: Vec3) Mat4 {
    return Mat4{
        .values = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ t.x(), t.y(), t.z(), 1 },
        },
    };
}

pub fn scale(s: Vec3) Mat4 {
    return Mat4{
        .values = .{
            .{ s.x(), 0, 0, 0 },
            .{ 0, s.y(), 0, 0 },
            .{ 0, 0, s.z(), 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub fn degs(rads_: f32) f32 {
    return rads_ * (180.0 / pi);
}

pub fn rads(degs_: f32) f32 {
    return degs_ * (pi / 180.0);
}

pub fn rotX(radians: f32) Mat4 {
    return .{
        .values = .{
            .{ 1, 0, 0, 0 },
            .{ 0, cos(radians), -sin(radians), 0 },
            .{ 0, sin(radians), cos(radians), 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub fn rotY(radians: f32) Mat4 {
    return .{
        .values = .{
            .{ cos(radians), 0, sin(radians), 0 },
            .{ 0, 1, 0, 0 },
            .{ -sin(radians), 0, cos(radians), 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub fn rotZ(radians: f32) Mat4 {
    return .{
        .values = .{
            .{ cos(radians), -sin(radians), 0, 0 },
            .{ sin(radians), cos(radians), 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

// angle in radians
pub fn rotAroundAxis(rangle: f32, axis: Vec3) Mat4 {
    const axis_unit = axis.normalized();
    const x = axis_unit.x();
    const y = axis_unit.y();
    const z = axis_unit.z();

    const cos_a = cos(rangle);
    const sin_a = sin(rangle);
    const om_cos_a = (1 - cos_a);

    const x0 = cos_a - (x * x * om_cos_a);
    const y0 = (y * x * om_cos_a) + (z * sin_a);
    const z0 = (z * x * om_cos_a) - (y * sin_a);

    const x1 = (x * y * om_cos_a) - (z * sin_a);
    const y1 = cos_a - (y * y * om_cos_a);
    const z1 = (z * y * om_cos_a) + (x * sin_a);

    const x2 = (x * z * om_cos_a) + (y * sin_a);
    const y2 = (y * z * om_cos_a) - (x * sin_a);
    const z2 = cos_a + z * z * om_cos_a;

    return .{
        .values = .{
            .{ x0, y0, z0, 0 },
            .{ x1, y1, z1, 0 },
            .{ x2, y2, z2, 0 },
            .{ 0, 0, 0, 1 },
        },
    };
}

pub const PerspectiveProjectionMat4Params = struct {
    fovy: f32, // radians
    aspect_ratio: f32,
    z_near: f32,
    z_far: f32,
};

fn Vector(comptime slot_count: usize) type {
    return extern struct {
        values: [slot_count]f32,

        const Self = @This();

        pub const zero = Self.fill(0);
        pub const one = Self.fill(1);

        pub fn fill(fill_value: f32) Self {
            var values: [slot_count]f32 = undefined;
            comptime var i = 0;

            inline while (i < values.len) : (i += 1) {
                values[i] = fill_value;
            }

            return Self{
                .values = values,
            };
        }

        fn simd(self: Self) @Vector(slot_count, f32) {
            const self_values: @Vector(slot_count, f32) = self.values;
            return self_values;
        }

        pub fn add(self: Self, other: Self) Self {
            return Self{ .values = self.simd() + other.simd() };
        }

        pub fn sub(self: Self, other: Self) Self {
            return Self{ .values = self.simd() - other.simd() };
        }

        pub fn mul(self: Self, other: Self) Self {
            return Self{ .values = self.simd() * other.simd() };
        }

        pub fn mulScalar(self: Self, scalar: f32) Self {
            return Self{ .values = self.simd() * Self.fill(scalar).simd() };
        }

        pub fn div(self: Self, other: Self) Self {
            return Self{ .values = self.simd() / other.simd() };
        }

        /// the sum of all the values in the vector
        pub fn sum(self: Self) f32 {
            var sum_: f32 = 0;
            for (self.values) |value| {
                sum_ += value;
            }
            return sum_;
        }

        pub fn dot(self: Self, other: Self) f32 {
            const product = self.mul(other);
            return product.sum();
        }

        pub fn sqMagnitude(self: Self) f32 {
            const vec = self.mul(self);
            return vec.sum();
        }

        pub fn magnitude(self: Self) f32 {
            return smath.sqrt(self.sqMagnitude());
        }

        pub fn normalized(self: Self) Self {
            var mag = self.magnitude();
            if (mag == 0) mag = 1;

            return self.mulScalar(1 / mag);
        }

        pub fn cross(self: Self, other: Self) Self {
            comptime if (slot_count != 3) {
                @compileError("cross product is only defined for 3-dimensional vectors");
            };

            const values = [_]f32{
                self.values[1] * other.values[2] - self.values[2] * other.values[1],
                self.values[2] * other.values[0] - self.values[0] * other.values[2],
                self.values[0] * other.values[1] - self.values[1] * other.values[0],
            };

            return Self{
                .values = values,
            };
        }

        pub fn x(self: Self) f32 {
            return self.values[0];
        }

        pub fn setX(self: *Self, val: f32) void {
            self.values[0] = val;
        }

        pub fn y(self: Self) f32 {
            return self.values[1];
        }

        pub fn setY(self: *Self, val: f32) void {
            self.values[1] = val;
        }

        pub fn z(self: Self) f32 {
            comptime if (slot_count < 3) {
                @compileError("vector has no Z-component");
            };

            return self.values[2];
        }

        pub fn setZ(self: *Self, val: f32) void {
            comptime if (slot_count < 3) {
                @compileError("vector has no Z-component");
            };

            self.values[2] = val;
        }

        pub fn w(self: Self) f32 {
            comptime if (slot_count < 4) {
                @compileError("vector has no W-component");
            };

            return self.values[3];
        }

        pub fn setW(self: *Self, val: f32) void {
            comptime if (slot_count < 4) {
                @compileError("vector has no W-component");
            };

            self.values[3] = val;
        }
    };
}

/// column major matrix
fn Matrix(comptime side_len: usize) type {
    return extern struct {
        values: [side_len][side_len]f32,

        const Self = @This();

        pub fn zero() Self {
            var values_: [side_len][side_len]f32 = undefined;

            comptime var i = 0;
            inline while (i < side_len) : (i += 1) {
                comptime var k = 0;
                inline while (k < side_len) : (k += 1) {
                    values_[i][k] = 0;
                }
            }

            return Self{ .values = values_ };
        }

        pub fn identity() Self {
            var values_: [side_len][side_len]f32 = undefined;

            comptime var i = 0;
            inline while (i < side_len) : (i += 1) {
                comptime var k = 0;
                inline while (k < side_len) : (k += 1) {
                    values_[i][k] = if (i == k) 1 else 0;
                }
            }

            return Self{ .values = values_ };
        }

        pub fn transpose(self: Self) Self {
            var values_: [side_len][side_len]f32 = undefined;

            comptime var i = 0;
            inline while (i < side_len) : (i += 1) {
                comptime var k = 0;
                inline while (k < side_len) : (k += 1) {
                    values_[i][k] = self.values[k][i];
                }
            }

            return Self{ .values = values_ };
        }

        pub fn mul(self: Self, other: Self) Self {
            var values_: [side_len][side_len]f32 = undefined;

            const a = self.transpose();
            const b = other;

            comptime var i = 0;
            inline while (i < side_len) : (i += 1) {
                comptime var k = 0;
                inline while (k < side_len) : (k += 1) {
                    const row: @Vector(side_len, f32) = a.values[k];
                    const col: @Vector(side_len, f32) = b.values[i];
                    const products: [side_len]f32 = row * col;

                    var sum: f32 = 0;
                    for (products) |product| {
                        sum += product;
                    }

                    values_[i][k] = sum;
                }
            }

            return Self{ .values = values_ };
        }
    };
}
