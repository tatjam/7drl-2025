package src
import rl "vendor:raylib"
import "core:c"

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

    demo_wall, demo_wall_width := wall_from_image("res/demo.png")
    shrunk := shrink_wall(demo_wall[:], demo_wall_width)

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        for yi:=0; yi < len(demo_wall) / demo_wall_width; yi+=1 {
            for xi:=0; xi < demo_wall_width; xi+=1 {
                if demo_wall[yi*demo_wall_width + xi] {
                    rl.DrawPixel(c.int(xi) + 50, c.int(yi) + 50, rl.WHITE)
                }
                if shrunk[yi * demo_wall_width + xi] {
                    rl.DrawPixel(c.int(xi) + 50, c.int(yi) + 50, rl.RED)
                }
            }
        }

        ui_draw(&game)
        rl.EndDrawing()
    }

}