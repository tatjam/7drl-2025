package src
import rl "vendor:raylib"

main :: proc() {
    rl.SetConfigFlags(rl.ConfigFlags{
        rl.ConfigFlag.WINDOW_RESIZABLE
    })
    rl.InitWindow(512, 512, "Guamedo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    game := create_game()
    game_push_message(&game, "Welcome to Scalar!")
    game_push_message(&game, "You may press ? to get a list of controls / help")

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        ui_draw(&game)

        rl.EndDrawing()
    }

}