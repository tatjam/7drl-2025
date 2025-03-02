package src

import rl "vendor:raylib"
import "core:math/linalg"
import "core:math/rand"

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
    tex: rl.RenderTexture,
}

SubscaleActor :: struct {
    subscale_of: int
}

FullscaleActor :: struct {
    subscale: SubscaleMap,
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

    out.scale_kind = FullscaleActor{}
    fs := &out.scale_kind.(FullscaleActor)

    create_subscale_map(&out, "res/agents/player_interior.png", DungeonSettings{
        max_room_size = [2]int{6, 6},
        min_room_size = [2]int{3, 3},
        num_rooms = 16,
    })

    fs.subscale.tex = render_subscale_tilemap(fs.subscale.tmap)

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

create_subscale_map :: proc(for_actor: ^Actor, fname: string, sets: DungeonSettings) {
    fullscale, is_fullscale := &for_actor.scale_kind.(FullscaleActor)
    assert(is_fullscale)


    actor_wall, width, tags := wall_from_image(fname)
    dungeon, dungeon_rooms, frontier := dungeon_gen(actor_wall[:], width, sets)
    fullscale.subscale.tmap = create_tilemap(dungeon, frontier[:], width, dungeon_rooms)
    tex := get_texture(&for_actor.in_game.assets, "res/smalltiles.png")
    fullscale.subscale.tmap.tileset = tex
    fullscale.subscale.tmap.tileset_size = [2]int{int(tex.width) / 2, int(tex.height) / 1}
    worldmap := &fullscale.subscale.tmap
    height := worldmap.height

    resize(&worldmap.tile_to_tex, width*height)
    resize(&worldmap.tile_rot, width*height)
    resize(&worldmap.tile_tint, width*height)

    orient := [4]f32{0.0, 90.0, 180.0, 270.0}
    // For now, simple wall-floor mapping
    for yi := 0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            i := yi*width+xi
            tex := [2]int{0, 0}
            if dungeon[i] {
                tex = [2]int{1, 0}
            }
            worldmap.tile_to_tex[i] = tex
            worldmap.tile_rot[i] = rand.choice(orient[:])
            worldmap.tile_tint[i] = rl.WHITE
        }
    }


    delete(actor_wall)
    delete(frontier)

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

