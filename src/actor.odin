package src

import rl "vendor:raylib"
import "core:math/linalg"
import "core:math/rand"
import "core:c"
import "core:log"

SUBSCALE_ACTIONS_PER_TURN :: 8

Direction :: enum {
    NORTH,
    EAST,
    SOUTH,
    WEST
}

oppositedir :: proc(dir: Direction) -> Direction {
    switch dir {
    case .NORTH:
        return .SOUTH
    case .EAST:
        return .WEST
    case .SOUTH:
        return .NORTH
    case .WEST:
        return .EAST
    }
    assert(false)
    return .NORTH
}

// There's likely a cleaner way to do this lol
entrydir :: proc(movedir: Direction, rot: Direction) -> Direction {
    relativedir := Direction(abs(int(movedir - rot) % 4))
    return oppositedir(relativedir)
}

SubscaleWire :: struct {
    start_actor: ^OrganActor,
    end_actor: ^OrganActor,
    steps: [dynamic][2]int,
    // Progress along length of wire
    charges: [dynamic]int,
    charge_tex: rl.Texture2D,
}

subscale_wire_update :: proc(wire: ^SubscaleWire) {
    if wire.start_actor.energy > 0 {
        append(&wire.charges, 0)
        wire.start_actor.energy -= 1
    }

    for i := 0; i < len(wire.charges); {
        if wire.charges[i] > len(wire.steps) {
            unordered_remove(&wire.charges, i)
            wire.end_actor.energy += 1
        } else {
            wire.charges[i] += 1
            i += 1
        }
    }
}

subscale_wire_draw :: proc(wire: ^SubscaleWire) {
    scale := 1.0 / f32(wire.charge_tex.width)

    for charge in wire.charges {
        if charge < len(wire.steps) && charge > 0 {
            pos := linalg.to_f32(wire.steps[charge])

            rl.DrawTextureEx(wire.charge_tex, pos, 0.0, scale, rl.WHITE)
        }
    }
}

subscale_wire_at :: proc(scale: ^SubscaleMap, pos: [2]int) -> ^SubscaleWire {
    // TODO: This could be a bit different
    for &wire in scale.wire {
        for step in wire.steps {
            if step == pos {
                return &wire
            }
        }
    }

    return nil
}

// If we are not a subscale actor, we must have
// such a map
SubscaleMap :: struct {
    tmap: Tilemap,
    tex: rl.RenderTexture,
    wire: [dynamic]SubscaleWire,

    cortex: ^OrganActor,
    engines: [dynamic]^OrganActor,
    radars: [dynamic]^OrganActor,
    factories: [dynamic]^OrganActor,
}

SubscaleActor :: struct {
    subscale_of: ^Actor,
}

FullscaleActor :: struct {
    subscale: SubscaleMap,
}

ActorClass :: enum {
    HERO,
    FRIENDLY,
    HOSTILE,
    TURRET,
    ENVIRONMENT,
}

Actor :: struct {
    // If set to 0, an action will take place eitherway
    actions_per_turn: int,
    actions_taken: int,
    swappable: bool,

    impedes_movement: bool,

    class: bit_set[ActorClass],
    alive: bool,
    pos: [2]int,
    // Offset while drawing, for animation
    doffset: [2]f32,
    drotate: f32,

    sprite: rl.Texture2D,
    sprite_rect: rl.Rectangle,
    sprite_size: [2]int,

    // For sprites which have different directions based on sprite
    ignore_dir_graphics: bool,
    dir: Direction,
    in_game: ^Game,

    scale_kind: union #no_nil{
        FullscaleActor,
        SubscaleActor
    },

    kind: union {
        ^HeroActor,
        ^ProbeActor,
        ^NPCActor,
        ^OrganActor,
        ^TurretActor,
    }
}

// The hero is the player controllable entity.
HeroActor :: struct {
    using base: Actor
}

ProbeActor :: struct {
    using base: Actor
}

NPCState :: struct {

}

ChaserAI :: struct {
    max_turns_without_vision:int,

    turns_without_vision: int,
    last_seen: [2]int,
    min_dist: f32,
}

TargetAI :: union {
    ChaserAI,
}

RandomMoveAI :: struct {

}

LoiterAI :: union {
    RandomMoveAI
}

AttackAI :: union {
}


NPCActor :: struct {
    target_ai: TargetAI,
    loiter_ai: LoiterAI,
    attack_ai: AttackAI,

    target_acquire_class: bit_set[ActorClass],

    target: ^Actor,
    require_los: bool,

    using base: Actor
}

OrganKind :: enum {
    CORTEX,
    ENGINE,
    RADAR,
    FACTORY
}

OrganActor :: struct {
    energy: int,
    organ_kind: OrganKind,
    using base: Actor
}

TurretActor :: struct {
    target_bitset: bit_set[ActorClass],
    target_wires: bool,
    // Damage to target, or energy (negative means healing / energy gen)
    damage: int,

    target_radius: f32,
    using base: Actor
}

// Returns CENTER of the actor. If the actor size is odd, this is clearly
// defined to be a tile center, otherwise, it's offset to positive x / y
// such that the center lies on a tile center
actor_get_draw_pos :: proc(actor: Actor) -> [2]f32 {
    extra := [2]f32{0.0, 0.0}
    if actor.sprite_size.x % 2 == 0 {
        extra.x = -0.5
    }
    if actor.sprite_size.y % 2 == 0 {
        extra.y = -0.5
    }
    return linalg.to_f32(actor.pos) + [2]f32{0.5, 0.5} + actor.doffset + extra
}

destroy_actor :: proc(actor: ^Actor) {
    destroy_subscale_map(actor)
    switch v in actor.kind {
        case ^NPCActor:
            free(v)
        case ^OrganActor:
            free(v)
        case ^TurretActor:
            free(v)
        case ^HeroActor:
        case ^ProbeActor:

    }
}

create_hero :: proc(game: ^Game, pos: [2]int) {
    out := &game.hero
    out.kind = &game.hero;
    out.in_game = game
    out.class = {.HERO, .FRIENDLY}
    out.actions_per_turn = 1
    out.pos = pos
    out.dir = .NORTH
    out.alive = true
    out.sprite = get_texture(&game.assets, "res/agents/player.png")
    out.sprite_rect = rl.Rectangle{0, 0, f32(out.sprite.width), f32(out.sprite.height)}
    out.sprite_size = [2]int{1, 1}



    out.scale_kind = FullscaleActor{}
    fs := &out.scale_kind.(FullscaleActor)

    create_subscale_map(out, "res/agents/player_interior.png", DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{3, 3},
        num_rooms = 14,
    })

    fs.subscale.tex = render_subscale_tilemap(fs.subscale.tmap)

    return
}

create_probe :: proc(game: ^Game, pos: [2]int) {
    out := &game.probe
    out.kind = &game.probe
    out.in_game = game
    out.class = {.HERO, .FRIENDLY}
    out.pos = pos
    out.dir = .NORTH
    out.alive = true
    out.sprite = get_texture(&game.assets, "res/agents/probe.png")
    out.sprite_rect = rl.Rectangle{0, 0, f32(out.sprite.width), f32(out.sprite.height)}
    out.sprite_size = [2]int{1, 1}
    out.actions_per_turn = SUBSCALE_ACTIONS_PER_TURN

    out.scale_kind = SubscaleActor{
        subscale_of = &game.hero
    }
    fs := &out.scale_kind.(SubscaleActor)

    return
}

take_turn_hero :: proc(actor: ^HeroActor) -> Action {
    if rl.IsKeyPressed(.P) {
        return shoot_probe_action(actor, actor.dir)
    } else if rl.IsKeyPressed(.SPACE) {
        actor.in_game.playing_subscale = true
        return no_action()
    }
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


take_turn_probe :: proc(actor: ^ProbeActor) -> Action {
    if rl.IsKeyPressed(.SPACE) {
        actor.in_game.playing_subscale = false
        return no_action()
    }

    // HJKL motion
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


    return move_action(actor, dir, 1)
}

ai_can_target :: proc(ai: ^NPCActor, target: ^Actor) -> bool {
    sscale_ai, is_ai_subscale := ai.scale_kind.(SubscaleActor)
    sscale_tgt, is_tgt_subscale := target.scale_kind.(SubscaleActor)

    compatible := false
    for tag in ai.target_acquire_class {
        if tag in target.class {
            compatible = true
            break
        }
    }

    if !compatible do return false

    if is_ai_subscale && is_tgt_subscale && sscale_ai.subscale_of == sscale_tgt.subscale_of {
        return true
    }
    if !is_ai_subscale && !is_tgt_subscale {
        if ai.require_los {
            spos := linalg.to_f32(ai.pos) + [2]f32{0.5, 0.5}
            epos := linalg.to_f32(target.pos) + [2]f32{0.5, 0.5}
            visible := !tilemap_raycast(ai.in_game.worldmap, spos, epos)
            return visible
        } else {
            return true
        }
    }

    return false
}

ai_find_target :: proc(actor: ^NPCActor) -> ^Actor {
    if ai_can_target(actor, &actor.in_game.hero) do return &actor.in_game.hero
    if ai_can_target(actor, &actor.in_game.probe) do return &actor.in_game.probe

    for other_actor in actor.in_game.npcs {
        if other_actor == actor do continue
        if ai_can_target(actor, other_actor) do return other_actor
    }

    return nil
}

ai_deacquire_target :: proc(actor: ^NPCActor) {
    actor.target = nil
}

ai_acquire_target :: proc(actor: ^NPCActor, target: ^Actor) {
    actor.target = target

    switch &ai in actor.target_ai {
    case ChaserAI:
        ai.turns_without_vision = 0
    }
}

ai_random_move_take_turn :: proc(actor: ^NPCActor) -> Action {
    return no_action()
}

ai_chaser_take_turn :: proc(actor: ^NPCActor) -> Action {
    chaser := actor.target_ai.(ChaserAI)

    obj: [2]int
    wmap: ^Tilemap
    if actor.require_los {
        wmap = &actor.in_game.worldmap

        spos := linalg.to_f32(actor.pos) + [2]f32{0.5, 0.5}
        epos := linalg.to_f32(actor.target.pos) + [2]f32{0.5, 0.5}
        in_sight := !tilemap_raycast(wmap^, spos, epos)
        if in_sight {
            chaser.last_seen = actor.target.pos
        } else {
            chaser.turns_without_vision += 1
            if chaser.turns_without_vision >= chaser.max_turns_without_vision {
                ai_deacquire_target(actor)
            }
        }

        // TODO: Otherwise excessively dumb
        // obj = actor.target.pos if in_sight else chaser.last_seen
        obj = actor.target.pos

    } else {
        sscale, is_subscale := actor.scale_kind.(SubscaleActor)
        if is_subscale {
            fscale := &sscale.subscale_of.scale_kind.(FullscaleActor)
            wmap = &fscale.subscale.tmap
        } else {
            wmap = &actor.in_game.worldmap
        }
        obj = actor.target.pos
    }

    path := astar_wall(actor.pos, obj, wmap.walls[:], wmap.width, max(int), 0, wmap.outside[:])
    if len(path) > 1 {
        next := path[1]

        nextf := linalg.to_f32(next) + [2]f32{0.5, 0.5}
        tgtf := linalg.to_f32(actor.target.pos) + [2]f32{0.5, 0.5}

        delta := next - actor.pos
        dir := delta_to_dir(delta)
        if actor.dir != dir {
            return turn_action(actor, dir)
        }

        if linalg.distance(nextf, tgtf) <= chaser.min_dist {
            return no_action()
        }

        return move_action(actor, dir, 1)

    }

    return no_action()
}

take_turn_monster :: proc(actor: ^NPCActor) -> Action {
    if actor.target == nil {
        // Target acquire
        ntarget := ai_find_target(actor)
        if ntarget != nil {
            ai_acquire_target(actor, ntarget)
        }
    }

    if actor.target == nil {
        // Loiter
        switch v in actor.loiter_ai {
        case RandomMoveAI:
            return ai_random_move_take_turn(actor)
        }
    } else {
        // Target
        switch v in actor.target_ai {
        case ChaserAI:
            return ai_chaser_take_turn(actor)
        }
    }

    return no_action()
}

take_turn_organ :: proc(actor: ^OrganActor) -> Action {
    if actor.organ_kind == .CORTEX {
        if actor.actions_taken == 0 {
            actor.energy = 16
        }

        for &wire in actor.scale_kind.(SubscaleActor).subscale_of.scale_kind.(FullscaleActor).subscale.wire {
            if wire.start_actor == actor {
                subscale_wire_update(&wire)
            }
        }

        if actor.scale_kind.(SubscaleActor).subscale_of == actor.in_game.focus_subscale && actor.in_game.playing_subscale {
            //return dummy_animate_action(actor, 0.0)
            return no_action()
        }
    }
    return no_action()
}

take_turn_turret :: proc(actor: ^TurretActor) -> Action {
    sof := actor.scale_kind.(SubscaleActor).subscale_of
    smap := sof.scale_kind.(FullscaleActor).subscale

    if actor.target_wires && actor.damage > 0 {

        // Search a random wire in range
        possible := make([dynamic]ChargeSuckAction, context.temp_allocator)
        defer delete(possible)

        for &wire in smap.wire {
            for charge_idx := 0; charge_idx < len(wire.charges); charge_idx+=1 {
                energy := wire.charges[charge_idx]
                if energy < 0 || energy >= len(wire.steps) do continue
                pos := wire.steps[energy]

                delta := linalg.to_f32(pos - actor.pos)
                if linalg.length(delta) <= actor.target_radius {
                    target := ChargeSuckAction{
                        wire = &wire,
                        pos = pos,
                        charge_index = charge_idx
                    }
                    append(&possible, target)
                }
            }
        }

        if len(possible) == 0 {
            return no_action()
        }

        return Action{
            by_actor = actor,
            variant = rand.choice(possible[:]),
        }



    } else if actor.target_wires && actor.damage < 0 {

    } else {

    }

    return no_action()
}

create_subscale_map :: proc(for_actor: ^Actor, fname: string, sets: DungeonSettings) {

    fullscale, is_fullscale := &for_actor.scale_kind.(FullscaleActor)
    assert(is_fullscale)

    run_cable :: proc(inmap: ^Tilemap, frontier: []bool, from, to: [2]int,
        connect_start, connect_end: [2]int, from_act, to_act: ^OrganActor, cable_map: []bool) -> (out: SubscaleWire) {

        path := astar_wall(from, to, inmap.walls[:], inmap.width, max(int), 0, frontier)
        if len(path) == 0 {
            delete(path)
            path = astar_wall(from, to, inmap.walls[:], inmap.width, 100, 0, frontier)
            for step in path {
                inmap.walls[step.y * inmap.width + step.x] = false
            }
        }

        out.steps = path
        out.start_actor = from_act
        out.end_actor = to_act
        out.charge_tex = get_texture(&from_act.in_game.assets, "res/charge.png")

        cable_map[connect_start.y * inmap.width + connect_start.x] = true
        cable_map[connect_end.y * inmap.width + connect_end.x] = true
        for p in path {
            cable_map[p.y * inmap.width + p.x] = true
        }

        return
    }

    mesh_cables :: proc(inmap: ^Tilemap, cables: []bool) {
        for y := 1; y < inmap.height - 1; y += 1 {
            for x := 1; x < inmap.width - 1; x += 1 {
                if cables[y * inmap.width + x] {
                    n := cables[(y - 1) * inmap.width + x]
                    e := cables[y * inmap.width + x + 1]
                    s := cables[(y + 1) * inmap.width + x]
                    w := cables[y * inmap.width + x - 1]

                    num := 0
                    num += 1 if n else 0
                    num += 1 if e else 0
                    num += 1 if s else 0
                    num += 1 if w else 0

                    assert(num > 0)
                    if num == 1 {
                        // Nothing, this one is hidden below a target
                    } else if num == 2 {
                        // Two-way junction, may or may not be curved
                        if e && w {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 0}
                            inmap.tile_rot[y * inmap.width + x] = 0.0
                        } else if n && s {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 0}
                            inmap.tile_rot[y * inmap.width + x] = 90.0
                        } else if n && w {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 1}
                            inmap.tile_rot[y * inmap.width + x] = 0.0
                        } else if n && e {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 1}
                            inmap.tile_rot[y * inmap.width + x] = 90.0
                        } else if s && w {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 1}
                            inmap.tile_rot[y * inmap.width + x] = 270.0
                        } else if s && e {
                            inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 1}
                            inmap.tile_rot[y * inmap.width + x] = 180.0
                        }

                    } else if num == 3 {
                        // Three-way junction
                        inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 2}
                        if !s {
                            inmap.tile_rot[y * inmap.width + x] = 0
                        } else if !w {
                            inmap.tile_rot[y * inmap.width + x] = 90.0
                        } else if !n {
                            inmap.tile_rot[y * inmap.width + x] = 180.0
                        } else {
                            inmap.tile_rot[y * inmap.width + x] = 270.0
                        }
                    } else if num == 4 {
                        // Four-way junction
                        inmap.tile_to_tex[y * inmap.width + x] = [2]int{2, 3}
                    }

                }
            }
        }
    }

    clear_rectangle :: proc(inmap: ^Tilemap, center, rad: [2]int) {
        for dx:=-rad.x;dx <= rad.x;dx+=1 {
            for dy:=-rad.y;dy<=rad.y;dy+=1 {
                p := center + [2]int{dx, dy}
                inmap.walls[p.y * inmap.width + p.x] = false
            }
        }
    }

    set_footprint :: proc(inmap: ^Tilemap, center, s, e: [2]int, val := true) {
        for dx:=s.x; dx <= e.x; dx+=1 {
            for dy:=s.y; dy <= e.y; dy+=1 {
                p := center + [2]int{dx, dy}
                inmap.walls[p.y * inmap.width + p.x] = val
            }
        }
    }

    actor_wall, width, tags := wall_from_image(fname)
    defer delete(tags)

    dungeon, dungeon_rooms, frontier := dungeon_gen(actor_wall[:], width, sets)
    fullscale.subscale.tmap = create_tilemap(dungeon, frontier, width, dungeon_rooms)
    tex := get_texture(&for_actor.in_game.assets, "res/smalltiles.png")
    fullscale.subscale.tmap.tileset = tex
    fullscale.subscale.tmap.tileset_size = [2]int{int(tex.width) / 3, int(tex.height) / 4}
    worldmap := &fullscale.subscale.tmap
    height := worldmap.height

    // Run wires and build rooms for organs
    game := for_actor.in_game
    cortex : ^OrganActor
    engines : [dynamic]^OrganActor
    radars : [dynamic]^OrganActor
    factories : [dynamic]^OrganActor
    CORTEX_ID :: [3]u8{0, 0, 255}
    MOTOR_ID :: [3]u8{255, 0, 0}
    RADAR_ID :: [3]u8{0, 255, 0}
    FACTORY_ID :: [3]u8{255, 255, 0}

    cable_map := make_dynamic_array_len([dynamic]bool, worldmap.width * worldmap.height)
    defer delete(cable_map)

    for &tag in tags {
        if tag.tag == CORTEX_ID {
            cortex = create_cortex(game, tag.pos, for_actor, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,1})
        } else if tag.tag == MOTOR_ID {
            engine := create_engine(game, tag.pos, for_actor, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,0})
            append(&engines, engine)
        } else if tag.tag == RADAR_ID {
            radar := create_radar(game, tag.pos, for_actor, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,0})
            append(&radars, radar)
        } else if tag.tag == FACTORY_ID {
            factory := create_factory(game, tag.pos, for_actor, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,0})
            append(&factories, factory)

        }
    }

    // Run cables from cortex to everything else
    cable_start, cable_start_in := cortex_cable_location(cortex)
    wires : [dynamic]SubscaleWire
    for engine in engines {
        cable_end, cable_end_in := engine_cable_location(engine)
        nwire := run_cable(worldmap, frontier[:], cable_start, cable_end,
            cable_start_in, cable_end_in, cortex, engine, cable_map[:])
        append(&wires, nwire)
    }
    for radar in radars {
        cable_end, cable_end_in := engine_cable_location(radar)
        nwire := run_cable(worldmap, frontier[:], cable_start, cable_end,
            cable_start_in, cable_end_in, cortex, radar, cable_map[:])
        append(&wires, nwire)
    }
    for factory in factories {
        cable_end, cable_end_in := factory_cable_location(factory)
        nwire := run_cable(worldmap, frontier[:], cable_start, cable_end,
            cable_start_in, cable_end_in, cortex, factory, cable_map[:])
        append(&wires, nwire)
    }


    worldmap.tile_rot = make_dynamic_array_len([dynamic]f32, width*height)
    worldmap.tile_to_tex = make_dynamic_array_len([dynamic][2]int, width*height)
    worldmap.tile_tint = make_dynamic_array_len([dynamic]rl.Color, width*height)

    orient := [4]f32{0.0, 90.0, 180.0, 270.0}
    // For now, simple wall-floor mapping
    for yi := 0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            i := yi*width+xi
            tex := [2]int{0, int(rl.GetRandomValue(0, 3))}
            if worldmap.walls[i] {
                tex = [2]int{1, int(rl.GetRandomValue(0, 3))}
            }
            worldmap.tile_to_tex[i] = tex
            worldmap.tile_rot[i] = orient[0]
            worldmap.tile_tint[i] = rl.WHITE
        }
    }

    mesh_cables(worldmap, cable_map[:])

    fullscale.subscale.cortex = cortex
    fullscale.subscale.engines = engines
    fullscale.subscale.radars = radars
    fullscale.subscale.factories = factories
    fullscale.subscale.wire = wires
    delete(actor_wall)

}

destroy_subscale_map :: proc(for_actor: ^Actor) {
    fullscale, is_fullscale := &for_actor.scale_kind.(FullscaleActor)
    if !is_fullscale do return

    for wire in fullscale.subscale.wire {
        delete(wire.steps)
    }

    delete(fullscale.subscale.factories)
    delete(fullscale.subscale.radars)
    delete(fullscale.subscale.engines)
    delete(fullscale.subscale.wire)

    destroy_tilemap(&fullscale.subscale.tmap)
    rl.UnloadRenderTexture(fullscale.subscale.tex)
}

draw_actor :: proc(actor: ^Actor) {
    pos := actor_get_draw_pos(actor^)

    target_rect := rl.Rectangle{pos.x, pos.y, f32(actor.sprite_size.x), f32(actor.sprite_size.y)}

    rot : f32 = 0.0
    if !actor.ignore_dir_graphics {
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
    }
    rl.DrawTexturePro(actor.sprite,
        actor.sprite_rect, target_rect,
        [2]f32{0.5 * f32(actor.sprite_size.x), 0.5 * f32(actor.sprite_size.y)},
        rot + actor.drotate,
        rl.WHITE
        )

}

create_turret :: proc(game: ^Game, pos: [2]int, inside: ^Actor) -> ^TurretActor {
    actor := game_create_npc(game, TurretActor)
    actor.class = {.TURRET}
    actor.actions_per_turn = 4
    actor.target_bitset = {.HOSTILE}
    actor.damage = 1

    actor.pos = pos
    actor.dir = .NORTH
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/turret.png")
    actor.sprite_rect = rl.Rectangle{
        0, 0,
        f32(actor.sprite.height), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{2, 2}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return actor
}

create_collector :: proc(game: ^Game, pos: [2]int, inside: ^Actor) -> ^TurretActor {
    actor := game_create_npc(game, TurretActor)
    actor.class = {.TURRET}
    actor.actions_per_turn = 2
    actor.target_wires = true
    actor.target_radius = 4.0
    actor.damage = 1

    actor.pos = pos
    actor.dir = .NORTH
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/energy_collector.png")
    actor.sprite_rect = rl.Rectangle{
        0, 0,
        f32(actor.sprite.height), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{2, 2}

    actor.scale_kind = SubscaleActor{subscale_of = inside}
    return  actor
}

create_cortex :: proc(game: ^Game, pos: [2]int, inside: ^Actor, orient: c.int) -> ^OrganActor {
    actor := game_create_npc(game, OrganActor)
    actor.class = {.ENVIRONMENT}
    actor.actions_per_turn = SUBSCALE_ACTIONS_PER_TURN

    actor.pos = pos
    actor.ignore_dir_graphics = true
    actor.dir = Direction(orient)
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/cortex.png")
    actor.sprite_rect = rl.Rectangle{
        f32(orient * actor.sprite.height), 0,
        f32(actor.sprite.height), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{3, 3}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return actor
}

cortex_cable_location :: proc(cortex: ^Actor) -> (outer: [2]int, inner: [2]int) {
    switch cortex.dir {
    case .NORTH:
        return cortex.pos + [2]int{0, -2}, cortex.pos + [2]int{0, -1}
    case .EAST:
        return cortex.pos + [2]int{2, 0}, cortex.pos + [2]int{1, 0}
    case .SOUTH:
        return cortex.pos + [2]int{0, 2}, cortex.pos + [2]int{0, 1}
    case .WEST:
        return cortex.pos + [2]int{-2, 0}, cortex.pos + [2]int{-1, 0}
    }
    assert(false, "invalid cortex direction")
    return cortex.pos, cortex.pos
}

engine_cable_location :: proc(engine: ^Actor) -> (outer: [2]int, inner: [2]int) {

    switch engine.dir {
    case .NORTH:
        return engine.pos + [2]int{0, -2}, engine.pos + [2]int{0, -1}
    case .EAST:
        return engine.pos + [2]int{2, 0}, engine.pos + [2]int{1, 0}
    case .SOUTH:
        return engine.pos + [2]int{0, 1}, engine.pos + [2]int{0, 0}
    case .WEST:
        return engine.pos + [2]int{-2, 0}, engine.pos + [2]int{-1, 0}
    }
    assert(false, "invalid engine direction")
    return engine.pos, engine.pos
}

radar_cable_location :: proc(radar: ^Actor) -> (outer: [2]int, inner: [2]int) {

    switch radar.dir {
    case .NORTH:
        return radar.pos + [2]int{0, -2}, radar.pos + [2]int{0, -1}
    case .EAST:
        return radar.pos + [2]int{2, 0}, radar.pos + [2]int{1, 0}
    case .SOUTH:
        return radar.pos + [2]int{0, 1}, radar.pos + [2]int{0, 0}
    case .WEST:
        return radar.pos + [2]int{-2, 0}, radar.pos + [2]int{-1, 0}
    }
    assert(false, "invalid radar direction")
    return radar.pos, radar.pos
}

factory_cable_location :: proc(factory: ^Actor) -> (outer: [2]int, inner: [2]int) {

    switch factory.dir {
    case .NORTH:
        return factory.pos + [2]int{0, -2}, factory.pos + [2]int{0, -1}
    case .EAST:
        return factory.pos + [2]int{2, 0}, factory.pos + [2]int{1, 0}
    case .SOUTH:
        return factory.pos + [2]int{0, 1}, factory.pos + [2]int{0, 0}
    case .WEST:
        return factory.pos + [2]int{-2, 0}, factory.pos + [2]int{-1, 0}
    }
    assert(false, "invalid factory direction")
    return factory.pos, factory.pos
}

create_engine :: proc(game: ^Game, pos: [2]int, inside: ^Actor, orient: c.int) -> ^OrganActor {
    actor := game_create_npc(game, OrganActor)
    actor.class = {.ENVIRONMENT}
    actor.organ_kind = .ENGINE


    actor.pos = pos
    actor.ignore_dir_graphics = true
    actor.dir = Direction(orient)
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/engine.png")
    w := actor.sprite.width / 4
    actor.sprite_rect = rl.Rectangle{
        f32(orient * w), 0,
        f32(w), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{3, 2}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return actor
}

create_radar :: proc(game: ^Game, pos: [2]int, inside: ^Actor, orient: c.int) -> ^OrganActor {
    actor := game_create_npc(game, OrganActor)
    actor.class = {.ENVIRONMENT}
    actor.organ_kind = .RADAR


    actor.pos = pos
    actor.ignore_dir_graphics = true
    actor.dir = Direction(orient)
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/radar.png")
    w := actor.sprite.width / 4
    actor.sprite_rect = rl.Rectangle{
        f32(orient * w), 0,
        f32(w), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{3, 2}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return actor
}

create_sentinel :: proc(game: ^Game, pos: [2]int) -> ^Actor {
    actor := game_create_npc(game, NPCActor)
    actor.actions_per_turn = 1
    actor.class = {.HOSTILE}
    actor.swappable = true
    actor.impedes_movement = true
    actor.pos = pos
    actor.dir = .NORTH
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/sentinel.png")
    actor.sprite_rect = rl.Rectangle{0, 0, f32(actor.sprite.width), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{1, 1}

    actor.require_los = true
    actor.target_ai = ChaserAI{max_turns_without_vision = 2, min_dist = 2.0}
    actor.loiter_ai = RandomMoveAI{}
    actor.target_acquire_class = {.HERO}

    actor.scale_kind = FullscaleActor{}
    fs := &actor.scale_kind.(FullscaleActor)

    create_subscale_map(actor, "res/agents/sentinel_interior.png", DungeonSettings{
        max_room_size = [2]int{3, 3},
        min_room_size = [2]int{2, 2},
        num_rooms = 6,
    })

    fs.subscale.tex = render_subscale_tilemap(fs.subscale.tmap)

    return actor
}

create_factory :: proc(game: ^Game, pos: [2]int, inside: ^Actor, orient: c.int) -> ^OrganActor {
    actor := game_create_npc(game, OrganActor)
    actor.class = {.ENVIRONMENT}
    actor.organ_kind = .FACTORY


    actor.pos = pos
    actor.ignore_dir_graphics = true
    actor.dir = Direction(orient)
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/factory.png")
    w := actor.sprite.width / 4
    actor.sprite_rect = rl.Rectangle{
        f32(orient * w), 0,
        f32(w), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{3, 2}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return actor
}
