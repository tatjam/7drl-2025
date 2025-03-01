package src

import rl "vendor:raylib"
import c "core:c"

// The UI consits of the main panel, where the world can be seen,
// a bottom panel of status messages and a right panel where the user
// can access his inventory, health status, and so on...

statuspanel_draw :: proc(game: ^GameState, starth, endw: c.int) {
    rl.DrawRectangleLines(0, starth, endw, rl.GetScreenHeight() - starth, rl.WHITE)
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