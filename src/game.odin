package src

import rl "vendor:raylib"
import "core:log"
import "core:math/linalg"

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

BuildingType :: enum {
    COLLECTOR,
    TURRET,
}

Game :: struct {
    last_income: int,
    income: int,
    turns_remain: bool,

    skip_further_anims: bool,
    start_skipping: f64,

    building: bool,
    building_cursor: [2]int,
    building_selected: BuildingType,

    uifont: rl.Font,
    assets: AssetManager,
    // Last message pushed is last message shown.
    statuslog: [dynamic]cstring,
    lastmessage_t: f64,

    worldmap: Tilemap,

    hero: HeroActor,
    probe: ProbeActor,
    npcs: [dynamic]^Actor,
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

get_actor_at :: proc(game: ^Game, pos: [2]int, subscale_of: ^Actor = nil) -> ^Actor {
    if actor_intersects(&game.hero, pos, subscale_of) do return &game.hero
    if actor_intersects(&game.probe, pos, subscale_of) do return &game.probe

    for npc in game.npcs {
        if actor_intersects(npc, pos, subscale_of) do return npc
    }

    return nil
}

create_game :: proc() -> (out: Game) {
    out.uifont = rl.LoadFont("res/fonts/setback.png")
    out.turni = -1
    out.anim_progress = -1.0
    out.focus_subscale = &out.hero

    return
}

destroy_game :: proc(game: ^Game) {
    destroy_actor(game, &game.probe)
    destroy_actor(game, &game.hero)
    for npc in game.npcs {
        destroy_actor(game, npc)
    }
    delete(game.statuslog)
    delete(game.npcs)
    delete(game.fx)
    destroy_assets(&game.assets)
}

game_push_message :: proc(game: ^Game, msg: cstring) {
    append(&game.statuslog, msg)
    game.lastmessage_t = rl.GetTime()
}

// If it returns true, an animation must be carried out
game_do_action :: proc(game: ^Game, action: Action, force_anim := false) -> bool {
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
        can_see_any |= action.force_animate
        can_see_any |= force_anim

        if can_see_any && !game.skip_further_anims {
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
        if game.focus_subscale != subscale.subscale_of || !game.playing_subscale || game.skip_further_anims {
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

game_update_anim :: proc(game: ^Game) {
    // Animate cur action
    action, is_ok := game.cur_action.(Action)
    assert(is_ok)


    t := animate_action(action, game.anim_progress)
    if rl.GetKeyPressed() != rl.KeyboardKey.KEY_NULL {
        game.anim_progress = t
        game.skip_further_anims = true
        game.start_skipping = rl.GetTime()
    }

    if game.anim_progress >= t {
        for fx in game.fx {
            free(fx)
        }
        clear(&game.fx)

        // Carry out the action itself
        act_action(action)
        game.anim_progress = -1.0

    } else {
        game.anim_progress += rl.GetFrameTime()
    }

}

game_update_turn_for :: proc(game: ^Game, actor: ^Actor, force_anim := false) -> bool {
    if actor.actions_taken >= actor.actions_per_turn do return false
    if !actor.alive do return false

    action : Action
    switch v in actor.kind {
        case ^HeroActor:
           action = take_turn_hero(v)
        case ^ProbeActor:
            action = take_turn_probe(v)
        case ^NPCActor:
            action = take_turn_monster(v)
        case ^OrganActor:
            action = take_turn_organ(v)
        case ^TurretActor:
            action = take_turn_turret(v)
    }

    game.cur_action = action

    _, is_none := action.variant.(NoAction)

    if !(ActorClass.HERO in actor.class && is_none) {
        actor.actions_taken += 1
    }
    game.turns_remain |= actor.actions_taken < actor.actions_per_turn

    if is_none do return false


    if game_do_action(game, action) {
        return true
    }

    return false
}

game_update_turn :: proc(game: ^Game) {
    for {
        if game.turni == -1 {
            // Progress in turn
            has_action := false
            if game.playing_subscale {
                has_action = game.probe.actions_taken < game.probe.actions_per_turn
            } else {
                has_action = game.hero.actions_taken < game.hero.actions_per_turn
            }
            if !has_action {
                game.turni += 1
                continue
            }

            if game.playing_subscale {
                if rl.IsKeyPressed(rl.KeyboardKey.B) {
                    // (This is not an action, as it doesn't consume turn)
                    game.building = true
                    break
                }
                game_update_turn_for(game, &game.probe, true)
            } else {
                game_update_turn_for(game, &game.hero, true)
            }

            act, is_ok := game.cur_action.(Action)
            assert(is_ok)
            no_act, is_none := act.variant.(NoAction)
            if is_none && !no_act.rest do break // Continue processing user input

            game.turni += 1

            // (User actions always animate)
            break
        } else {
            if game.turni == len(game.npcs) {
                if game.turns_remain {
                    game.turns_remain = false
                    game.turni = -1
                } else {
                    // TURN IS DONE
                    // Give some energy to probe, to prevent player from getting stuck
                    game.probe.energy += 1
                    game.probe.energy = min(game.probe.energy, game.probe.max_energy)

                    free_all(context.temp_allocator)
                    game.turni = -1
                    game.hero.actions_taken = 0
                    game.probe.actions_taken = 0
                    for &npc in game.npcs {
                        npc.actions_taken = 0
                    }
                    game.turns_remain = false
                    game.skip_further_anims = false
                    game.last_income = game.income
                    game.income = 0

                    // Remove dead actors
                    for npc in game.npcs {
                        if npc.alive do continue

                        destroy_actor(game, npc)
                    }

                    break
                }
            } else {
                brk := game_update_turn_for(game, game.npcs[game.turni])
                game.turni += 1
                if brk do break
            }
        }
    }
}

BUILDING_RADIUS :: 4

game_building_size :: proc(game: ^Game) -> [2]int {
    return [2]int{2, 2}
}

game_building_move_cursor :: proc(game: ^Game, delta: [2]int) {
    center := game.probe.pos
    npos := game.building_cursor + delta + game.probe.pos

    dx := game_building_size(game) - [2]int{1, 1}
    dv1 := linalg.to_f32(npos - game.probe.pos)
    dv2 := linalg.to_f32([2]int{dx.x, 0} + npos - game.probe.pos)
    dv3 := linalg.to_f32([2]int{0, dx.y} + npos - game.probe.pos)
    dv4 := linalg.to_f32(dx + npos - game.probe.pos)
    if  linalg.length(dv1) <= BUILDING_RADIUS &&
        linalg.length(dv2) <= BUILDING_RADIUS &&
        linalg.length(dv3) <= BUILDING_RADIUS &&
        linalg.length(dv4) <= BUILDING_RADIUS {

        game.building_cursor += delta
    }
}

game_building_valid_placement :: proc(game: ^Game) -> bool {
    sx := game.building_cursor + game.probe.pos
    sz := game_building_size(game)

    sscale_actor := game.probe.scale_kind.(SubscaleActor).subscale_of
    sscale := sscale_actor.scale_kind.(FullscaleActor).subscale

    for dx := 0; dx < sz.x; dx += 1 {
        for dy := 0; dy < sz.y; dy += 1 {
            p := sx + [2]int{dx, dy}

            if tilemap_tile_collides(sscale.tmap, p) {
                return false
            }
            if get_actor_at(game, p, sscale_actor) != nil {
                return false
            }
            if subscale_wire_at(&sscale, p) != nil {
                return false
            }
        }
    }

    return true
}

game_build_building :: proc(game: ^Game) {
    if !game_building_valid_placement(game) do return

    focus := game.probe.scale_kind.(SubscaleActor).subscale_of
    pos := game.building_cursor + game.probe.pos
    switch game.building_selected {
    case .COLLECTOR:
        if game.probe.energy > 4 {
            create_collector(game, pos + [2]int{1, 1}, focus)
            game.probe.energy -= 4
        } else {
            game_push_message(game, "Unable to build collector, need 4 energy in probe!")
        }
    case .TURRET:
        if game.probe.energy > 7 {
            create_turret(game, pos + [2]int{1, 1}, focus)
            game.probe.energy -= 7
        } else {
            game_push_message(game, "Unable to build turret, need 7 energy in probe!")
        }
    }
}

game_update_building :: proc(game: ^Game) {
    if rl.IsKeyPressed(rl.KeyboardKey.B) {
        game.building = false
    }

    if rl.IsKeyPressed(rl.KeyboardKey.H) {
        game_building_move_cursor(game, [2]int{-1, 0})
    }
    if rl.IsKeyPressed(rl.KeyboardKey.J) {
        game_building_move_cursor(game, [2]int{0, 1})
    }
    if rl.IsKeyPressed(rl.KeyboardKey.K) {
        game_building_move_cursor(game, [2]int{0, -1})
    }
    if rl.IsKeyPressed(rl.KeyboardKey.L) {
        game_building_move_cursor(game, [2]int{1, 0})
    }

    if rl.IsKeyPressed(rl.KeyboardKey.T) {
        game.building_selected = .TURRET
    }
    if rl.IsKeyPressed(rl.KeyboardKey.C) {
        game.building_selected = .COLLECTOR
    }

    if rl.IsKeyPressed(rl.KeyboardKey.ENTER) {
        game_build_building(game)
    }
}

game_update :: proc(game: ^Game) {

    if game.show_help {
        if rl.GetCharPressed() == '?' || rl.GetKeyPressed() == rl.KeyboardKey.ESCAPE {
            game.show_help = false
        }
    } else {
        if rl.GetCharPressed() == '?' {
            game.show_help = true
            return
        }
        if game.building {
            game_update_building(game)
        } else {
            if game.anim_progress >= 0 {
                game_update_anim(game)
            } else {
                game_update_turn(game)
            }
        }
    }
}

game_draw_game :: proc(game: ^Game) {
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
        if !npc.alive do continue
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

    rl.EndMode2D()

    msize := [2]i32{i32(game.worldmap.width * 3), i32(game.worldmap.height * 3)}
    off := [2]i32{i32(game_screen.width), i32(game_screen.height)} - msize
    preview_wall(game.worldmap.walls[:], game.worldmap.width, off, rl.GRAY, game.hero.pos)

    if game.playing_subscale {
        rl.DrawRectangleRec(game_screen, rl.ColorAlpha(rl.GRAY, 0.3))
    }
    rl.EndScissorMode()

}

game_create_npc :: proc(game: ^Game, $T: typeid) -> ^T {
    id := len(game.npcs)

    actor := new(T)
    actor.kind = actor
    actor.in_game = game
    append(&game.npcs, (^Actor)(actor))
    return actor
}

game_draw_subscale :: proc(game: ^Game) {
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

    for &wire in subs.wire {
        subscale_wire_draw(&wire)
    }


    for &actor in game.npcs {
        if !actor.alive do continue
        subscale, is_subscale := actor.scale_kind.(SubscaleActor)
        if is_subscale && subscale.subscale_of == game.focus_subscale {
            draw_actor(actor)
        }
    }

    // Draw the actors
    if game.probe.scale_kind.(SubscaleActor).subscale_of == game.focus_subscale {
        draw_actor(&game.probe)
    }

    if game.building {
        for x := -BUILDING_RADIUS; x <= BUILDING_RADIUS; x+=1 {
            for y := -BUILDING_RADIUS; y <= BUILDING_RADIUS; y+=1 {
                p := linalg.to_f32(game.probe.pos + [2]int{x, y})
                if linalg.length(p - linalg.to_f32(game.probe.pos)) < BUILDING_RADIUS {
                    rl.DrawRectangleV(p, [2]f32{1, 1}, rl.ColorAlpha(rl.WHITE, 0.1))
                }
            }
        }

        p := linalg.to_f32(game.probe.pos + game.building_cursor)
        s := linalg.to_f32(game_building_size(game))
        tex: rl.Texture2D
        switch game.building_selected {
        case .COLLECTOR:
            tex = get_texture(&game.assets, "res/agents/energy_collector.png")
        case .TURRET:
            tex = get_texture(&game.assets, "res/agents/turret.png")
        }
        tint := rl.GRAY
        if !game_building_valid_placement(game) {
            tint = rl.RED
        }

        rl.DrawTexturePro(tex,
            rl.Rectangle{0.0, 0.0, f32(tex.width), f32(tex.height)},
            rl.Rectangle{p.x, p.y, s.x, s.y},
            [2]f32{0.0, 0.0}, 0.0, rl.ColorAlpha(tint, 0.8))
    }

    for fx in game.fx {
        if fx.in_subscale == game.focus_subscale {
            game_draw_fx(fx)
        }
    }

    rl.EndMode2D()

    if !game.playing_subscale {
        rl.DrawRectangleRec(subscale_screen, rl.ColorAlpha(rl.GRAY, 0.3))
    }

    rl.EndScissorMode()
}


game_draw :: proc(game: ^Game) {
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
    //rl.DrawCircleV(fx.pos, 0.1, fx.tint)
}