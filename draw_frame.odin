package triangle

import "core:os"
import "core:fmt"
import vk "idiomatic_odin_vulkan_bindings"
import sdl "vendor:sdl2"

draw_frame :: proc(using gfxres: ^Graphics_Resources) {
    previous_image := &swapchain.images[swapchain.image_index]
    vk.wait_for_fences({ previous_image.fence_in_flight }, true, max(u64))

    drawing_to_image_index := (swapchain.image_index + 1) % swapchain.image_count
    drawing_to_image := &swapchain.images[drawing_to_image_index]
    vk.reset_fences({ drawing_to_image.fence_in_flight })

    res: vk.Result
    swapchain.image_index, res = 
        vk.acquire_next_image(swapchain.handle, 0, drawing_to_image.image_available, {})

    if res != .Success {
        recreate_graphics(gfxres)
        return
    }

    vk.begin_command_buffer(graphics_cmd_buffer, nil, {.One_Time_Submit})

    output_dims := vk.Extent_2D { u32(swapchain.pixel_width), u32(swapchain.pixel_height) }

    vk.cmd_set_viewport(graphics_cmd_buffer, 0, { vk.Viewport {
        x = 0.0, y = 0.0,
        width = f32(output_dims.width), height = f32(output_dims.height),
        min_depth = 0.0, max_depth = 1.0,
    } })
    vk.cmd_set_scissor(graphics_cmd_buffer, 0, { { extent = output_dims } })

    vk.cmd_begin_render_pass(graphics_cmd_buffer,
        pipelines[.Triangle].render_pass, 
        drawing_to_image.framebuffer,
        vk.Rect_2D { extent = output_dims },
        {
            { color = { float32 = [4]f32{0, 0, 0, 1} } }, 
        },
        .Inline,
    )

    vk.cmd_bind_pipeline(graphics_cmd_buffer, .Graphics, pipelines[.Triangle].handle)

    offsets: vk.Device_Size = 0
    vk.cmd_bind_vertex_buffers(graphics_cmd_buffer, 0, 1, &vertex_buffer.handle, &offsets)
    vk.cmd_draw(graphics_cmd_buffer, 3, 1, 0, 0)

    vk.cmd_end_render_pass(graphics_cmd_buffer)

    vk.end_command_buffer(graphics_cmd_buffer) 

    submit_info := vk.Submit_Info {
        s_type = .Submit_Info,
        wait_semaphore_count = 1,
        wait_semaphores = &drawing_to_image.image_available,
        wait_dst_stage_mask = &vk.Pipeline_Stage_Flags { .Color_Attachment_Output },
        command_buffer_count = 1,
        command_buffers = &graphics_cmd_buffer,
        signal_semaphore_count = 1,
        signal_semaphores = &drawing_to_image.render_finished,
    }

    try(vk.queue_submit(queues[.Graphics], { submit_info }, drawing_to_image.fence_in_flight))

    vk.queue_present(queues[.Graphics], results = nil,
        wait_semaphores = { drawing_to_image.render_finished },
        swapchains = { swapchain.handle },
        image_indices = &swapchain.image_index)
}
