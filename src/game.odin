package src

import rl "vendor:raylib"

GameState :: struct {
    uifont: rl.Font,
    // Last message pushed is last message shown.
    statuslog: [dynamic]cstring,
    lastmessage_t: f64
}

create_game :: proc() -> (out: GameState) {
    out.uifont = rl.LoadFont("res/fonts/setback.png")

    return
}

game_push_message :: proc(game: ^GameState, msg: cstring) {
    append(&game.statuslog, msg)
    game.lastmessage_t = rl.GetTime()
}
