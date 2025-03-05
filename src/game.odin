package src

import rl "vendor:raylib"
import "core:log"

ActionFX :: struct {
    visible: bool,
    pos: [2]f32,
    angle: f32,
    scale: f32,

    sprite_tex: rl.Texture2D,
    sprite_rect: rl.Rectangle,
    in_subscale: ^Actor,
    tint: rl.Color,
}

GameState :: struct {
    uifont: rl.Font,
    assets: AssetManager,
    // Last message pushed is last message shown.
    statuslog: [dynamic]cstring,
    lastmessage_t: f64,

    worldmap: Tilemap,

    hero: HeroActor,
    probe: ProbeActor,
    npcs: [dynamic]^NPCActor,
    turni: int,

    focus_subscale: ^Actor,

    cur_action: Maybe(Action),
    anim_progress: f32,

    playing_subscale: bool,

    show_help: bool,

    // Cleared at the end of the action animation
    fx: [dynamic]^ActionFX,
}

get_actor_aabb :: proc(actor: ^Actor) -> (tl: [2]int, size: [2]int) {
    size = actor.sprite_size
    tl = actor.pos - actor.sprite_size / 2
    return
}

actor_intersects :: proc(actor:^Actor, pos: [2]int, subscale_of: ^Actor = nil) -> bool {
    subscale, is_subscale := actor.scale_kind.(SubscaleActor)

    if subscale_of == nil && is_subscale do return false

    if (subscale_of != nil && is_subscale && subscale.subscale_of == subscale_of) ||
        (subscale_of == nil && !is_subscale) {

        tl, size := get_actor_aabb(actor)
        return pos.x >= tl.x && pos.x < tl.x + size.x && pos.y >= tl.y && pos.y < tl.y + size.y
    }

    return false
}

get_actor_at :: proc(game: ^GameState, pos: [2]int, subscale_of: ^Actor = nil) -> ^Actor {
    if actor_intersects(&game.hero, pos, subscale_of) do return &game.hero
    if actor_intersects(&game.probe, pos, subscale_of) do return &game.probe

    for npc in game.npcs {
        if actor_intersects(npc, pos, subscale_of) do return npc
    }

    return nil
}

create_game :: proc() -> (out: GameState) {
    out.uifont = rl.LoadFont("res/fonts/setback.png")
    out.turni = -1
    out.anim_progress = -1.0
    out.focus_subscale = &out.hero

    return
}

destroy_game :: proc(game: ^GameState) {
    destroy_actor(&game.probe)
    destroy_actor(&game.hero)
    for npc in game.npcs {
        destroy_actor(npc)
        free(npc)
    }
    delete(game.statuslog)
    delete(game.npcs)
    delete(game.fx)
    destroy_assets(&game.assets)
}

game_push_message :: proc(game: ^GameState, msg: cstring) {
    append(&game.statuslog, msg)
    game.lastmessage_t = rl.GetTime()
}

// If it returns true, an animation must be carried out
game_do_action :: proc(game: ^GameState, action: Action) -> bool {
    _, is_none := action.variant.(NoAction)
    if is_none {
        return false
    }

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

game_update_anim :: proc(game: ^GameState) {
    // Animate cur action
    action, is_ok := game.cur_action.(Action)
    assert(is_ok)

    if game.anim_progress >= animate_action(action, game.anim_progress) {
        for fx in game.fx {
            free(fx)
        }
        clear(&game.fx)

        // Carry out the action itself
        act_action(action)
        game.anim_progress = -1.0

    }

    game.anim_progress += rl.GetFrameTime()
}

game_update_turn :: proc(game: ^GameState) {
    for {
        if game.turni == -1 {
            // Progress in turn
            hero_action: Action
            if game.playing_subscale {
                hero_action = take_turn_probe(&game.probe)
            } else {
                hero_action = take_turn_hero(&game.hero)
            }
            _, is_none := hero_action.variant.(NoAction)
            if is_none do break // Continue processing user input
            game.turni += 1
            assert(game_do_action(game, hero_action))
            // (User actions always animate)
            break
        } else {
            // AI actions (TODO)
            if game.turni == len(game.npcs) {
                // TURN IS DONE
                free_all(context.temp_allocator)
                game.turni = -1
                break
            } else {
                action := take_turn_monster(game.npcs[game.turni])
                if game_do_action(game, action) {
                    break
                } else {
                    act_action(action)
                }
                game.npcs[game.turni].actions_taken += 1

                if game.npcs[game.turni].actions_taken > game.npcs[game.turni].actions_per_turn {
                    game.npcs[game.turni].actions_taken = 0
                    game.turni += 1
                }
            }
        }
    }
}

game_update :: proc(game: ^GameState) {
    if game.show_help {
        if rl.GetCharPressed() == '?' || rl.GetKeyPressed() == rl.KeyboardKey.ESCAPE {
            game.show_help = false
        }
    } else {
        if rl.GetCharPressed() == '?' {
            game.show_help = true
            return
        }
        if game.anim_progress >= 0 {
            game_update_anim(game)
        } else {
            game_update_turn(game)
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
    for npc in game.npcs {
        fullscale, is_fullscale := npc.scale_kind.(FullscaleActor)
        if is_fullscale {
            draw_actor(npc)
        }
    }
    for fx in game.fx {
        if fx.in_subscale == nil {
            game_draw_fx(fx)
        }
    }
    draw_world_tilemap(game.worldmap)

    rl.EndScissorMode()
    rl.EndMode2D()

}

game_create_npc :: proc(game: ^GameState) -> ^Actor {
    id := len(game.npcs)

    actor := new(NPCActor)
    actor.in_game = game
    append(&game.npcs, actor)
    return actor
}

game_draw_subscale :: proc(game: ^GameState) {
    cam: rl.Camera2D
    if rl.GetScreenWidth() > 1366 && rl.GetScreenHeight() > 768 {
        cam.zoom = 32.0
    } else {
        cam.zoom = 16.0
    }

    subscale_screen := rl.Rectangle{
        GAME_PANEL_W * f32(rl.GetScreenWidth()), 0.0,
        (1.0 - GAME_PANEL_W) * f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}

    subs := game.focus_subscale.scale_kind.(FullscaleActor).subscale
    stmap := subs.tmap
    cam.target = [2]f32{f32(stmap.width) * 0.5, f32(stmap.height) * 0.5}
    cam.offset = [2]f32{
        subscale_screen.x + subscale_screen.width * 0.5,
        subscale_screen.height * 0.5}

    ui_subscale_scissor()
    rl.BeginMode2D(cam)

    // Draw the tilemap texture
    source := rl.Rectangle{0, 0,
        -f32(stmap.width * subs.tmap.tileset_size[0]),
        f32(stmap.height * subs.tmap.tileset_size[1])
    }

    target := rl.Rectangle{
        f32(stmap.width) * 0.5, f32(stmap.height) * 0.5,
        f32(stmap.width), f32(stmap.height)}

    rl.DrawTexturePro(subs.tex.texture,
    source, target, [2]f32{f32(stmap.width) * 0.5, f32(stmap.height) * 0.5}, 180.0, rl.WHITE
    )

    // Draw the actors
    if game.probe.scale_kind.(SubscaleActor).subscale_of == game.focus_subscale {
        draw_actor(&game.probe)
    }

    for &actor in game.npcs {
        subscale, is_subscale := actor.scale_kind.(SubscaleActor)
        if is_subscale && subscale.subscale_of == game.focus_subscale {
            draw_actor(actor)
        }
    }

    for fx in game.fx {
        if fx.in_subscale == game.focus_subscale {
            game_draw_fx(fx)
        }
    }

    rl.EndMode2D()
    rl.EndScissorMode()
}


game_draw :: proc(game: ^GameState) {
    game_draw_game(game)
    game_draw_subscale(game)

    ui_draw(game)
}

game_draw_fx :: proc(fx: ^ActionFX) {
    source := fx.sprite_rect
    if source.width == 0 do source.width = f32(fx.sprite_tex.width)
    if source.height == 0 do source.height = f32(fx.sprite_tex.height)

    dest := rl.Rectangle{fx.pos.x, fx.pos.y, source.width * fx.scale, source.height * fx.scale}
    origin := [2]f32{source.width * fx.scale * 0.5, source.height * fx.scale * 0.5}

    rl.DrawTexturePro(fx.sprite_tex, source, dest, origin, fx.angle, fx.tint)
    rl.DrawCircleV(fx.pos, 0.1, rl.RED)
}