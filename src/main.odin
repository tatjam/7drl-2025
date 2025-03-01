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

    dungeon, dungeon_elems := dungeon_gen(demo_wall[:], demo_wall_width, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{1,1},
        num_rooms = 14
    })

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        ui_draw(&game)
        rl.EndDrawing()
    }

}