package src
import rl "vendor:raylib"
import "core:c"
import "core:log"
import "core:math"

main :: proc() {
    context.logger = log.create_console_logger()

    rl.SetConfigFlags(rl.ConfigFlags{
        rl.ConfigFlag.WINDOW_RESIZABLE
    })
    rl.InitWindow(512, 512, "Guamedo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    game := create_game()
    game_push_message(&game, "Welcome to Scalar!")
    game_push_message(&game, "You may press ? to get a list of controls / help")

    demo_wall, demo_wall_width := wall_from_image("res/demo.png")

    dungeon, dungeon_elems, frontier := dungeon_gen(demo_wall[:], demo_wall_width, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{1,1},
        num_rooms = 14
    })

    worldmap := create_world_tilemap(dungeon, frontier[:], demo_wall_width)

    cam: rl.Camera2D
    cam.zoom = 50.0
    cam.offset = [2]f32{100.0, 100.0}

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.Color{30, 30, 30, 255})

        cam.target = [2]f32{f32(rl.GetMouseX()) * 0.1, f32(rl.GetMouseY()) * 0.1}
        rl.BeginMode2D(cam)
        game_screen := rl.Rectangle{
            0.0, 0.0,
            GAME_PANEL_W * f32(rl.GetScreenWidth()), GAME_PANEL_H * f32(rl.GetScreenHeight())}

        tilemap_cast_shadows(worldmap,
            cam.target,
            game_screen, cam)

        ui_game_scissor()
        draw_world_tilemap(worldmap)

        rl.EndScissorMode()
        rl.EndMode2D()

        preview_wall(dungeon[:], demo_wall_width, [2]c.int{500, 500}, rl.WHITE)
        preview_wall(frontier[:], demo_wall_width, [2]c.int{500, 500}, rl.RED)

        ui_draw(&game)
        rl.EndDrawing()
    }

}