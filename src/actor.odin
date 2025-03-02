package src

import rl "vendor:raylib"
import "core:math/linalg"

Direction :: enum {
    NORTH,
    EAST,
    SOUTH,
    WEST
}

// If we are not a subscale actor, we must have
// such a map
SubscaleMap :: struct {
    tmap: Tilemap,

}

SubscaleActor :: struct {
    subscale_of: ^Actor
}

FullscaleActor :: struct {
    subscale: SubscaleMap
}

Actor :: struct {
    alive: bool,
    pos: [2]int,
    // Offset while drawing, for animation
    doffset: [2]f32,
    drotate: f32,

    sprite: rl.Texture2D,
    sprite_rect: rl.Rectangle,

    dir: Direction,
    in_game: ^GameState,

    scale_kind: union #no_nil{
        FullscaleActor,
        SubscaleActor
    },
}

// The hero is the player controllable entity.
HeroActor :: struct {
    using base: Actor
}

ProbeActor :: struct {
    using base: Actor
}

MonsterActor :: struct {
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
    out.alive = true
    out.sprite = get_texture(&game.assets, "res/agents/player.png")
    out.sprite_rect = rl.Rectangle{0, 0, f32(out.sprite.width), f32(out.sprite.height)}

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

take_turn_monster :: proc(actor: ^MonsterActor) -> Action {
    return no_action()
}

create_subscale_map :: proc(for_actor: ^Actor, fname: string) {

}

draw_actor :: proc(actor: ^Actor) {
    pos := actor_get_draw_pos(actor^)
    target_rect := rl.Rectangle{pos.x, pos.y, 1.0, 1.0}
    rot : f32
    switch actor.dir {
    case .NORTH:
        rot = 0.0
    case .EAST:
        rot = 90.0
    case .SOUTH:
        rot = 180.0
    case .WEST:
        rot = 270.0
    }
    rl.DrawTexturePro(actor.sprite,
        actor.sprite_rect, target_rect,
        [2]f32{0.5, 0.5},
        rot + actor.drotate,
        rl.WHITE
        )
}

