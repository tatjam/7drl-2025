package src

import rl "vendor:raylib"
import "core:math/linalg"
import "core:math/rand"
import "core:c"

Direction :: enum {
    NORTH,
    EAST,
    SOUTH,
    WEST
}

SubscaleWire :: struct {
    start_actor: int,
    end_actor: int,
    steps: [dynamic][2]int,
    // Progress along length of wire
    charges: [dynamic]int,
}

// If we are not a subscale actor, we must have
// such a map
SubscaleMap :: struct {
    tmap: Tilemap,
    tex: rl.RenderTexture,
    wire: [dynamic]SubscaleWire,
    cortex: int,
    engines: [dynamic]int,
    radars: [dynamic]int,
}

SubscaleActor :: struct {
    subscale_of: int,
}

FullscaleActor :: struct {
    subscale: SubscaleMap,
}

Actor :: struct {
    id: int,
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
}

create_hero :: proc(game: ^GameState, pos: [2]int) -> (out: HeroActor) {
    out.id = -1
    out.in_game = game
    out.pos = pos
    out.dir = .NORTH
    out.alive = true
    out.sprite = get_texture(&game.assets, "res/agents/player.png")
    out.sprite_rect = rl.Rectangle{0, 0, f32(out.sprite.width), f32(out.sprite.height)}
    out.sprite_size = [2]int{1, 1}

    out.scale_kind = FullscaleActor{}
    fs := &out.scale_kind.(FullscaleActor)

    frontier := create_subscale_map(&out, "res/agents/player_interior.png", DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{3, 3},
        num_rooms = 16,
    })

    fs.subscale.tex = render_subscale_tilemap(fs.subscale.tmap, frontier[:])
    delete(frontier)

    return
}

create_probe :: proc(game: ^GameState, pos: [2]int) -> (out: ProbeActor) {
    out.id = -2
    out.in_game = game
    out.pos = pos
    out.dir = .NORTH
    out.alive = true
    out.sprite = get_texture(&game.assets, "res/agents/probe.png")
    out.sprite_rect = rl.Rectangle{0, 0, f32(out.sprite.width), f32(out.sprite.height)}
    out.sprite_size = [2]int{1, 1}

    out.scale_kind = SubscaleActor{
        subscale_of = -1
    }
    fs := &out.scale_kind.(SubscaleActor)

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



create_subscale_map :: proc(for_actor: ^Actor, fname: string, sets: DungeonSettings) ->
    [dynamic]bool {

    fullscale, is_fullscale := &for_actor.scale_kind.(FullscaleActor)
    assert(is_fullscale)

    run_cable :: proc(inmap: ^Tilemap, frontier: []bool, from, to: [2]int,
        connect_start, connect_end: [2]int, from_act, to_act: int, cable_map: []bool) -> (out: SubscaleWire) {

        path := astar_wall(from, to, inmap.walls[:], inmap.width, max(int), 0, frontier)
        if len(path) == 0 {

            path = astar_wall(from, to, inmap.walls[:], inmap.width, 100, 0, frontier)
            for step in path {
                inmap.walls[step.y * inmap.width + step.x] = false
            }
        }

        out.steps = path
        out.start_actor = from_act
        out.end_actor = to_act

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
    dungeon, dungeon_rooms, frontier := dungeon_gen(actor_wall[:], width, sets)
    fullscale.subscale.tmap = create_tilemap(dungeon, frontier[:], width, dungeon_rooms)
    tex := get_texture(&for_actor.in_game.assets, "res/smalltiles.png")
    fullscale.subscale.tmap.tileset = tex
    fullscale.subscale.tmap.tileset_size = [2]int{int(tex.width) / 3, int(tex.height) / 4}
    worldmap := &fullscale.subscale.tmap
    height := worldmap.height

    // Run wires and build rooms for organs
    game := for_actor.in_game
    cortex : int
    engines : [dynamic]int
    radars : [dynamic]int
    CORTEX_ID :: [3]u8{0, 0, 255}
    MOTOR_ID :: [3]u8{255, 0, 0}
    RADAR_ID :: [3]u8{0, 255, 0}

    cable_map := make_dynamic_array_len([dynamic]bool, worldmap.width * worldmap.height)
    defer delete(cable_map)

    for &tag in tags {
        if tag.tag == CORTEX_ID {
            cortex = create_cortex(game, tag.pos, for_actor.id, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,1})
        } else if tag.tag == MOTOR_ID {
            engine := create_engine(game, tag.pos, for_actor.id, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,0})
            append(&engines, engine)
        } else if tag.tag == RADAR_ID {
            radar := create_radar(game, tag.pos, for_actor.id, rl.GetRandomValue(0, 3))
            clear_rectangle(&fullscale.subscale.tmap, tag.pos, [2]int{2,2})
            set_footprint(&fullscale.subscale.tmap, tag.pos, [2]int{-1,-1}, [2]int{1,0})
            append(&radars, radar)
        }
    }

    // Run cables from cortex to everything else
    cable_start, cable_start_in := cortex_cable_location(&game.npcs[cortex])
    wires : [dynamic]SubscaleWire
    for engine in engines {
        cable_end, cable_end_in := engine_cable_location(&game.npcs[engine])
        nwire := run_cable(worldmap, frontier[:], cable_start, cable_end,
            cable_start_in, cable_end_in, cortex, engine, cable_map[:])
        append(&wires, nwire)
    }
    for radar in radars {
        cable_end, cable_end_in := engine_cable_location(&game.npcs[radar])
        nwire := run_cable(worldmap, frontier[:], cable_start, cable_end,
        cable_start_in, cable_end_in, cortex, radar, cable_map[:])
        append(&wires, nwire)
    }


    resize(&worldmap.tile_to_tex, width*height)
    resize(&worldmap.tile_rot, width*height)
    resize(&worldmap.tile_tint, width*height)

    orient := [4]f32{0.0, 90.0, 180.0, 270.0}
    // For now, simple wall-floor mapping
    for yi := 0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            i := yi*width+xi
            tex := [2]int{0, int(rl.GetRandomValue(0, 3))}
            if dungeon[i] {
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
    fullscale.subscale.radars = engines
    fullscale.subscale.wire = wires
    delete(actor_wall)
    return frontier

}

destroy_subscale_map :: proc(for_actor: ^Actor) {
    fullscale, is_fullscale := &for_actor.scale_kind.(FullscaleActor)
    if !is_fullscale do return

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

create_cortex :: proc(game: ^GameState, pos: [2]int, inside: int, orient: c.int) -> (id: int) {
    id = game_create_npc(game)
    actor := &game.npcs[id]

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

    return
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

create_engine :: proc(game: ^GameState, pos: [2]int, inside: int, orient: c.int) -> (id: int) {
    id = game_create_npc(game)
    actor := &game.npcs[id]


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

    return
}

create_radar :: proc(game: ^GameState, pos: [2]int, inside: int, orient: c.int) -> (id: int) {
    id = game_create_npc(game)
    actor := &game.npcs[id]


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

    return
}
