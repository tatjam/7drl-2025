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

    startpos := tilemap_find_spawn_pos(&game, nil)
    create_hero(&game, startpos)
    hero_cortex := game.hero.scale_kind.(FullscaleActor).subscale.cortex
    probestartpos := tilemap_find_spawn_pos(&game, &game.hero)
    create_probe(&game, probestartpos, hero_cortex)
    game.focus_subscale = &game.hero
    // Do this so player starts functional
    for i:=1; i < 100; i+=1 {
        take_turn_organ(game.hero.scale_kind.(FullscaleActor).subscale.cortex)
    }

    for i := 0; i < 2; i += 1{
        spawnpos := tilemap_find_spawn_pos(&game, nil)
        create_mechanic(&game, spawnpos)
    }
    for i := 0; i < 5; i += 1{
        spawnpos := tilemap_find_spawn_pos(&game, nil)
        create_sentinel(&game, spawnpos)
    }

    for !rl.WindowShouldClose() {
        game_update(&game)

        rl.BeginDrawing()

        game_draw(&game)
        //preview_wall(game.worldmap.walls[:], game.worldmap.width, [2]c.int{900, 512}, rl.RED)

        rl.EndDrawing()
    }

}