package src

import rl "vendor:raylib"
import "core:log"

GameState :: struct {
    uifont: rl.Font,
    assets: AssetManager,
    // Last message pushed is last message shown.
    statuslog: [dynamic]cstring,
    lastmessage_t: f64,

    worldmap: Tilemap,

    hero: HeroActor,
    probe: ProbeActor,
    monsters: [dynamic]MonsterActor,
    turni: int,

    focus_subscale: int,

    cur_action: Maybe(Action),
    anim_progress: f32,
}

create_game :: proc() -> (out: GameState) {
    out.uifont = rl.LoadFont("res/fonts/setback.png")
    out.turni = -1
    out.anim_progress = -1.0
    out.focus_subscale = -1

    return
}

destroy_game :: proc(game: ^GameState) {
    destroy_actor(&game.hero)
    for &monster in game.monsters {
        destroy_actor(&monster)
    }
    delete(game.statuslog)
    delete(game.monsters)
    destroy_assets(&game.assets)
}

game_push_message :: proc(game: ^GameState, msg: cstring) {
    append(&game.statuslog, msg)
    game.lastmessage_t = rl.GetTime()
}

// If it returns true, an animation must be carried out
game_do_action :: proc(game: ^GameState, action: Action) -> bool {
    subscale, is_subscale := action.by_actor.scale_kind.(SubscaleActor)
    if !is_subscale {
        can_see_any := false
        for need_see in action.need_see {
            if tilemap_raycast(game.worldmap,
            tile_center(game.hero.pos), tile_center(need_see)) == false {
                can_see_any = true
                break
            }
        }

        if can_see_any {
            game.anim_progress = 0.0
            game.cur_action = action
            return true
        } else {
            // Carry out the action instantly
            game.anim_progress = -1.0
            act_action(action)
            return false
        }
    }
    else {
        // Within a subscale actor, all actions are visible
        if game.focus_subscale != subscale.subscale_of {
            game.anim_progress = -1.0
            act_action(action)
            return false
        } else {
            game.anim_progress = 0.0
            game.cur_action = action
            return true
        }
    }
}

game_update :: proc(game: ^GameState) {
    if game.anim_progress >= 0 {
        // Animate cur action
        action, is_ok := game.cur_action.(Action)
        assert(is_ok)

        if game.anim_progress >= animate_action(action, game.anim_progress) {
            // Carry out the action itself
            act_action(action)
            game.anim_progress = -1.0
        }

        game.anim_progress += rl.GetFrameTime()
    } else {
        for {
            if game.turni == -1 {
                // Progress in turn
                hero_action := take_turn_hero(&game.hero)
                _, is_none := hero_action.variant.(NoAction)
                if is_none do break // Continue processing user input
                game.turni += 1
                assert(game_do_action(game, hero_action))
                // (User actions always animate)
                break
            } else {
                // AI actions (TODO)
                if game.turni == len(game.monsters) {
                    // TURN IS DONE
                    free_all(context.temp_allocator)
                    game.turni = -1
                    break
                } else {
                    action := take_turn_monster(&game.monsters[game.turni])
                    if game_do_action(game, action) {
                        break
                    } else {
                        act_action(action)
                    }

                    game.turni += 1
                }
            }
        }
    }
}

game_draw_game :: proc(game: ^GameState) {
    cam: rl.Camera2D
    cam.zoom = 64.0

    game_screen := rl.Rectangle{
        0.0, 0.0,
        GAME_PANEL_W * f32(rl.GetScreenWidth()), GAME_PANEL_H * f32(rl.GetScreenHeight())}
    cam.target = actor_get_draw_pos(game.hero)
    cam.offset = [2]f32{game_screen.width * 0.5, game_screen.height * 0.5}

    rl.ClearBackground(rl.Color{0, 0, 0, 255})
    rl.BeginMode2D(cam)


    ui_game_scissor()
    rl.ClearBackground(rl.Color{30, 30, 30, 255})
    world_tilemap_cast_shadows(game.worldmap, cam.target, game_screen, cam)
    draw_actor(&game.hero)
    draw_world_tilemap(game.worldmap)

    rl.EndScissorMode()
    rl.EndMode2D()

}

game_get_actor :: proc(game: ^GameState, actor_id: int) -> ^Actor {
    if actor_id < 0 {
        return &game.hero
    } else {
        return &game.monsters[actor_id]
    }
}

game_draw_subscale :: proc(game: ^GameState) {
    cam: rl.Camera2D
    cam.zoom = 16.0

    subscale_screen := rl.Rectangle{
        GAME_PANEL_W * f32(rl.GetScreenWidth()), 0.0,
        GAME_PANEL_W * (1.0 - f32(rl.GetScreenWidth())), GAME_PANEL_H * f32(rl.GetScreenHeight())}

    subs := game_get_actor(game, game.focus_subscale).scale_kind.(FullscaleActor).subscale
    stmap := subs.tmap
    cam.target = [2]f32{f32(stmap.width) * 0.5, f32(stmap.height) * 0.5}
    cam.offset = [2]f32{subscale_screen.width * 0.5, subscale_screen.height * 0.5}

    ui_subscale_scissor()

    // Draw the tilemap texture
    source := rl.Rectangle{0, 0,
        f32(subs.tmap.width * subs.tmap.tileset_size[0]),
        f32(subs.tmap.height * subs.tmap.tileset_size[1])
    }

    target := rl.Rectangle{
        subscale_screen.x, subscale_screen.y,
        source.width * 1, source.height * 1}

    rl.DrawTexturePro(subs.tex.texture,
        source, target, [2]f32{source.width, source.height}, 180.0, rl.WHITE
    )
    /*rl.DrawTextureRec(subs.tex.texture,
        source, [2]f32{subscale_screen.x, subscale_screen.y}, rl.WHITE)*/

    rl.EndScissorMode()
}

game_draw :: proc(game: ^GameState) {
    game_draw_game(game)
    game_draw_subscale(game)

    ui_draw(game)
}
