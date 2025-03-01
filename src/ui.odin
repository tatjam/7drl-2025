package src

import rl "vendor:raylib"
import c "core:c"

// The UI consits of the main panel, where the world can be seen,
// a bottom panel of status messages and a right panel where the user
// can access his inventory, health status, and so on...

statuspanel_draw :: proc(game: ^GameState, starth, endw: c.int) {
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

userpanel_draw :: proc(game: ^GameState, startw: c.int) {
    rl.DrawRectangleLines(startw, 0, rl.GetScreenWidth() - startw, rl.GetScreenHeight(), rl.WHITE)

}

ui_draw :: proc(game: ^GameState) {
    wf := f32(rl.GetScreenWidth())
    hf := f32(rl.GetScreenHeight())

    userpanel_draw(game, c.int(0.6 * wf))
    statuspanel_draw(game, c.int(0.7 * hf), c.int(0.6 * wf))


}