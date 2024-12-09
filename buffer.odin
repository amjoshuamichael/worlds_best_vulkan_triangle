package triangle

import "core:mem"
import "core:fmt"
import vk "idiomatic_odin_vulkan_bindings"

Buffer :: struct($T: typeid) {
    handle: vk.Buffer,
    memory: vk.Device_Memory,
    size:   vk.Device_Size,
}

buffer_allocate :: proc(
    $T: typeid,
    #any_int size: vk.Device_Size, 
    usage: vk.Buffer_Usage_Flags, properties: vk.Memory_Property_Flags,
) -> Buffer(T) {
    buffer := try(vk.create_buffer(size, usage, .Exclusive, {}))
    
    mem_reqs := vk.get_buffer_memory_requirements(buffer)
    memory := allocate_memory_of_type(mem_reqs, properties)

    vk.bind_buffer_memory(buffer, memory)

    return Buffer(T) { buffer, memory, size }
}

buffer_destroy :: proc(buffer: ^Buffer($T)) {
    vk.free_memory(buffer.memory)
    vk.destroy_buffer(buffer.handle)
}

buffer_write :: proc(data: []$T, write_to: ^Buffer(T), transfer_cmd: vk.Command_Buffer) -> Buffer(T) {
    write_size := vk.Device_Size(len(data) * size_of(T))

    staging_buf := buffer_allocate(T, write_size, {.Transfer_Src}, {.Host_Visible, .Host_Coherent})

    mapped_region := try(vk.map_memory(staging_buf.memory, 0, write_size, {}))
    mem.copy(cast(^T)mapped_region, raw_data(data), int(write_size))
    vk.unmap_memory(staging_buf.memory)
    
    vk.cmd_copy_buffer(transfer_cmd, staging_buf.handle, write_to.handle, 
        { { size = write_size } })

    return staging_buf
}

allocate_memory_of_type :: proc(
    reqs: vk.Memory_Requirements, flags: vk.Memory_Property_Flags,
) -> vk.Device_Memory {
    using physical_device_info.memory_properties

    memory_type: int = -1
    for type, t in memory_types[:memory_type_count] {
        type_fits_filter := reqs.memory_type_bits & (1 << u32(t)) != 0
        properties_match := type.property_flags >= flags

        if type_fits_filter && properties_match {
            memory_type = t
            break
        }
    }
    
    if memory_type == -1 do fmt.panicf("no suitable memory for %v %v", reqs, flags)

    return try(vk.allocate_memory(reqs.size, u32(memory_type)))
}
