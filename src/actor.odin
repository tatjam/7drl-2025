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
}

SubscaleActor :: struct {
    subscale_of: int
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


    actor_wall, width, tags := wall_from_image(fname)
    dungeon, dungeon_rooms, frontier := dungeon_gen(actor_wall[:], width, sets)
    fullscale.subscale.tmap = create_tilemap(dungeon, frontier[:], width, dungeon_rooms)
    tex := get_texture(&for_actor.in_game.assets, "res/smalltiles.png")
    fullscale.subscale.tmap.tileset = tex
    fullscale.subscale.tmap.tileset_size = [2]int{int(tex.width) / 2, int(tex.height) / 4}
    worldmap := &fullscale.subscale.tmap
    height := worldmap.height

    // Run wires and build rooms for organs
    game := for_actor.in_game
    cortex : int
    CORTEX_ID :: [3]u8{0, 0, 255}
    for tag in tags {
        if tag.tag == CORTEX_ID {
            cortex = create_cortex(game, tag.pos, for_actor.id, 0)
        }
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

create_cortex :: proc(game: ^GameState, pos: [2]int, inside: int, orient: c.int) -> (id: int) {
    id = game_create_npc(game)
    actor := &game.npcs[id]

    actor.pos = pos
    actor.dir = .NORTH
    actor.alive = true
    actor.sprite = get_texture(&game.assets, "res/agents/cortex.png")
    actor.sprite_rect = rl.Rectangle{
        f32(orient * actor.sprite.height), 0,
        f32(actor.sprite.height), f32(actor.sprite.height)}
    actor.sprite_size = [2]int{3, 3}

    actor.scale_kind = SubscaleActor{subscale_of = inside}

    return
}
