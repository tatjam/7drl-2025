package src
import rl "vendor:raylib"
import "core:c"
import "core:log"
import "core:math"
import "core:mem"
import "core:fmt"

main :: proc() {
    // Initialize the tracking allocator
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
    rl.SetExitKey(rl.KeyboardKey.KEY_NULL)
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    game := create_game()
    defer destroy_game(&game)

    game_push_message(&game, "Welcome to Scalar!")
    game_push_message(&game, "You may press ? to get a list of controls / help")

    game.worldmap = create_world(32, 32, DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{1,1},
        num_rooms = 14
    })
    defer destroy_tilemap(&game.worldmap)

    startpos := tilemap_find_spawn_pos(game.worldmap)
    game.hero = create_hero(&game, startpos)
    probestartpos := tilemap_find_spawn_pos(game.hero.scale_kind.(FullscaleActor).subscale.tmap)
    game.probe = create_probe(&game, probestartpos)

    for !rl.WindowShouldClose() {
        game_update(&game)

        rl.BeginDrawing()

        game_draw(&game)
        //preview_wall(game.worldmap.walls[:], game.worldmap.width, [2]c.int{900, 512}, rl.RED)

        rl.EndDrawing()
    }

}