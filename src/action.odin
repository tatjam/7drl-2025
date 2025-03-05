package src

import rl "vendor:raylib"
import "core:math/linalg"
import "core:math"

// Default action does nothing
Action :: struct {
    by_actor: ^Actor,
    need_see: [dynamic][2]int,
    variant: union{NoAction, MoveAction, TurnAction, ShootProbeAction}
}

MoveAction :: struct {
    startpos: [2]int,
    endpos: [2]int
}

TurnAction :: struct {
    dir: Direction
}

// This doesn't imply a "rest", it implies that no action
// was performed. In the hero, this will wait for input
NoAction :: struct {
}




no_action :: proc() -> (out: Action) {
    out.variant = NoAction{}
    return
}

dir_to_delta :: proc(dir: Direction) -> [2]int {
    delta: [2]int
    switch dir {
    case .NORTH:
        delta = [2]int{0, -1}
    case .EAST:
        delta = [2]int{1, 0}
    case .SOUTH:
        delta = [2]int{0, 1}
    case .WEST:
        delta = [2]int{-1, 0}
    }
    return delta
}

// Clamps to prevent skipping walls
move_action :: proc(actor: ^Actor, dir: Direction, steps: int) -> Action {
    // Check for collision
    delta := dir_to_delta(dir)

    i := 0
    np := actor.pos
    endpos := actor.pos
    visited := make([dynamic][2]int, context.temp_allocator)

    for ;i <= steps; i+=1 {
        np = np + delta * i
        wmap := &actor.in_game.worldmap

        if np.x < 0 || np.y < 0 || np.x >= wmap.width || np.y >= wmap.height {
            break
        }

        if wmap.walls[np.y * wmap.width + np.x] {
            break
        }

        endpos = np
        append(&visited, np)
    }


    if endpos == actor.pos {
        return no_action()
    }


    return Action{by_actor = actor, need_see = visited, variant = MoveAction{
        startpos = actor.pos,
        endpos = np
    }}

}

animate_move_action :: proc(action: Action, prog: f32) -> f32 {
    MOVE_ANIM_TIME :: 0.15
    move := action.variant.(MoveAction)
    delta := linalg.to_f32(move.endpos - move.startpos)

    action.by_actor.doffset = prog / MOVE_ANIM_TIME * delta

    return MOVE_ANIM_TIME
}

animate_turn_action :: proc(action: Action, prog: f32) -> f32 {
    ROT_ANIM_TIME :: 0.1
    rot := action.variant.(TurnAction)

    rot_span := f32((int(rot.dir) - int(action.by_actor.dir)) % 4) * 90.0
    if rot_span > 180.0 {
        rot_span = -90.0
    } else if rot_span < -180.0 {
        rot_span = 90.0
    }

    action.by_actor.drotate = prog / ROT_ANIM_TIME * rot_span

    return ROT_ANIM_TIME
}

act_move_action :: proc(action: Action) {
    move := action.variant.(MoveAction)
    action.by_actor.pos = move.endpos
    action.by_actor.doffset = [2]f32{0.0, 0.0}
}

act_turn_action :: proc(action: Action) {
    turn := action.variant.(TurnAction)
    action.by_actor.dir = turn.dir
    action.by_actor.drotate = 0.0
}

// Return the time required to complete anim, 0 if it has no animation
animate_action :: proc(action: Action, prog: f32) -> f32 {
    switch var in action.variant {
    case MoveAction:
        return animate_move_action(action, prog)
    case TurnAction:
        return animate_turn_action(action, prog)
    case ShootProbeAction:
        return animate_shoot_probe_action(action, prog)
    case NoAction:
        assert(false)
        return 0.0
    case:
        return 0.0
    }
}

act_action :: proc(action: Action) {
    switch var in action.variant {
    case MoveAction:
        act_move_action(action)
    case TurnAction:
        act_turn_action(action)
    case ShootProbeAction:
        act_shoot_probe_action(action)
    case NoAction:
    case:
    }
}

turn_action :: proc(actor: ^Actor, dir: Direction) -> (out: Action) {
    out.by_actor = actor
    out.need_see = make([dynamic][2]int, context.temp_allocator)
    append(&out.need_see, actor.pos)

    out.variant = TurnAction{dir = dir}
    return
}

ShootProbeAction :: struct {
    startpos: [2]int,
    endpos: [2]int,
    hit: ^Actor,
    dir: Direction,
}

shoot_probe_action :: proc(actor: ^Actor, dir: Direction) -> (out: Action) {
    out.by_actor = actor
    out.need_see = make([dynamic][2]int, context.temp_allocator)
    append(&out.need_see, actor.pos)
    pos := actor.pos
    hit: ^Actor = nil

    w := actor.in_game.worldmap.width
    h := actor.in_game.worldmap.height

    for {
        pos += dir_to_delta(dir)
        if pos.x < 0 || pos.y < 0 || pos.x > w || pos.y > h do break
        if actor.in_game.worldmap.walls[pos.y * w + pos.x] do break

        hit = get_actor_at(actor.in_game, pos, nil)
        if hit != nil do break
    }

    out.variant = ShootProbeAction{startpos=actor.pos, endpos=pos, hit=hit, dir = dir}

    return
}

animate_shoot_probe_action :: proc(action: Action, prog: f32) -> f32 {
    SHOOT_STEP_TIME :: 0.15
    shoot := action.variant.(ShootProbeAction)

    game := action.by_actor.in_game

    if len(game.fx) == 0 {
        fx := new(ActionFX)
        fx.pos = linalg.to_f32(shoot.startpos)
        fx.sprite_tex = get_texture(&game.assets, "res/fx/probe.png")
        fx.scale = 0.05
        fx.tint = rl.WHITE
        append(&game.fx, fx)
    }
    fx := game.fx[0]

    delta := linalg.to_f32(shoot.endpos - shoot.startpos)
    dist := linalg.length(delta)
    fx.pos = linalg.to_f32(shoot.startpos) + delta * prog / (SHOOT_STEP_TIME * dist)
    fx.pos += [2]f32{0.5, 0.5}
    fx.angle = math.to_degrees(math.atan2(delta.y, delta.x)) + 90.0

    return dist * SHOOT_STEP_TIME
}

act_shoot_probe_action :: proc(action: Action) {
    shoot := action.variant.(ShootProbeAction)
    game := action.by_actor.in_game


    if shoot.hit == nil {
        game_push_message(game, "The scale probe doesn't hit a valid target")
    } else {
        game_push_message(game, "The scale probe hits a target!")
    }

}