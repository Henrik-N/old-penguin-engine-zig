const vk = @import("vulkan");

pub const BaseDispatch = vk.BaseWrapper(.{
    .createInstance = true,
    .enumerateInstanceLayerProperties = true,
});

pub const InstanceDispatch = vk.InstanceWrapper(.{
    .destroyInstance = true,
    .destroySurfaceKHR = true,
    .createDebugUtilsMessengerEXT = true,
    .destroyDebugUtilsMessengerEXT = true,
    .enumeratePhysicalDevices = true,
    .getPhysicalDeviceProperties = true,
    .enumerateDeviceExtensionProperties = true,
    .getPhysicalDeviceSurfaceFormatsKHR = true,
    .getPhysicalDeviceSurfaceSupportKHR = true,
    .getPhysicalDeviceSurfacePresentModesKHR = true,
    .getPhysicalDeviceSurfaceCapabilitiesKHR = true,
    .getPhysicalDeviceQueueFamilyProperties = true,
    .getDeviceProcAddr = true,
    .createDevice = true,
    .getPhysicalDeviceMemoryProperties = true,
    .getPhysicalDeviceFeatures = true,
    .getPhysicalDeviceFormatProperties = true,
});

pub const DeviceDispatch = vk.DeviceWrapper(.{
    .destroyDevice = true,
    .getDeviceQueue = true,
    .createSwapchainKHR = true,
    .destroySwapchainKHR = true,
    .getSwapchainImagesKHR = true,
    .createSemaphore = true,
    .destroySemaphore = true,
    .createFence = true,
    .destroyFence = true,
    .resetFences = true,
    .createImageView = true,
    .destroyImageView = true,
    .waitForFences = true,
    .createShaderModule = true,
    .destroyShaderModule = true,
    .createPipelineLayout = true,
    .destroyPipelineLayout = true,
    .createRenderPass = true,
    .destroyRenderPass = true,
    .createGraphicsPipelines = true,
    .destroyPipeline = true,
    .createFramebuffer = true,
    .destroyFramebuffer = true,
    .createCommandPool = true,
    .destroyCommandPool = true,
    .allocateCommandBuffers = true,
    .acquireNextImageKHR = true,
    .beginCommandBuffer = true,
    .endCommandBuffer = true,
    .resetCommandBuffer = true,
    .cmdBeginRenderPass = true,
    .cmdEndRenderPass = true,
    .queueSubmit = true,
    .queuePresentKHR = true,
    .cmdBindPipeline = true,
    .queueWaitIdle = true, // temp
    .deviceWaitIdle = true,
    .cmdDraw = true,
    .createBuffer = true,
    .destroyBuffer = true,
    .getBufferMemoryRequirements = true,
    .getBufferMemoryRequirements2 = true,
    .allocateMemory = true,
    .freeMemory = true,
    .bindBufferMemory = true,
    .mapMemory = true,
    .unmapMemory = true,
    .cmdBindVertexBuffers = true,
    //
    .freeCommandBuffers = true,
    .cmdSetViewport = true,
    .cmdSetScissor = true,
    .cmdCopyBuffer = true,
    .createImage = true,
    .destroyImage = true,
    .getImageMemoryRequirements = true,
    .bindImageMemory = true,
});
