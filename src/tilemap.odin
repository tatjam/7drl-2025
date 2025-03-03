package src

import rl "vendor:raylib"
import "core:c"
import "core:math/linalg"
import "core:math/rand"
import "core:math"

// A tilemap is where the gameplay takes places. It's a
// rectangular grid of tiles which may contain entities
// Tiles are drawn using shadow projection from all the edges
// in the tile map (in the big scale map) and with sprites
// in the small case map
Tile :: struct {
    scale_color: rl.Color,
    // Texture index in the tilemap
    tex: [2]int,
}

// Float coordinates are such that the tiles
// top-left corner is at the rounded int coordinate
MapEdge :: struct {
    start: [2]f32,
    end: [2]f32,
    shadow_vertices: [4][2]f32,
    shadow_present: bool,
}

Tilemap :: struct {
    walls: [dynamic]bool,
    width: int,
    height: int,
    rooms: [dynamic]DungeonRoom,

    // Only if this is a world tilemap
    meshing: [dynamic]MapEdge,
    // Only if this is a subscale tilemap
    tileset: rl.Texture2D,
    tileset_size: [2]int,
    tile_to_tex: [dynamic][2]int,
    tile_rot: [dynamic]f32,
    tile_tint: [dynamic]rl.Color,
}

// We take ownership of walls
create_tilemap :: proc(walls: [dynamic]bool, exclude: []bool, width: int,
    rooms: [dynamic]DungeonRoom) -> (out: Tilemap) {

    out.walls = walls
    out.width = width
    out.height = len(walls) / width
    out.rooms = rooms
    mesh_world_tilemap(&out, exclude)
    return out
}

destroy_tilemap :: proc(tm: ^Tilemap) {
    delete(tm.meshing)
    delete(tm.walls)
    delete(tm.rooms)
    delete(tm.tile_tint)
    delete(tm.tile_to_tex)
    delete(tm.tile_rot)
}

mesh_world_tilemap :: proc(tm: ^Tilemap, exclude: []bool = nil) {
    if exclude != nil {
        assert(len(exclude) == len(tm.walls))
    }

    // x represents any, 0 represents no wall, 1 represents wall
    // A left edge is generated at given stencil
    // [X][X][X]
    // [1][0][X]
    // [X][X][X]
    // The same logic applies to all other edges, but we skip any excluded edges
    // The edges are made in clockwise direction, for early culling
    for yi:=0; yi < tm.height; yi+=1 {
        for xi:=0; xi < tm.width; xi+=1 {
            if !(xi > 0 && yi > 0 && xi < tm.width - 1 && yi < tm.height - 1) {
                continue
            }
            if tm.walls[yi * tm.width + xi] do continue
            if exclude != nil {
                if exclude[yi*tm.width + xi] do continue
            }

            if tm.walls[(yi-1)*tm.width + xi] {
                edge := MapEdge{
                    start=[2]f32{f32(xi + 1), f32(yi)},
                    end=[2]f32{f32(xi), f32(yi)}
                }
                append(&tm.meshing, edge)
            }
            if tm.walls[yi * tm.width + (xi + 1)] {
                edge := MapEdge{
                    start=[2]f32{f32(xi + 1), f32(yi + 1)},
                    end=[2]f32{f32(xi + 1), f32(yi)}
                }
                append(&tm.meshing, edge)
            }
            if tm.walls[(yi+1)*tm.width + xi] {
                edge := MapEdge{
                    start=[2]f32{f32(xi), f32(yi+1)},
                    end=[2]f32{f32(xi + 1), f32(yi+1)}
                }
                append(&tm.meshing, edge)
            }
            if tm.walls[yi*tm.width + (xi-1)] {
                edge := MapEdge{
                    start=[2]f32{f32(xi), f32(yi)},
                    end=[2]f32{f32(xi), f32(yi + 1)}
                }
                append(&tm.meshing, edge)
            }
        }
    }
}

// Will understand raylib camera to early-cull edges
world_tilemap_cast_shadows :: proc(tm: Tilemap, caster: [2]f32,
    screen: rl.Rectangle, cam: rl.Camera2D) {
    for &edge in tm.meshing {
        // The normal vector to the edge is defined as the 90º perpendicular
        // it points OUT from the room
        norm := linalg.normalize([2]f32 {
            -(edge.end.y - edge.start.y),
            edge.end.x - edge.start.x,
        })

        caster2start := linalg.normalize(edge.start - caster)
        caster2end := linalg.normalize(edge.end - caster)

        if linalg.vector_dot(norm, caster2start) > 0 {
            // We are inside the room and it makes sense to cast shadows
            start_screen := rl.GetWorldToScreen2D(edge.start, cam)
            end_screen := rl.GetWorldToScreen2D(edge.end, cam)
            /*if !rl.CheckCollisionPointRec(start_screen, screen) && !rl.CheckCollisionPointRec(end_screen, screen) {
                edge.shadow_present = false
            } else {*/
                edge.shadow_present = true

                // Project the two edges outwards
                edge.shadow_vertices[0] = edge.start
                edge.shadow_vertices[1] = (edge.start + caster2start * 60.0)
                edge.shadow_vertices[2] = (edge.end + caster2end * 60.0)
                edge.shadow_vertices[3] = edge.end
            //}
        } else {
            edge.shadow_present = false
        }
    }
}

// Should be fairly efficient
tilemap_raycast :: proc(tm: Tilemap, start: [2]f32, end: [2]f32) -> (visible: bool) {
    visible = true

    // Raycasting algorithm, kind of similar to Wolfenstein 3D
    // where we just evaluate at the edges of the tiles along
    // the line from start to end
    dir := linalg.normalize(end - start)

    // If we move along the line, every how much distance do we intersect
    // an x = constant line
    delta_x := 1e30 if dir.x == 0 else abs(1.0 / dir.x)
    // Same as before but for y = constant line
    delta_y := 1e30 if dir.y == 0 else abs(1.0 / dir.y)

    // How much distance to first x = constant line, and to first y = constant line
    cell := linalg.to_int(linalg.floor(start))
    endcell := linalg.to_int(linalg.floor(end))

    if cell == endcell do return false

    side_x : f32
    side_y : f32
    step_x := 0
    step_y := 0
    if dir.x < 0 {
        step_x = -1
        side_x = (start.x - f32(cell.x)) * delta_x
    } else {
        step_x = 1
        side_x = (f32(cell.x) + 1 - start.x) * delta_x
    }
    if dir.y < 0 {
        step_y = -1
        side_y = (start.y - f32(cell.y)) * delta_y
    } else {
        step_y = 1
        side_y = (f32(cell.y) + 1 - start.y) * delta_y
    }

    hit := false
    for {
        if cell == endcell {
            break
        }

        if side_x < side_y {
            side_x += delta_x
            cell.x += step_x
        } else {
            side_y += delta_y
            cell.y += step_y
        }


        if cell.y < 0 || cell.x < 0 || cell.y >= tm.height || cell.x >= tm.width {
            hit = true
            break
        }

        if tm.walls[cell.y * tm.width + cell.x] {
            hit = true
            break
        }
    }

    return hit
}

tile_center :: proc(pos: [2]int) -> [2]f32 {
    return [2]f32{f32(pos.x) + 0.5, f32(pos.y) + 0.5}
}

tilemap_find_spawn_pos :: proc(tm: Tilemap) -> [2]int {
    room := rand.choice(tm.rooms[:])
    return room.center
}

draw_world_tilemap :: proc(tm: Tilemap) {
    for &edge in tm.meshing {
        rl.DrawLineEx(edge.start, edge.end, 0.1, rl.WHITE)

    }
    for &edge in tm.meshing {
        if edge.shadow_present {
            rl.DrawTriangleFan(raw_data(edge.shadow_vertices[:]), 4, rl.BLACK)
        }
    }
}

// Renders to a texture. Only call once when generating the actor
render_subscale_tilemap :: proc(tm: Tilemap, frontier: []bool) -> rl.RenderTexture2D {
    out := rl.LoadRenderTexture(
        c.int(tm.width * tm.tileset_size.x), c.int(tm.height * tm.tileset_size.y))
    rl.BeginTextureMode(out)
    rl.ClearBackground(rl.BLACK)

    for y:=0; y < tm.height; y+=1 {
        for x:=0; x < tm.width; x+=1 {
            if frontier[y * tm.width + x] do continue
            tpos := tm.tile_to_tex[y * tm.width + x]
            tile := rl.Rectangle{
                f32(tpos.x * tm.tileset_size.x), f32(tpos.y * tm.tileset_size.y),
                f32(tm.tileset_size.x), f32(tm.tileset_size.y)}
            origin := [2]f32{
                f32(tm.tileset_size.x) * 0.5, f32(tm.tileset_size.y) * 0.5,
            }
            target := rl.Rectangle{
                f32(x * tm.tileset_size.x) + origin.x, f32(y * tm.tileset_size.y) + origin.y,
                f32(tm.tileset_size.x), f32(tm.tileset_size.y)}

            rl.DrawTexturePro(tm.tileset, tile, target, origin,
                tm.tile_rot[y*tm.width + x], tm.tile_tint[y*tm.width + x])
        }
    }

    rl.EndTextureMode()
    return out
}
