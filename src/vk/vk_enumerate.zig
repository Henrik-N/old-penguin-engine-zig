const vk = @import("vulkan");
const VkContext = @import("VkContext.zig");

const vk_dispatch = @import("vk_dispatch.zig");
const BaseDispatch = vk_dispatch.BaseDispatch;
const InstanceDispatch = vk_dispatch.InstanceDispatch;

const Allocator = @import("std").mem.Allocator;

pub fn enumerateInstanceLayerProperties(allocator: Allocator, vkb: BaseDispatch) ![]vk.LayerProperties {
    var layer_count: u32 = undefined;
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, null);

    var available_layers: []vk.LayerProperties = try allocator.alloc(vk.LayerProperties, layer_count);
    errdefer allocator.free(available_layers);
    _ = try vkb.enumerateInstanceLayerProperties(&layer_count, @ptrCast([*]vk.LayerProperties, available_layers));

    return available_layers;
}

pub fn enumeratePhysicalDevices(allocator: Allocator, vki: InstanceDispatch, instance: vk.Instance) ![]vk.PhysicalDevice {
    var physical_device_count: u32 = undefined;
    _ = try vki.enumeratePhysicalDevices(instance, &physical_device_count, null);

    const physical_devices = try allocator.alloc(vk.PhysicalDevice, physical_device_count);
    errdefer allocator.free(physical_devices);
    _ = try vki.enumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr);

    return physical_devices;
}

pub fn enumerateDeviceExtensionProperties(allocator: Allocator, vki: InstanceDispatch, pd: vk.PhysicalDevice) ![]vk.ExtensionProperties {
    var ext_prop_count: u32 = undefined;
    _ = try vki.enumerateDeviceExtensionProperties(pd, null, &ext_prop_count, null);

    const pd_ext_props = try allocator.alloc(vk.ExtensionProperties, ext_prop_count);
    errdefer allocator.free(pd_ext_props);
    _ = try vki.enumerateDeviceExtensionProperties(pd, null, &ext_prop_count, pd_ext_props.ptr);

    return pd_ext_props;
}

pub fn getPhysicalDeviceQueueFamilyProperties(allocator: Allocator, vki: InstanceDispatch, pd: vk.PhysicalDevice) ![]vk.QueueFamilyProperties {
    var family_count: u32 = undefined;
    vki.getPhysicalDeviceQueueFamilyProperties(pd, &family_count, null);

    const family_properties = try allocator.alloc(vk.QueueFamilyProperties, family_count);
    errdefer allocator.free(family_properties);
    vki.getPhysicalDeviceQueueFamilyProperties(pd, &family_count, family_properties.ptr);

    return family_properties;
}

pub fn getPhysicalDeviceSurfaceFormatsKHR(allocator: Allocator, context: VkContext) ![]vk.SurfaceFormatKHR {
    var surface_format_count: u32 = undefined;
    _ = try context.vki.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device, context.surface, &surface_format_count, null);

    const surface_formats = try allocator.alloc(vk.SurfaceFormatKHR, surface_format_count);
    errdefer allocator.free(surface_formats);
    _ = try context.vki.getPhysicalDeviceSurfaceFormatsKHR(context.physical_device, context.surface, &surface_format_count, surface_formats.ptr);

    return surface_formats;
}

pub fn getPhysicalDeviceSurfacePresentModesKHR(allocator: Allocator, context: VkContext) ![]vk.PresentModeKHR {
    var count: u32 = undefined;
    _ = try context.vki.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device, context.surface, &count, null);

    const available_present_modes = try allocator.alloc(vk.PresentModeKHR, count);
    errdefer allocator.free(available_present_modes);
    _ = try context.vki.getPhysicalDeviceSurfacePresentModesKHR(context.physical_device, context.surface, &count, available_present_modes.ptr);

    return available_present_modes;
}

pub fn getSwapchainImagesKHR(allocator: Allocator, context: VkContext, swapchain: vk.SwapchainKHR) ![]vk.Image {
    var image_count: u32 = undefined;
    _ = try context.vkd.getSwapchainImagesKHR(context.device, swapchain, &image_count, null);

    const swapchain_images = try allocator.alloc(vk.Image, image_count);
    errdefer allocator.free(swapchain_images);
    _ = try context.vkd.getSwapchainImagesKHR(context.device, swapchain, &image_count, swapchain_images.ptr);

    return swapchain_images;
}
