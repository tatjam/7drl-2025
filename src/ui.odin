package src

import rl "vendor:raylib"
import c "core:c"
import "core:fmt"

GAME_PANEL_W :: 0.56
GAME_PANEL_H :: 0.7
STATUS_PANEL_W :: 0.4

// The UI consits of the main panel, where the world can be seen,
// a bottom panel of status messages and player status
// and the right panel for subscale probe

statuspanel_draw :: proc(game: ^Game, starth, endw: c.int) {
    h := rl.GetScreenHeight() - starth
    rl.DrawRectangleLines(0, starth, endw, h, rl.WHITE)

    rl.BeginScissorMode(0, starth, endw, rl.GetScreenHeight())
    msg_h := int(game.uifont.baseSize)

    recent := rl.GetTime() - game.lastmessage_t < 1.0

    for i := 0; i < len(game.statuslog); i+=1 {
        ri := len(game.statuslog) - 1 - i
        if ri >= 0 {
            yoff := int(rl.GetScreenHeight()) - msg_h * (i + 1) - 5
            pos := [2]f32{0.0, f32(yoff)}
            tint := rl.GRAY
            if recent && i == 0 {
                tint = rl.WHITE
            }
            rl.DrawTextEx(game.uifont, game.statuslog[ri], pos, f32(game.uifont.baseSize), 4, tint)
        }
    }
    rl.EndScissorMode()
}

scalepanel_draw :: proc(game: ^Game, startw: c.int, endh: c.int) {
    rl.DrawRectangleLines(startw, 0, rl.GetScreenWidth() - startw, endh, rl.WHITE)
}

BIG_SKIP :: 14.0
SKIP :: 12.0

userpanel_summary :: proc(game: ^Game, actor: ^Actor, sscale: ^SubscaleMap, w: f32, h: ^f32) {

    tot_engine_energy := 0
    tot_max_engine_energy := 0
    tot_radar_energy := 0
    tot_max_radar_energy := 0
    tot_factory_energy := 0
    tot_max_factory_energy := 0
    for engine in sscale.engines {
        tot_engine_energy += engine.energy
        tot_max_engine_energy += engine.max_energy
    }
    for radar in sscale.radars {
        tot_radar_energy += radar.energy
        tot_max_radar_energy += radar.max_energy
    }
    for factory in sscale.factories {
        tot_factory_energy += factory.energy
        tot_max_factory_energy += factory.max_energy
    }

    str := fmt.ctprint(" Health", actor.health)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h^}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h^ += SKIP
    str = fmt.ctprint(" Engine", tot_engine_energy, "/", tot_max_engine_energy)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h^}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h^ += SKIP
    str = fmt.ctprint(" Radar", tot_radar_energy, "/", tot_max_radar_energy)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h^}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h^ += SKIP
    str = fmt.ctprint(" Factory", tot_factory_energy, "/", tot_max_factory_energy)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h^}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h^ += SKIP
}

userpanel_draw :: proc(game: ^Game, startw: c.int, starth: c.int, endw: c.int) {
    rl.DrawRectangleLines(startw, starth,
        endw - startw, rl.GetScreenHeight() - starth, rl.WHITE)


    // Self-energy
    h := f32(starth)
    w := f32(startw + 4.0);

    str := fmt.ctprint("Probe: ", game.probe.energy, "/", game.probe.max_energy)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h += BIG_SKIP

    str = fmt.ctprint("Income: ", game.last_income)
    rl.DrawTextEx(game.uifont, str, [2]f32{w, h}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h += BIG_SKIP

    rl.DrawTextEx(game.uifont, "Self", [2]f32{w, h}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h += BIG_SKIP

    self_scale := game.hero.scale_kind.(FullscaleActor).subscale
    userpanel_summary(game, &game.hero, &self_scale, w, &h)



    // Target-energy
    rl.DrawTextEx(game.uifont, "Target", [2]f32{w, h}, f32(game.uifont.baseSize), 4, rl.WHITE)
    h += BIG_SKIP


    if game.focus_subscale != nil && game.focus_subscale != &game.hero {
        fscale := game.focus_subscale.scale_kind.(FullscaleActor).subscale
        userpanel_summary(game, game.focus_subscale, &fscale, w, &h)
    }

}

helppanel_draw :: proc(game: ^Game, marginw: c.int, marginh: c.int) {
    if game.show_help {
        rl.DrawRectangle(marginw, marginh,
            rl.GetScreenWidth() - 2 * marginw,
            rl.GetScreenHeight() - 2 * marginh,
            rl.BLACK)
        rl.DrawRectangleLines(marginw, marginh,
            rl.GetScreenWidth() - 2 * marginw,
            rl.GetScreenHeight() - 2 * marginh,
            rl.WHITE)

    }
}

ui_draw :: proc(game: ^Game) {
    wf := f32(rl.GetScreenWidth())
    hf := f32(rl.GetScreenHeight())

    scalepanel_draw(game, c.int(GAME_PANEL_W * wf), c.int(hf))
    userpanel_draw(game, c.int(STATUS_PANEL_W * wf), c.int(GAME_PANEL_H * hf), c.int((GAME_PANEL_W) * wf))
    statuspanel_draw(game, c.int(GAME_PANEL_H * hf), c.int(STATUS_PANEL_W * wf))
    helppanel_draw(game, c.int(0.2 * wf), c.int(0.2 * hf))
}

ui_game_scissor :: proc() {
    wf := f32(rl.GetScreenWidth())
    hf := f32(rl.GetScreenHeight())

    rl.BeginScissorMode(0, 0, c.int(GAME_PANEL_W*wf), c.int(GAME_PANEL_H*hf))
}

ui_subscale_scissor :: proc() {
    wf := f32(rl.GetScreenWidth())
    hf := f32(rl.GetScreenHeight())

    rl.BeginScissorMode(c.int(GAME_PANEL_W*wf), 0, c.int(wf - GAME_PANEL_W*wf), c.int(hf))
}
