package src

import rl "vendor:raylib"
import "core:math/linalg"

// Default action does nothing
Action :: struct {
    by_actor: ^Actor,
    need_see: [dynamic][2]int,
    variant: union{MoveAction, TurnAction, NoAction}
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

// Clamps to prevent skipping walls
move_action :: proc(actor: ^Actor, dir: Direction, steps: int) -> Action {
    // Check for collision
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
