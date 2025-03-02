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

    dungeon, dungeon_rooms, frontier := dungeon_gen(demo_wall[:], demo_wall_width, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{1,1},
        num_rooms = 14
    })

    game.worldmap = create_world_tilemap(dungeon, frontier[:], demo_wall_width, dungeon_rooms)
    startpos := tilemap_find_spawn_pos(game.worldmap)
    game.hero = create_hero(&game, startpos)


    for !rl.WindowShouldClose() {
        game_update(&game)

        rl.BeginDrawing()

        game_draw(&game)

        preview_wall(dungeon[:], demo_wall_width, [2]c.int{500, 500}, rl.WHITE)
        preview_wall(frontier[:], demo_wall_width, [2]c.int{500, 500}, rl.RED)

        rl.EndDrawing()
    }

}