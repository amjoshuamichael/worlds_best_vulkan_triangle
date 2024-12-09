package triangle

import "core:c"
import "core:fmt"
import "core:slice"
import "base:intrinsics"
import vk "idiomatic_odin_vulkan_bindings"
import sdl "vendor:sdl2"

Graphics_Resources :: struct {
    swapchain: Swapchain,
    instance: vk.Instance,
    surface: vk.Surface,
    queue_indices: [Queue_Family]u32,
    queues: [Queue_Family]vk.Queue,
    command_pools: [Queue_Family]vk.Command_Pool,
    device: vk.Device,
    vertex_buffer: Buffer(Vertex),
    pipelines: [GPU_Pipeline_ID]Pipeline,
    graphics_cmd_buffer: vk.Command_Buffer,
    pipeline_cache: vk.Pipeline_Cache,

    transfer_cmd_buffer: vk.Command_Buffer,
    transfer_fence: vk.Fence,
}

Queue_Family :: enum {
    Graphics,
    Transfer,
}

// These static variables are set once, and never changed... it's helpful to
// have this data around for various purposes.
physical_device: vk.Physical_Device
physical_device_info: Physical_Device_Info

Swapchain :: struct {
    window: ^sdl.Window,
    surface_capabilities: vk.Surface_Capabilities,
    handle: vk.Swapchain,
    present_mode: vk.Present_Mode,
    format: vk.Surface_Format,
    image_count: u32,
    image_index: u32,
    // We use #soa so that we can have the vulkan API write directly into the
    // array of images.
    images: #soa []Swapchain_Item,
    point_width, point_height, pixel_width, pixel_height: c.int,
}

Swapchain_Item :: struct {
    image: vk.Image,
    view: vk.Image_View,
    framebuffer: vk.Framebuffer,
    image_available: vk.Semaphore,
    render_finished: vk.Semaphore,
    fence_in_flight: vk.Fence,
}

// Certain validation layers impose considerable overhead. Typically, you want
// validation layers to be enabled when debug mode is enabled, and vice versa,
// but there are cases where you might want to run in debug mode without the
// validation layer overhead.
VK_VALIDATION :: #config(vk_validation, ODIN_DEBUG)

Vertex :: struct #packed {
    pos: [3]f32,
    color: [3]f32,
}

INIT_WIDTH :: 1000
INIT_HEIGHT :: 1000

graphics_initialize :: proc() -> (res: Graphics_Resources) {
    when ODIN_DEBUG do recompile_shaders_in_directory(".")

    libresult := sdl.Vulkan_LoadLibrary(nil)
    if libresult == -1 && ODIN_OS == .Darwin {
        // explicitly use the dylib location on mac
        libresult = sdl.Vulkan_LoadLibrary("/usr/local/lib/libvulkan.dylib")
    }
    assert(libresult == 0, "could not found vulkan library!")

    get_instance_proc_addr := try(sdl.Vulkan_GetVkGetInstanceProcAddr())
    vk.load_proc_addresses_global(get_instance_proc_addr)

    using res

    swapchain.window = sdl.CreateWindow(
        "Triangle", 
        1000, 20, 1000, 1000, 
        { .VULKAN, .RESIZABLE, .ALLOW_HIGHDPI },
    )

    // Getting API & Device Handles
    instance = create_instance(swapchain.window)
    surface = create_surface(swapchain.window, instance)
    physical_device, physical_device_info = pick_suitable_device(instance)
    queue_indices = find_queue_families(physical_device, surface)
    device = grab_device(physical_device, queue_indices)
    for q, f in &queue_indices do queues[f] = vk.get_device_queue(u32(q), 0)

    // Allocating Objects
    create_swapchain(&swapchain, physical_device, surface)
    command_pools = create_command_pools(queue_indices)
    vk.allocate_command_buffers(command_pools[.Graphics], .Primary, 1, &graphics_cmd_buffer)

    vk.allocate_command_buffers(command_pools[.Transfer], .Primary, 1, &transfer_cmd_buffer)
    transfer_fence = try(vk.create_fence({}))

    initialize_vetex_buffer(&res)

    pipeline_cache = load_pipeline_cache()

    pipelines = load_graphics_pipelines(swapchain.format.format, pipeline_cache)
    create_swapchain_framebuffers(pipelines, &swapchain)

    return
}

recreate_graphics :: proc(using res: ^Graphics_Resources) {
    // It's helpful to still have the old items around while we're reacreating
    // because of things like SwapchainCreateInfo.oldSwapchain, where old
    // resources can be re-used and not deleted.
    old_res := res^

    create_swapchain(&swapchain, physical_device, surface,
        old_swapchain = old_res.swapchain.handle)
    command_pools = create_command_pools(queue_indices)
    vk.allocate_command_buffers(command_pools[.Graphics], .Primary, 1, &graphics_cmd_buffer)

    vk.allocate_command_buffers(command_pools[.Transfer], .Primary, 1, &transfer_cmd_buffer)
    transfer_fence = try(vk.create_fence({}))

    pipelines = load_graphics_pipelines(swapchain.format.format, pipeline_cache)
    create_swapchain_framebuffers(pipelines, &swapchain)

    destroy_recreatable_graphics_resources(&old_res)
}

destroy_recreatable_graphics_resources :: proc(using res: ^Graphics_Resources) {
    for &image in swapchain.images {
        vk.destroy_image_view(image.view)
        vk.destroy_framebuffer(image.framebuffer)
        vk.destroy_semaphore(image.image_available)
        vk.destroy_semaphore(image.render_finished)
        vk.destroy_fence(image.fence_in_flight)
    }
    delete(swapchain.images)

    vk.destroy_swapchain(swapchain.handle)

    vk.free_command_buffers(command_pools[.Graphics], { graphics_cmd_buffer })
    vk.free_command_buffers(command_pools[.Transfer], { transfer_cmd_buffer })
    vk.destroy_fence(transfer_fence)
    for command_pool in command_pools do vk.destroy_command_pool(command_pool)

    for pipeline in pipelines {
        vk.destroy_pipeline_layout(pipeline.layout)
        vk.destroy_pipeline(pipeline.handle)
        vk.destroy_render_pass(pipeline.render_pass)
    }
}

initialize_vetex_buffer :: proc(using gfxres: ^Graphics_Resources) {
    vertex_buffer = buffer_allocate(Vertex, 3 * size_of(Vertex), 
        { .Vertex_Buffer, .Transfer_Dst }, { .Device_Local })

    vk.begin_command_buffer(transfer_cmd_buffer, nil, {.One_Time_Submit})

    staging_buffer := buffer_write([]Vertex {
        Vertex { {  0.0, -0.5, 0.0 }, { 0.0, 0.0, 1.0 } },
        Vertex { { -0.5,  0.5, 0.0 }, { 0.0, 1.0, 0.0 } },
    	Vertex { {  0.5,  0.5, 0.0 }, { 1.0, 0.0, 0.0 } },
    }, &vertex_buffer, transfer_cmd_buffer);
    defer buffer_destroy(&staging_buffer)

    vk.end_command_buffer(transfer_cmd_buffer)

    vk.queue_submit(
        queues[.Transfer],
        { {
            s_type = .Submit_Info,
            command_buffer_count = 1,
            command_buffers = &transfer_cmd_buffer,
        } },
        transfer_fence,
    )

    vk.wait_for_fences({ transfer_fence }, true, max(u64))
    vk.reset_fences({ transfer_fence })
}

create_surface :: proc(window: ^sdl.Window, instance: vk.Instance) -> 
  (surface: vk.Surface) {
    // Quick hack because the odin sdl bindings work with the builtin vulkan
    // bindings and we do not 
    sdl_vulkan_create_surface := 
        transmute(proc "c" (^sdl.Window, vk.Instance, ^vk.Surface) -> bool)sdl.Vulkan_CreateSurface

    ok := sdl_vulkan_create_surface(window, instance, &surface)
    if !ok do fmt.panicf("%v\n", sdl.GetError())
    return
}

create_instance :: proc(window: ^sdl.Window) -> (instance: vk.Instance) {
    app_info := vk.Application_Info {
        s_type = .Application_Info,
        application_name = "Triangle",
        application_version = vk.MAKE_VERSION(1, 0, 1),
        engine_name = "No Engine",
        engine_version = vk.MAKE_VERSION(1, 0, 0),
        api_version = vk.API_VERSION_1_3,
    }

    // extensions
    ext_count: u32 = 0
    sdl.Vulkan_GetInstanceExtensions(window, &ext_count, nil)
    ext_names := make([dynamic]cstring, len = ext_count, cap = ext_count,
        allocator = context.temp_allocator)
    sdl.Vulkan_GetInstanceExtensions(window, &ext_count, raw_data(ext_names))

    flags: vk.Instance_Create_Flags = {}

    when ODIN_OS == .Darwin {
        append(&ext_names, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
        flags |= { .Enumerate_Portability }
    }

    when VK_VALIDATION {
        append(&ext_names, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)
    }

    validation_layers: []cstring

    // layers
    when VK_VALIDATION {
        VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"}
        instance_layers := try(vk.enumerate_instance_layer_properties())

        outer: for name in VALIDATION_LAYERS {
            for &layer in instance_layers {
                if name == transmute(cstring)&layer.layer_name {
                    continue outer
                }
            }

            fmt.panicf("validation layer %v is not available!", name)
        }
        
        validation_layers = VALIDATION_LAYERS[:]
    } else {
        validation_layers = {}
    }
    
    instance = try(vk.create_instance(&app_info, flags, validation_layers, ext_names[:]))
    
    vk.load_proc_addresses_instance(instance)

    return
}

create_swapchain :: proc(
    using swapchain: ^Swapchain, dev: vk.Physical_Device, surface: vk.Surface, 
    old_swapchain: vk.Swapchain = {},
) {
    surface_capabilities = 
        try(vk.get_physical_device_surface_capabilities(dev, surface))

    sdl.GetWindowSize(window, &point_width, &point_height)
    sdl.Vulkan_GetDrawableSize(window, &pixel_width, &pixel_height)

    assert(surface_capabilities.current_extent.width  == u32(pixel_width))
    assert(surface_capabilities.current_extent.height == u32(pixel_height))

    supported_surface_formats :=
        try(vk.get_physical_device_surface_formats(dev, surface))
    supported_present_modes :=
        try(vk.get_physical_device_surface_present_modes(dev, surface))

    format = vk.Surface_Format { .B8G8R8A8_Srgb, .Srgb_Nonlinear }
    if slice.none_of(supported_surface_formats, format) {
        format = supported_surface_formats[0]
    }

    present_mode = vk.Present_Mode(.Mailbox)
    if slice.none_of(supported_present_modes, present_mode) {
        present_mode = supported_present_modes[0]
    }

    intended_image_count := clamp(3,
        surface_capabilities.min_image_count, 
        surface_capabilities.max_image_count,
    )
    
    create_info := vk.Swapchain_Create_Info {
        s_type = .Swapchain_Create_Info,
        surface = surface,
        min_image_count = intended_image_count,
        image_format = format.format,
        image_color_space = format.color_space,
        image_extent = vk.Extent_2D { u32(pixel_width), u32(pixel_height) },
        image_array_layers = 1,
        image_usage = { .Color_Attachment },
        pre_transform = surface_capabilities.current_transform,
        composite_alpha = { .Opaque },
        present_mode = present_mode,
        clipped = true,
        old_swapchain = old_swapchain,
        image_sharing_mode = .Exclusive,
    }
    
    swapchain.handle = try(vk.create_swapchain(&create_info))
    image_handles := try(vk.get_swapchain_images(swapchain.handle))
    image_count = u32(len(image_handles))

    // The swapchain image_index marks the frame we last issued the draw
    // command with. Next frame, we'll draw to (image_index + 1) % image_count.
    // We want to start with image_index set to the final frame index, so that
    // draw_frame, starts from frame 0.
    swapchain.image_index = image_count - 1

    swapchain.images = soa_zip(
        image = image_handles,
        view = make([]vk.Image_View, image_count),
        framebuffer = make([]vk.Framebuffer, image_count),
        image_available = make([]vk.Semaphore, image_count),
        render_finished = make([]vk.Semaphore, image_count),
        fence_in_flight = make([]vk.Fence, image_count),
    )

    for &image in swapchain.images {
        image.view = try(vk.create_image_view(&vk.Image_View_Create_Info {
            s_type = .Image_View_Create_Info,
            image = image.image,
            format = format.format,
            view_type = .D2,
            subresource_range = vk.COMPLETE_COLOR_IMAGE_RANGE,
        }))

        image.image_available = try(vk.create_semaphore({}))
        image.render_finished = try(vk.create_semaphore({}))
        image.fence_in_flight = try(vk.create_fence({ .Signaled }))
    }
}

create_command_pools :: proc(queue_indices: [Queue_Family]u32) -> 
  (pools: [Queue_Family]vk.Command_Pool) {
    for queue_index, family_index in queue_indices {
        pools[family_index] =
            try(vk.create_command_pool(queue_index, { .Reset_Command_Buffer }))
    }

    return
}

create_swapchain_framebuffers :: proc(
    pipelines: Pipelines, using swapchain: ^Swapchain,
) {
    for &image, i in images {
        image.framebuffer = try(vk.create_framebuffer(
            pipelines[.Triangle].render_pass,
            { image.view },
            width = u32(pixel_width), height = u32(pixel_height),
        ))
    }
}

graphics_cleanup :: proc(using res: ^Graphics_Resources) {
    vk.device_wait_idle()

    destroy_recreatable_graphics_resources(res)

    buffer_destroy(&vertex_buffer)

    save_pipeline_cache(pipeline_cache)
    vk.destroy_pipeline_cache(pipeline_cache)

    vk.destroy_device(device)
    vk.destroy_surface(instance, surface)
    vk.destroy_instance(instance)
}
