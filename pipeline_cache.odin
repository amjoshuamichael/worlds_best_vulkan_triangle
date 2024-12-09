package triangle

import "core:os"
import "core:crypto/hash"
import vk "idiomatic_odin_vulkan_bindings"

// save some metadata with the pipeline cache blob, so when we get everything
// back we know it's the right file. technique adapted from Arseny Kapoulkine's
// blog:
//
// https://zeux.io/2019/07/17/serializing-pipeline-cache/
@(private="file")
Pipeline_Cache_Header :: struct {
    data_size: u32,
    data_hash: [32]u8,

    vendor_id: u32,
    device_id: u32,
    driver_version: u32,
    cache_uuid: [vk.UUID_SIZE]u8, // Physical_Device_Properties.pipeline_cache_uuid
}

@(private="file")
HEADER_SIZE :: size_of(Pipeline_Cache_Header)

@(private="file")
pipeline_cache_file_location :: proc() -> string {
    // In a real application, you'd want to find a real directory to store this:
    // AppData\Local\Temp on Windows
    // ~/Library/Caches on MacOS
    // ~/.cache on Linux
    return "pipeline_cache_data.bin"
}

load_pipeline_cache :: proc() -> vk.Pipeline_Cache {
    bin_data, found_file := os.read_entire_file(pipeline_cache_file_location())

    if !found_file || len(bin_data) <= HEADER_SIZE {
        return try(vk.create_pipeline_cache(0, nil))
    }

    prefix := (cast(^Pipeline_Cache_Header)raw_data(bin_data))^
    cache_data_ptr := bin_data[HEADER_SIZE:]

    if prefix.data_hash      != hash_bytes(cache_data_ptr) ||
       prefix.data_size      != u32(len(bin_data) - HEADER_SIZE) ||
       prefix.vendor_id      != physical_device_info.props.vendor_id ||
       prefix.device_id      != physical_device_info.props.device_id ||
       prefix.driver_version != physical_device_info.props.driver_version ||
       prefix.cache_uuid     != physical_device_info.props.pipeline_cache_uuid {
        return try(vk.create_pipeline_cache(0, nil))
    } else {
        return try(vk.create_pipeline_cache(
            initial_data_size = int(prefix.data_size), 
            initial_data      = rawptr(raw_data(cache_data_ptr)),
        ))
    }
}

save_pipeline_cache :: proc(pipeline_cache: vk.Pipeline_Cache) {
    pipeline_cache_data := try(vk.get_pipeline_cache_data(pipeline_cache))

    if len(pipeline_cache_data) <= size_of(u32) {
        // data is empty or only contains application version information
        return
    }

    prefix_header := Pipeline_Cache_Header {
        data_size      = u32(len(pipeline_cache_data)),
        data_hash      = hash_bytes(pipeline_cache_data),
        vendor_id      = physical_device_info.props.vendor_id,
        device_id      = physical_device_info.props.device_id,
        driver_version = physical_device_info.props.driver_version,
        cache_uuid     = physical_device_info.props.pipeline_cache_uuid,
    }

    pipeline_cache_file := try(os.open(pipeline_cache_file_location(), 
        os.O_CREATE | os.O_TRUNC | os.O_WRONLY, 
        os.S_IRUSR | os.S_IWUSR | os.S_IRGRP | os.S_IWGRP | os.S_IROTH | os.S_IWOTH,
    ))
    prefix_header_bytes := (cast([^]u8)&prefix_header)[:size_of(Pipeline_Cache_Header)]
    os.write(pipeline_cache_file, prefix_header_bytes)
    os.write(pipeline_cache_file, pipeline_cache_data)
    os.close(pipeline_cache_file)
}

@(private="file")
hash_bytes :: proc(bytes: []u8) -> (data_hash: [32]u8) {
    hash_context: hash.Context
	hash.init(&hash_context, .SHA256)
	hash.update(&hash_context, bytes)
	hash.final(&hash_context, data_hash[:])
    return data_hash
}
