package triangle

import "core:os"
import "core:path/filepath"
import "core:fmt"
import "core:c/libc"
import "core:slice"
import vk "idiomatic_odin_vulkan_bindings"

SHADER_FILE_EXTENSIONS :: []string {".glsl", ".vert", ".frag", ".geom", ".tesc", ".tese"}

recompile_shaders_in_directory :: proc(path: string) {
    dir := try(os.open(path))
    dir_entries := try(os.read_dir(dir, 0))

    for entry in dir_entries {
        ext := filepath.ext(entry.name)
        if entry.is_dir {
            recompile_shaders_in_directory(entry.fullpath)
        } else if slice.any_of(SHADER_FILE_EXTENSIONS, ext) {
            compiled_path := fmt.tprintf("%v.spv", entry.fullpath)

            if !os.exists(compiled_path) {
                recompile_shader(entry.fullpath)
                continue
            }

            compiled_stat, err := os.stat(compiled_path)
            assert(err == nil)
            if entry.modification_time._nsec > compiled_stat.modification_time._nsec {
                // shader was compiled after the last modification
                recompile_shader(entry.fullpath)
                continue
            }
        }
    }
}

GLSLC_PATH :: #config(glslc, "glslc")

@(private="file")
recompile_shader :: proc(file_path: string) {
    cmd := fmt.ctprintf("%v -g -o %v.spv %v", GLSLC_PATH, file_path, file_path)

    cmd_status := libc.system(cmd)
    err_code := cmd_status >> 8

    if err_code == 1 {
        fmt.printf("failed to compile shader %v!\n", file_path)
        os.exit(0)
    }
}

shader_module :: proc($path: string) -> vk.Shader_Module {
    when ODIN_DEBUG {
        full_path := fmt.tprintf("%v", path)
        spirv_code := try(os.read_entire_file(full_path))
    } else {
        spirv_code := #load(path)
    }

    return try(vk.create_shader_module(len(spirv_code), cast(^u32)raw_data(spirv_code)))
}
