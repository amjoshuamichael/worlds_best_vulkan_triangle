package triangle

import sdl "vendor:sdl2"

main :: proc() {
    sdl.Init({ .VIDEO, .EVENTS })

    gfxres := graphics_initialize()

    event: sdl.Event
    app_loop: for {
        for sdl.PollEvent(&event) {
            if event.type == .QUIT do break app_loop
        }

        draw_frame(&gfxres)
    }

    graphics_cleanup(&gfxres)
}

