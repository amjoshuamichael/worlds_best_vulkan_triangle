package triangle

import "core:fmt"
import vk "idiomatic_odin_vulkan_bindings"

when ODIN_OS == .Darwin {
    DEVICE_EXTENSIONS := [?]cstring{
        "VK_KHR_swapchain",

        // MacOS uses MoltenVK, which is a non-conformant vulkan
        // implementation. We need to accept this when creating the Vulkan
        // Instance on Mac.
        //
        // See: https://vulkan.lunarg.com/doc/view/1.3.236.0/mac/getting_started.html#user-content-encountered-vk_error_incompatible_driver
        "VK_KHR_portability_subset",
    }
} else {
    DEVICE_EXTENSIONS := [?]cstring{
        "VK_KHR_swapchain",
    }
}

Physical_Device_Info :: struct {
    props: vk.Physical_Device_Properties,
    features: vk.Physical_Device_Features,
    available_extensions: []vk.Extension_Properties,
    surface_capabilities: vk.Surface_Capabilities,
    surface_formats: []vk.Surface_Format,
    memory_properties: vk.Physical_Device_Memory_Properties,
}

pick_suitable_device :: proc(instance: vk.Instance) ->
  (vk.Physical_Device, Physical_Device_Info) {
    devices := try(vk.enumerate_physical_devices(instance))

    suitability :: proc(using info: ^Physical_Device_Info) -> (score: int) {
        iterate_required_extensions: for ext in DEVICE_EXTENSIONS {
            for &available in available_extensions {
                if cstring(&available.extension_name[0]) == ext {
                    continue iterate_required_extensions
                }
            }

            return 0
        }

        switch props.device_type {
        case .Discrete_Gpu  : score += 10000
        case .Integrated_Gpu: score += 5000
        case .Virtual_Gpu   : score += 4000
        case .Cpu           : score += 3000
        case .Other         : score += 2000
        }

        score += int(props.limits.max_image_dimension_1d)

        return score
    }
    
    best_score := 0
    best_device_info: Physical_Device_Info
    device: vk.Physical_Device
    for dev in devices {
        device_info := Physical_Device_Info {
            props = vk.get_physical_device_properties(dev),
            features = vk.get_physical_device_features(dev),
            available_extensions = 
                try(vk.enumerate_device_extension_properties(dev)),
        }

        score := suitability(&device_info)
        
        if score > best_score {
            best_score = score
            best_device_info = device_info
            device = dev
        }
    }

    if device == nil {
        panic("no suitable graphics devices")
    }

    best_device_info.memory_properties = 
        vk.get_physical_device_memory_properties(device)

    return device, best_device_info
}

find_queue_families :: proc(device: vk.Physical_Device, surface: vk.Surface) -> 
  (queue_indices: [Queue_Family]u32) {
    found_graphics, found_transfer := false, false

    available_queues := vk.get_physical_device_queue_family_properties(device)
    
    for v, i in available_queues {
        present_support := try(vk.get_physical_device_surface_support(
            device, u32(i), surface,
        ))

        if .Graphics in v.queue_flags && present_support {
            queue_indices[.Graphics] = u32(i)
            found_graphics = true
            break
        }
    }

    for v, i in available_queues {
        if queue_indices[.Graphics] == u32(i) do continue // we want unique indices
        if .Transfer in v.queue_flags {
            queue_indices[.Transfer] = u32(i)
            found_transfer = true
            break
        }
    }

    if !found_transfer || !found_graphics {
        fmt.panicf("could not get all queues: %v %v", found_transfer, found_graphics)
    }

    return queue_indices
}

grab_device :: proc(
    physical_device: vk.Physical_Device, queue_indices: [Queue_Family]u32
) -> vk.Device {
    queue_create_infos: [len(Queue_Family)]vk.Device_Queue_Create_Info

    for &queue_create_info, family_idx in queue_create_infos {
        queue_create_info = vk.Device_Queue_Create_Info {
            s_type = .Device_Queue_Create_Info,
            queue_family_index = queue_indices[Queue_Family(family_idx)],
            queue_count = 1,
            queue_priorities = raw_data([]f32 { 1.0 }),
        }
    }

    device := try(vk.create_device(physical_device,
        enabled_features = &vk.Physical_Device_Features { },
        queue_create_infos = queue_create_infos[:],
        enabled_extension_names = DEVICE_EXTENSIONS[:],
    ))

    vk.set_global_device(device)

    return device
}
