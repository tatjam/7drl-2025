package src

import rl "vendor:raylib"
import "core:math/linalg"
import "core:math"
import "core:log"

// Default action does nothing
Action :: struct {
    by_actor: ^Actor,
    need_see: [dynamic][2]int,
    force_animate: bool,
    variant: union{
        NoAction, MoveAction, TurnAction, ShootProbeAction, DummyAnimateAction,
        ChargeSuckAction}
}

MoveAction :: struct {
    startpos: [2]int,
    endpos: [2]int,
    swap_actor: ^Actor,
    swap_pos: [2]int,
}

TurnAction :: struct {
    dir: Direction
}

DummyAnimateAction :: struct {
    wait: f32,
}

// This doesn't imply a "rest", it implies that no action
// was performed. In the hero, this will wait for input
NoAction :: struct {
    rest: bool,
}


ChargeSuckAction :: struct {
    wire: ^SubscaleWire,
    pos: [2]int,
    charge_index: int,
    to_probe: ^ProbeActor,
}

dummy_animate_action :: proc(by: ^Actor, time: f32 = 0.0) -> (out: Action) {
    out.variant = DummyAnimateAction{wait = time}
    out.force_animate = true
    out.by_actor = by
    return
}

no_action :: proc(rest := false) -> (out: Action) {
    out.variant = NoAction{rest=rest}
    return
}

delta_to_dir :: proc(delta: [2]$T) -> Direction {
    dir := Direction.NORTH
    if abs(delta.x) > abs(delta.y) {
        if delta.x > 0 {
            dir = .EAST
        } else {
            dir = .WEST
        }
    } else {
        if delta.y > 0 {
            dir = .SOUTH
        } else {
            dir = .NORTH
        }
    }

    return dir
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

    subscale, is_subscale := actor.scale_kind.(SubscaleActor)
    wmap := actor.in_game.worldmap
    sof : ^Actor = nil
    if is_subscale {
        wmap = subscale.subscale_of.scale_kind.(FullscaleActor).subscale.tmap
        sof = subscale.subscale_of
    } else {
        // Check that we have enough energy in engines
        self_subscale := actor.scale_kind.(FullscaleActor).subscale

        found_any := false
        for engine in self_subscale.engines {
            if engine.energy > 0 {
                found_any = true
                break
            }
        }

        if !found_any {
            if actor == &actor.in_game.hero {
                game_push_message(actor.in_game, "Unable to move, not enough energy in engines!")
                return no_action(true)
            }
        }
    }

    swap_actor: ^Actor = nil
    swap_pos: [2]int

    prevp := np

    for ;i <= steps; i+=1 {
        prevp = np
        np = np + delta * i

        if np.x < 0 || np.y < 0 || np.x >= wmap.width || np.y >= wmap.height {
            break
        }

        if i >= 1 {
            if tilemap_tile_collides(wmap, np) do break
        }

        act := get_actor_at(actor.in_game, np, sof)
        if i >= 1 && act != nil && act.impedes_movement &&
            !(act.swappable && .HERO in actor.class) {

            break
        }

        endpos = np
        append(&visited, np)

        if i >= 1 && act != nil && act.impedes_movement && (act.swappable && .HERO in actor.class) {
            swap_actor = act
            swap_pos = prevp
            break
        }
    }


    if endpos == actor.pos {
        return no_action()
    }


    return Action{by_actor = actor, need_see = visited, variant = MoveAction{
        startpos = actor.pos,
        endpos = np,
        swap_actor = swap_actor,
        swap_pos = swap_pos,
    }}

}

animate_charge_suck_action :: proc(action: Action, prog: f32) -> f32 {
    CHARGE_SUCK_ANIM_TIME :: 0.15
    game := action.by_actor.in_game
    suck := action.variant.(ChargeSuckAction)

    if len(game.fx) == 0 {
        fx := new(ActionFX)
        fx.in_subscale = action.by_actor.scale_kind.(SubscaleActor).subscale_of
        fx.pos = linalg.to_f32(suck.pos)
        fx.sprite_tex = get_texture(&game.assets, "res/charge.png")
        fx.scale = 0.1
        fx.tint = rl.WHITE
        append(&game.fx, fx)
    }
    fx := game.fx[0]

    delta := linalg.to_f32(action.by_actor.pos - suck.pos)
    fx.pos = linalg.to_f32(suck.pos) + delta * prog / CHARGE_SUCK_ANIM_TIME
    fx.pos += [2]f32{0.5, 0.5}

    return CHARGE_SUCK_ANIM_TIME
}

animate_move_action :: proc(action: Action, prog: f32) -> f32 {
    MOVE_ANIM_TIME :: 0.1
    SUBSCALE_MOVE_ANIM_TIME :: 0.03

    _, is_subscale := action.by_actor.scale_kind.(SubscaleActor)
    t : f32 = SUBSCALE_MOVE_ANIM_TIME if is_subscale else MOVE_ANIM_TIME

    move := action.variant.(MoveAction)
    delta := linalg.to_f32(move.endpos - move.startpos)

    action.by_actor.doffset = prog / t * delta

    if move.swap_actor != nil {
        delta_swap := linalg.to_f32(move.swap_pos - move.swap_actor.pos)
        move.swap_actor.doffset = prog / t * delta_swap
    }
    // TODO: This feels clumsy
    //return 0.0
    return t
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

act_charge_suck_action :: proc(action: Action) {
    suck := action.variant.(ChargeSuckAction)
    unordered_remove(&suck.wire.charges, suck.charge_index)
    if suck.to_probe.energy == suck.to_probe.max_energy {
        // Give energy to cortex
        suck.to_probe.cortex.extra_energy += 1
        hero_fscale := suck.to_probe.in_game.hero.scale_kind.(FullscaleActor)
        sucked_from := action.by_actor.scale_kind.(SubscaleActor).subscale_of

        if suck.to_probe.cortex == hero_fscale.subscale.cortex {
            suck.to_probe.in_game.income += 1
        }
        if sucked_from != suck.to_probe.cortex.scale_kind.(SubscaleActor).subscale_of {
            // Damage, as we take energy away
            sucked_from.health -= 1
        }
    } else {
        suck.to_probe.energy += 1
    }
}

act_move_action :: proc(action: Action) {
    move := action.variant.(MoveAction)
    action.by_actor.pos = move.endpos
    action.by_actor.doffset = [2]f32{0.0, 0.0}

    if move.swap_actor != nil {
        move.swap_actor.pos = move.swap_pos
        move.swap_actor.doffset = [2]f32{0.0, 0.0}
    }

    fscale, is_fullscale := action.by_actor.scale_kind.(FullscaleActor)
    if is_fullscale {
        self_subscale := fscale.subscale
        for engine in self_subscale.engines {
            if engine.energy > 0 {
                engine.energy -= 1
                break
            }
        }
    }

}

act_turn_action :: proc(action: Action) {
    turn := action.variant.(TurnAction)
    action.by_actor.dir = turn.dir
    action.by_actor.drotate = 0.0
}

// Return the time required to complete anim, 0 if it has no animation
animate_action :: proc(action: Action, prog: f32) -> f32 {
// TODO: These could use var instead of action
    switch var in action.variant {
    case MoveAction:
        return animate_move_action(action, prog)
    case TurnAction:
        return animate_turn_action(action, prog)
    case ShootProbeAction:
        return animate_shoot_probe_action(action, prog)
    case DummyAnimateAction:
        return var.wait
    case ChargeSuckAction:
        return animate_charge_suck_action(action, prog)
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
    case ChargeSuckAction:
        act_charge_suck_action(action)
    case DummyAnimateAction:
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
}

shoot_probe_action_return :: proc(actor: ^Actor) -> (out: Action) {
    out.by_actor = actor
    if actor == actor.in_game.focus_subscale do return no_action()

    out.need_see = make([dynamic][2]int, context.temp_allocator)
    append(&out.need_see, actor.pos)

    out.variant = ShootProbeAction{startpos=actor.in_game.focus_subscale.pos, endpos=actor.pos, hit=actor}

    return

}

shoot_probe_action :: proc(actor: ^Actor, dir: Direction) -> (out: Action) {
    if actor.in_game.focus_subscale != actor {
        return shoot_probe_action_return(actor)
    }

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
        if tilemap_tile_collides(actor.in_game.worldmap, pos) do break

        hit = get_actor_at(actor.in_game, pos, nil)
        if hit != nil do break
    }

    out.variant = ShootProbeAction{startpos=actor.pos, endpos=pos, hit=hit}

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
        // Find entrypoint from direction
        delta := linalg.to_f32(shoot.endpos - shoot.startpos)
        dir := delta_to_dir(delta)
        // But ofcourse, entity is rotated
        dir = entrydir(dir, shoot.hit.dir)

        if shoot.hit == &game.hero {
            game_push_message(game, "The scale probe returns!")
        } else {
            game_push_message(game, "The scale probe hits a target!")
            game.playing_subscale = true
        }
        pos :=  tilemap_find_spawn_pos_dir(game, shoot.hit, dir)
        subs := &game.probe.scale_kind.(SubscaleActor)
        subs.subscale_of = shoot.hit
        game.probe.pos = pos
        game.focus_subscale = shoot.hit
    }

}