const vk = @import("vulkan");
const smath = @import("std").math;

// inspired by https://github.com/cshenton/learnopengl/blob/master/src/glm.zig

pub const Vec2 = Vector(2);
pub const Vec3 = Vector(3);
pub const Vec4 = Vector(4);

pub const Mat2 = Matrix(2);
pub const Mat3 = Matrix(3);
pub const Mat4 = Matrix(4);

fn Vector(comptime slot_count: usize) type {
    return extern struct {
        values: [slot_count]f32,

        const Self = @This();

        pub fn fill(fill_value: f32) Self {
            comptime var values: [slot_count]f32 = undefined;
            comptime var i = 0;

            inline while (i < values.len) : (i += 1) {
                values[i] = fill_value;
            }

            return Self{
                .values = values,
            };
        }

        pub fn zero() Self {
            return Self.fill(0);
        }

        pub fn one() Self {
            return Self.fill(1);
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

        pub fn sqNormalized(self: Self) f32 {
            return self.dot(self);
        }

        pub fn normalized(self: Self) f32 {
            return smath.sqrt(self.sqNormalized());
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

        pub fn y(self: Self) f32 {
            return self.values[1];
        }

        pub fn z(self: Self) f32 {
            comptime if (slot_count < 3) {
                @compileError("vector has no Z-component");
            };

            return self.values[2];
        }

        pub fn w(self: Self) f32 {
            comptime if (slot_count < 4) {
                @compileError("vector has no W-component");
            };

            return self.values[3];
        }
    };
}

// column major matrix
fn Matrix(comptime side_len: usize) type {
    return extern struct {
        values: [side_len][side_len]f32,

        const Self = @This();

        pub fn zero() Self {
            comptime var values_: [side_len][side_len]f32 = undefined;

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
            comptime var values_: [side_len][side_len]f32 = undefined;

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
