package src

import rl "vendor:raylib"
import "core:math/linalg"

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

WorldTilemap :: struct {
    walls: [dynamic]bool,
    width: int,
    height: int,
    meshing: [dynamic]MapEdge,
}

// We take ownership of walls
create_world_tilemap :: proc(walls: [dynamic]bool, exclude: []bool, width: int) -> (out: WorldTilemap) {
    out.walls = walls
    out.width = width
    out.height = len(walls) / width
    mesh_world_tilemap(&out, exclude)
    return out
}

mesh_world_tilemap :: proc(tm: ^WorldTilemap, exclude: []bool = nil) {
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
tilemap_cast_shadows :: proc(tm: WorldTilemap, caster: [2]f32,
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

draw_world_tilemap :: proc(tm: WorldTilemap) {
    for &edge in tm.meshing {
        rl.DrawLineEx(edge.start, edge.end, 0.1, rl.WHITE)

    }
    for &edge in tm.meshing {
        if edge.shadow_present {
            rl.DrawTriangleFan(raw_data(edge.shadow_vertices[:]), 4, rl.BLACK)
        }
    }
}


