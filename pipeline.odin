package triangle

import "base:runtime"
import "core:fmt"
import "core:slice"
import vk "idiomatic_odin_vulkan_bindings"

Pipeline :: struct {
    handle: vk.Pipeline,
    layout: vk.Pipeline_Layout,
    render_pass: vk.Render_Pass,
}

GPU_Pipeline_ID :: enum {
    Triangle,
}

Pipelines :: [GPU_Pipeline_ID]Pipeline

@(private="file")
Pipeline_Configuration :: struct {
    vertex_input: vk.Pipeline_Vertex_Input_State_Create_Info,
    dynamic_state: vk.Pipeline_Dynamic_State_Create_Info,
    input_assembly: vk.Pipeline_Input_Assembly_State_Create_Info,
    rasterizer: vk.Pipeline_Rasterization_State_Create_Info,
    multisampling: vk.Pipeline_Multisample_State_Create_Info,
    blending: vk.Pipeline_Color_Blend_State_Create_Info,
    depth: vk.Pipeline_Depth_Stencil_State_Create_Info,
    viewport: vk.Pipeline_Viewport_State_Create_Info,
    layout: vk.Pipeline_Layout,
    shaders: []vk.Pipeline_Shader_Stage_Create_Info,
    render_pass: vk.Render_Pass,
}

load_graphics_pipelines :: proc(format: vk.Format, pipeline_cache: vk.Pipeline_Cache) -> 
  Pipelines {
    main_vert := shader_module("main.vert.spv")
    main_frag := shader_module("main.frag.spv")

    defer vk.destroy_shader_module(main_vert)
    defer vk.destroy_shader_module(main_frag)

    // This triangle example is mnimal of course, but in practice, a program will
    // take a number of steps to render. We need to create separate graphics
    // pipelines for each of these steps, but and each of these steps has slightly
    // different configurations from the others. It doesn't quite make sense to
    // specify the entire configuration for every single pipeline in the list.
    // Instead, we do this in a stateful way: initialize a structure that has a
    // default config, and then for each pipeline, modify it, and use that modified
    // version to create the pipeline. 

    good_default_config := Pipeline_Configuration {
        dynamic_state = {
            s_type = .Pipeline_Dynamic_State_Create_Info,
            dynamic_state_count = 2,
            dynamic_states = raw_data([]vk.Dynamic_State { .Viewport, .Scissor, }),
        },
        input_assembly = {
            s_type = .Pipeline_Input_Assembly_State_Create_Info,
            topology = .Triangle_List,
        },
        rasterizer = {
            s_type = .Pipeline_Rasterization_State_Create_Info,
            polygon_mode = .Fill,
            line_width = 1.0,
            cull_mode = {.Back},
            front_face = .Counter_Clockwise,
        },
        multisampling = {
            s_type = .Pipeline_Multisample_State_Create_Info,
            rasterization_samples = {._1},
            min_sample_shading = 1.0,
        },
        blending = {
            s_type = .Pipeline_Color_Blend_State_Create_Info,
            attachment_count = 1,
            attachments = raw_data([]vk.Pipeline_Color_Blend_Attachment_State {
                { color_write_mask = {.R, .G, .B}, blend_enable = false, },
            }),
        },
        depth = {
            s_type = .Pipeline_Depth_Stencil_State_Create_Info,
            depth_test_enable = true,
            depth_write_enable = true,
            depth_compare_op = .Less,
        },
        viewport = {
            s_type = .Pipeline_Viewport_State_Create_Info,
            viewport_count = 1,
            scissor_count = 1, scissors = &vk.Rect_2D { },
        },
    }

    pipeline_configs: [GPU_Pipeline_ID]Pipeline_Configuration
    for &config in pipeline_configs do config = good_default_config

    triangle := &pipeline_configs[.Triangle]
    // we aren't passing any descriptors or push constants to the shader, so we
    // can leave the pipeline layout blank.
    triangle.layout = try(vk.create_pipeline_layout({}))
    triangle.shaders = {
        shader(.Vertex, main_vert), shader(.Fragment, main_frag),
    }
    triangle.depth.depth_test_enable = false
    triangle.vertex_input = vertex_input_for(Vertex)
    triangle.render_pass = try(vk.create_render_pass(
       attachments = {
            { load_op = .Clear, store_op = .Store, format = format,
                initial_layout = .Undefined, final_layout = .Present_Src,
                samples = {._1} },
        },
        subpasses = {
            subpass(
                color = { { 0, .Color_Attachment_Optimal }, },
            ),
        },
    ))
    
    return create_graphics_pipelines(&pipeline_configs, pipeline_cache)
}

create_graphics_pipelines :: proc(
    configurations: ^[GPU_Pipeline_ID]Pipeline_Configuration, 
    pipeline_cache: vk.Pipeline_Cache,
) -> (pipelines: [GPU_Pipeline_ID]Pipeline) {
    pipeline_create_infos: [len(GPU_Pipeline_ID)]vk.Graphics_Pipeline_Create_Info 

    for &config, p in configurations {
        pipelines[p].layout = config.layout
        pipelines[p].render_pass = config.render_pass

        pipeline_create_infos[int(p)] = vk.Graphics_Pipeline_Create_Info {
            s_type = .Graphics_Pipeline_Create_Info,
            stage_count = u32(len(config.shaders)),
            stages = raw_data(config.shaders),
            vertex_input_state = &config.vertex_input,
            input_assembly_state = &config.input_assembly,
            viewport_state = &config.viewport,
            rasterization_state = &config.rasterizer,
            multisample_state = &config.multisampling,
            depth_stencil_state = &config.depth,
            color_blend_state = &config.blending,
            dynamic_state = &config.dynamic_state,
            layout = config.layout,
            render_pass = config.render_pass,
            subpass = 0,
            base_pipeline_index = -1,
        }
    }

    handles: [len(GPU_Pipeline_ID)]vk.Pipeline

    try(vk.create_graphics_pipelines(
        pipeline_cache, pipeline_create_infos[:], raw_data(handles[:]),
    ))

    for handle, h in handles do pipelines[GPU_Pipeline_ID(h)].handle = handle

    return pipelines
}

@(private="file")
shader :: proc(stage: vk.Shader_Stage_Flag, module: vk.Shader_Module) -> 
  vk.Pipeline_Shader_Stage_Create_Info {
    return vk.Pipeline_Shader_Stage_Create_Info {
        s_type = .Pipeline_Shader_Stage_Create_Info,
        name = "main",
        stage = { stage },
        module = module,
    }
}

@(private="file")
subpass :: proc(
    bind_point: vk.Pipeline_Bind_Point = .Graphics, 
    color: []vk.Attachment_Reference = {},
	inputs: []vk.Attachment_Reference = {},
    depth: ^vk.Attachment_Reference = nil,
) -> vk.Subpass_Description {
    return vk.Subpass_Description {
        color_attachment_count = u32(len(color)),
        color_attachments = raw_data(color),
        input_attachment_count = u32(len(inputs)),
        input_attachments = raw_data(inputs),
        depth_stencil_attachment = depth,
    }
}

@(private="file")
vertex_input_for :: proc($V: typeid) -> 
  (vertex_input: vk.Pipeline_Vertex_Input_State_Create_Info) {
    vertex_input.vertex_binding_descriptions = 
        raw_data(slice.clone([]vk.Vertex_Input_Binding_Description {
            { 0, size_of(V), .Vertex },
        }, allocator = context.temp_allocator))
    vertex_input.vertex_binding_description_count = 1

    attributes := make([dynamic]vk.Vertex_Input_Attribute_Description,
        allocator = context.temp_allocator)
    get_vertex_attributes_for(V, 0, &attributes)

    vertex_input.vertex_attribute_description_count = u32(len(attributes))
    vertex_input.vertex_attribute_descriptions = raw_data(attributes)

    vertex_input.s_type = .Pipeline_Vertex_Input_State_Create_Info

    return
}

@(private="file")
get_vertex_attributes_for :: proc(
    $T: typeid, binding: u32,
    attributes: ^[dynamic]vk.Vertex_Input_Attribute_Description,
) {
    type_info := runtime.type_info_base(type_info_of(T))
    struct_info := type_info.variant.(runtime.Type_Info_Struct)

    for field, f in struct_info.types[:struct_info.field_count] {
        desc := vk.Vertex_Input_Attribute_Description {
            location = u32(len(attributes)),
            binding = binding,
            offset = u32(struct_info.offsets[f]),
        }

        #partial switch v in field.variant {
        case runtime.Type_Info_Array: array := v
            elem := runtime.type_info_base(v.elem)

            _, is_float := elem.variant.(runtime.Type_Info_Float)
            _, is_int   := elem.variant.(runtime.Type_Info_Integer)

            switch {
            case is_int && elem.size == 1: switch {
                case array.count == 2: desc.format = .R8G8_Sint
                case array.count == 3: desc.format = .R8G8B8_Sint
                case array.count == 4: desc.format = .R8G8B8A8_Sint
                case: fmt.panicf("can't use %v in array\n", field)
            }
            case is_float && elem.size == 2: switch {
                case array.count == 2: desc.format = .R16G16_Sfloat
                case array.count == 3: desc.format = .R16G16B16_Sfloat
                case array.count == 4: desc.format = .R16G16B16A16_Sfloat
                case: fmt.panicf("can't use %v in array\n", field)
            }
            case is_float && elem.size == 4: switch {
                case array.count == 2: desc.format = .R32G32_Sfloat
                case array.count == 3: desc.format = .R32G32B32_Sfloat
                case array.count == 4: desc.format = .R32G32B32A32_Sfloat
                case: fmt.panicf("can't use %v in array\n", field)
            }
            case: fmt.panicf("can't use %v in array\n", field)
            }
            

            append(attributes, desc)
        case runtime.Type_Info_Matrix:
            elem := runtime.type_info_base(v.elem)

            _,is_float := elem.variant.(runtime.Type_Info_Float)

            switch {
            case is_float && v.row_count == 4: desc.format = .R32G32B32A32_Sfloat
            case: fmt.panicf("can't use %v in matrix\n", field)
            }

            for c in 0..<v.column_count {
                append(attributes, desc)
                desc.offset += u32(v.row_count * size_of(f32))
                desc.location += 1
            }
        case runtime.Type_Info_Integer:
            switch field.size {
            case 2: desc.format = .R16_Uint
            case 4: desc.format = .R32_Uint
            case 8: desc.format = .R64_Uint
            }

            append(attributes, desc)
        case runtime.Type_Info_Float:
            switch field.size {
            case 2: desc.format = .R16_Sfloat
            case 4: desc.format = .R32_Sfloat
            case 8: desc.format = .R64_Sfloat
            }   

            append(attributes, desc)
        case: fmt.panicf("can't use %v in struct\n", field)
        }
    }
}
