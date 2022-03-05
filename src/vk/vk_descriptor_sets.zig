const vk = @import("vulkan");
const zk = @import("zulkan.zig");

const std = @import("std");
const VkContext = @import("VkContext.zig");
const vk_init = @import("vk_init.zig");

const Allocator = std.mem.Allocator;

const PoolEntry = struct {
    pool_type: vk.DescriptorType,
    multiplier: f32,
};

const pool_multipliers = [_]PoolEntry{
    .{ .pool_type = .uniform_buffer, .multiplier = 2.0 },
};

fn descriptorPoolSizes(count: usize) [pool_multipliers.len]vk.DescriptorPoolSize {
    var pool_sizes: [pool_multipliers.len]vk.DescriptorPoolSize = undefined;

    const count_f32 = @intToFloat(f32, count);

    inline for (pool_multipliers) |set, index| {
        pool_sizes[index] = .{
            .@"type" = set.pool_type,
            .descriptor_count = @floatToInt(u32, count_f32 * set.multiplier),
        };
    }

    return pool_sizes;
}

const DescriptorPoolStorage = struct {
    context: *const VkContext,
    used_pools: std.ArrayList(vk.DescriptorPool),
    free_pools: std.ArrayList(vk.DescriptorPool),

    const Self = @This();

    fn init(allocator: Allocator, context: *const VkContext) !Self {
        return Self{
            .context = context,
            .used_pools = try std.ArrayList(vk.DescriptorPool).initCapacity(allocator, 20),
            .free_pools = try std.ArrayList(vk.DescriptorPool).initCapacity(allocator, 20),
        };
    }

    fn deinit(self: Self) void {
        // destroy vulkan pools
        for (self.used_pools.items) |pool| self.context.destroyDescriptorPool(pool);
        for (self.free_pools.items) |pool| self.context.destroyDescriptorPool(pool);

        // free handles
        self.used_pools.deinit();
        self.free_pools.deinit();
    }

    fn reset(self: *Self) void {
        while (self.used_pools.popOrNull()) |used_pool| {
            self.context.resetCommandPool(used_pool, .{});

            try self.free_pools.append(used_pool);
        }
    }

    fn grabPool(self: *Self) !vk.DescriptorPool {
        // try to grab a free pool
        if (self.free_pools.popOrNull()) |pool| {
            try self.used_pools.append(pool);
            return pool;
        }

        const max_sets = 1000;
        const pool_sizes = descriptorPoolSizes(max_sets);

        // if there isn't any pool available, create a new one
        const descriptor_pool = try self.context.createDescriptorPool(.{
            .flags = .{},
            .max_sets = max_sets,
            .pool_sizes = &pool_sizes,
        });
        errdefer self.context.destroyDescriptorPool(descriptor_pool);

        try self.used_pools.append(descriptor_pool);

        return descriptor_pool;
    }
};

pub const DescriptorAllocator = struct {
    context: *const VkContext,
    current_pool: ?vk.DescriptorPool,
    pool_storage: DescriptorPoolStorage,

    const Self = @This();

    pub fn init(allocator: Allocator, context: *const VkContext) !Self {
        const storage = try DescriptorPoolStorage.init(allocator, context);

        return Self{
            .context = context,
            .current_pool = null,
            .pool_storage = storage,
        };
    }

    pub fn deinit(self: Self) void {
        self.pool_storage.deinit();
    }

    pub fn resetPools(self: Self) void {
        self.pool_storage.reset();
    }

    pub fn allocateDescriptorSet(self: *Self, layout: vk.DescriptorSetLayout) !vk.DescriptorSet {
        const current_pool = self.current_pool orelse try self.pool_storage.grabPool();

        const descriptor_set_first_try: ?vk.DescriptorSet = self.context.allocateDescriptorSet(current_pool, layout) catch |err| switch (err) {
            error.OutOfPoolMemory => null, // need new pool
            error.FragmentedPool => null, // need new pool
            else => return err, // unrecoverable error
        };

        if (descriptor_set_first_try) |descriptor_set| {
            return descriptor_set;
        }

        const new_pool = try self.pool_storage.grabPool();
        self.current_pool = new_pool;

        // if allocation to the new pool fails as well, something is probably quite wrong so we just propagate the error
        return try self.context.allocateDescriptorSet(new_pool, layout);
    }
};

const DescriptorLayoutKey = struct {
    bindings: std.ArrayList(vk.DescriptorSetLayoutBinding), // TODO stack array

    fn init(allocator: Allocator, bindings: []const vk.DescriptorSetLayoutBinding) !DescriptorLayoutKey {
        var bindings_list = try std.ArrayList(vk.DescriptorSetLayoutBinding).initCapacity(allocator, bindings.len);
        try bindings_list.appendSlice(bindings);

        return DescriptorLayoutKey{ .bindings = bindings_list };
    }

    fn deinit(self: DescriptorLayoutKey) void {
        self.bindings.deinit();
    }
};

const DescriptorLayoutHashContext = struct {
    const Self = @This();

    pub fn hash(self: Self, key: DescriptorLayoutKey) u64 {
        _ = self;

        var hasher = std.hash.Wyhash.init(0);

        for (key.bindings.items) |layout_binding| {
            const binding = layout_binding.binding;
            const desc_type = @intCast(u64, @enumToInt(layout_binding.descriptor_type));
            const desc_count = layout_binding.descriptor_count;
            const stage_flags = @intCast(u64, layout_binding.stage_flags.toInt());
            // TODO p_immutable_samplers, have to think about how to hash it as it's a pointer.
            // You can store data in the hash context, maybe add it here somehow?

            const binding_hash = binding | desc_type << 8 | desc_count << 16 | stage_flags << 24;

            std.hash.autoHash(&hasher, binding_hash);
        }

        return hasher.final();
    }

    pub fn eql(self: Self, key: DescriptorLayoutKey, other_key: DescriptorLayoutKey) bool {
        _ = self;

        if (key.bindings.items.len != other_key.bindings.items.len) {
            return false;
        }
        var i: usize = 0;
        while (i < key.bindings.items.len) : (i += 1) {
            const one = key.bindings.items[i];
            const two = other_key.bindings.items[i];

            if (one.binding != two.binding or
                one.descriptor_type != two.descriptor_type or
                one.descriptor_count != two.descriptor_count or
                one.stage_flags.toInt() != two.stage_flags.toInt())
                return false;

            if (one.p_immutable_samplers != null or two.p_immutable_samplers != null) {
                const warn_msg =
                    \\"DescriptorLayoutHashContext:\n
                    \\ Comparison and hashing for p_immutable_samplers is not implemented yet.
                    \\See comment in function 'hash'."
                ;

                std.log.warn(warn_msg, .{});
                return false;
            }
        }

        return true;
    }
};

pub const DescriptorLayoutCache = struct {
    const CacheType = std.HashMap(DescriptorLayoutKey, vk.DescriptorSetLayout, DescriptorLayoutHashContext, std.hash_map.default_max_load_percentage);

    allocator: Allocator,
    context: *const VkContext,
    cache: CacheType,

    const Self = @This();

    pub fn init(allocator: Allocator, context: *const VkContext) !Self {
        return Self{
            .allocator = allocator,
            .context = context,
            .cache = CacheType.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var cache_iter = self.cache.valueIterator();
        while (cache_iter.next()) |cached_layout| {
            self.context.destroyDescriptorSetLayout(cached_layout.*);
        }

        self.cache.deinit();
    }

    /// NOTE: The implementation assumes that the bindings given in zk.DescriptorSetLayouCreateInfo are ordered from lowest binding number to highest
    pub fn createDescriptorSetLayout(self: *Self, create_info: zk.DescriptorSetLayoutCreateInfo) !vk.DescriptorSetLayout {
        // construct key from bindings param
        var key = try DescriptorLayoutKey.init(self.allocator, create_info.bindings);
        errdefer key.deinit();

        for (create_info.bindings) |binding| {
            try key.bindings.append(binding);
        }

        // check if cache contains layout from key
        if (self.cache.get(key)) |layout| {
            return layout;
        }

        const descriptor_set_layout = try self.context.createDescriptorSetLayout(create_info);
        errdefer self.context.destroyDescriptorSetLayout(descriptor_set_layout);

        try self.cache.put(key, descriptor_set_layout);

        return descriptor_set_layout;
    }
};

pub const DescriptorBuilder = struct {
    layout_cache: *DescriptorLayoutCache,
    descriptor_allocator: *DescriptorAllocator,
    //
    layout_bindings: std.ArrayList(vk.DescriptorSetLayoutBinding),
    writes: std.ArrayList(vk.WriteDescriptorSet),

    const expected_max_bindings_count = 10;

    const Self = @This();

    pub fn init(allocator: Allocator, layout_cache: *DescriptorLayoutCache, descriptor_allocator: *DescriptorAllocator) !Self {
        return Self{
            .layout_cache = layout_cache,
            .descriptor_allocator = descriptor_allocator,
            .layout_bindings = try std.ArrayList(vk.DescriptorSetLayoutBinding).initCapacity(allocator, expected_max_bindings_count),
            .writes = try std.ArrayList(vk.WriteDescriptorSet).initCapacity(allocator, expected_max_bindings_count),
        };
    }

    pub fn deinit(self: *Self) void {
        self.layout_bindings.clearAndFree();
        self.writes.clearAndFree();
    }

    pub fn begin(self: *Self) *Self {
        // invalidate bindings and writes from previous use
        self.layout_bindings.clearRetainingCapacity();
        self.writes.clearRetainingCapacity();

        return self;
    }

    pub const BindBufferParams = struct {
        binding: u32,
        buffer_info: vk.DescriptorBufferInfo,
        descriptor_type: vk.DescriptorType,
        stage_flags: vk.ShaderStageFlags,
    };

    pub fn bindBuffer(self: *Self, params: BindBufferParams) !void {
        const layout_binding = vk.DescriptorSetLayoutBinding{
            .binding = params.binding,
            .descriptor_type = params.descriptor_type,
            .descriptor_count = 1,
            .stage_flags = params.stage_flags,
            .p_immutable_samplers = null,
        };

        try self.layout_bindings.append(layout_binding);

        if (params.descriptor_type == .inline_uniform_block_ext) {
            std.log.err(
                \\"Dst_binding is the strating element in array if descriptor_type == vk.DescriptorType.inline_uniform_block_ext.
                \\ If using this, descriptor_count specifies the number of bytes to update, and dst_array_element specifies the
                \\ starting element in the array. This implementation currently has not implemented a way of setting the starting element.
            , .{});
            return error.NonImplementedDescriptorType;
        }

        const descriptor_write = vk.WriteDescriptorSet{
            .dst_set = undefined, // set in build function
            .dst_binding = params.binding,
            .dst_array_element = 0,
            .descriptor_count = 1,
            .descriptor_type = params.descriptor_type,
            .p_image_info = undefined,
            .p_buffer_info = @ptrCast([*]const vk.DescriptorBufferInfo, &params.buffer_info),
            .p_texel_buffer_view = undefined,
        };

        try self.writes.append(descriptor_write);
    }

    pub fn bindImageBuffer(binding: u32, image_info: vk.DescriptorImageInfo, descriptor_type: vk.DescriptorType, stage_flags: vk.ShaderStageFlags) !void {
        _ = binding;
        _ = image_info;
        _ = descriptor_type;
        _ = stage_flags;
        return error.NotImplemented;
    }

    pub fn build(self: Self, context: VkContext, out_descriptor_set_layout: ?*vk.DescriptorSetLayout) !vk.DescriptorSet {
        const descriptor_set_layout = try self.layout_cache.createDescriptorSetLayout(.{
            .flags = .{},
            .bindings = self.layout_bindings.items,
        });

        if (out_descriptor_set_layout) |out_layout| {
            out_layout.* = descriptor_set_layout;
        }

        const descriptor_set = try self.descriptor_allocator.allocateDescriptorSet(descriptor_set_layout);

        for (self.writes.items) |*write_set| {
            write_set.dst_set = descriptor_set;
        }

        // set write data in the set
        try context.updateDescriptorSets(self.writes.items, &.{});

        return descriptor_set;
    }
};
