package src
import rl "vendor:raylib"
import "core:c"
import "core:log"
import "core:math"
import "core:mem"
import "core:fmt"

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)
        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

    rl.SetConfigFlags(rl.ConfigFlags{
        rl.ConfigFlag.WINDOW_RESIZABLE
    })
    rl.InitWindow(512, 512, "Guamedo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    game := create_game()
    defer destroy_game(&game)

    game_push_message(&game, "Welcome to Scalar!")
    game_push_message(&game, "You may press ? to get a list of controls / help")

    demo_wall, demo_wall_width := wall_from_image("res/demo.png")

    dungeon, dungeon_rooms, frontier := dungeon_gen(demo_wall[:], demo_wall_width, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{1,1},
        num_rooms = 14
    })
    delete(demo_wall)
    game.worldmap = create_tilemap(dungeon, frontier[:], demo_wall_width, dungeon_rooms)
    delete(frontier)
    defer destroy_tilemap(&game.worldmap)

    startpos := tilemap_find_spawn_pos(game.worldmap)
    game.hero = create_hero(&game, startpos)


    for !rl.WindowShouldClose() {
        game_update(&game)

        rl.BeginDrawing()

        game_draw(&game)

        rl.EndDrawing()
    }

}