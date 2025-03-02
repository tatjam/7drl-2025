package src

import rl "vendor:raylib"
import "core:math/linalg"

Direction :: enum {
    NORTH,
    EAST,
    SOUTH,
    WEST
}


Actor :: struct {
    pos: [2]int,
    // Offset while drawing, for animation
    doffset: [2]f32,
    drotate: f32,

    dir: Direction,
    in_game: ^GameState,
}

HeroActor :: struct {
    using base: Actor
}

// Returns CENTER of the actor
actor_get_draw_pos :: proc(actor: Actor) -> [2]f32 {
    return linalg.to_f32(actor.pos) + actor.doffset + [2]f32{0.5, 0.5}
}

create_hero :: proc(game: ^GameState, pos: [2]int) -> (out: HeroActor) {
    out.in_game = game
    out.pos = pos
    out.dir = .NORTH

    return
}

take_turn_hero :: proc(actor: ^HeroActor) -> Action {
    // HJKL turning / motion
    // Shift+HJKL turning only
    dir : Direction

    if rl.IsKeyPressed(.H) {
        dir = .WEST
    } else if rl.IsKeyPressed(.J) {
        dir = .SOUTH
    } else if rl.IsKeyPressed(.K) {
        dir = .NORTH
    } else if rl.IsKeyPressed(.L) {
        dir = .EAST
    } else do return no_action()


    if actor.dir == dir || rl.IsKeyDown(.LEFT_SHIFT) {
        return move_action(actor, dir, 1)
    } else {
        if dir == actor.dir do return no_action()

        return turn_action(actor, dir)
    }

    return no_action()

}

