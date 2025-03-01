package src
import rl "vendor:raylib"
import "core:c"
import "core:log"

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
    shrunk := shrink_wall(demo_wall[:], demo_wall_width)
    xor := wall_xor(demo_wall[:], shrunk[:], demo_wall_width)
    expanded := grow_wall(demo_wall[:], demo_wall_width)

    dungeon, dungeon_elems := dungeon_gen(demo_wall[:], demo_wall_width, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{3,3},
        num_rooms = 14
    })

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        preview_wall(demo_wall[:], demo_wall_width, [2]c.int{400, 400}, rl.RED)
        preview_wall(xor[:], demo_wall_width, [2]c.int{400, 400}, rl.WHITE)

        preview_wall(expanded[:], demo_wall_width, [2]c.int{100, 400}, rl.WHITE)
        preview_wall(demo_wall[:], demo_wall_width, [2]c.int{100, 400}, rl.RED)

        preview_wall(demo_wall[:], demo_wall_width, [2]c.int{50, 50}, rl.WHITE)
        preview_wall(dungeon[:], demo_wall_width, [2]c.int{50, 50}, rl.RED)

        ui_draw(&game)
        rl.EndDrawing()
    }

}