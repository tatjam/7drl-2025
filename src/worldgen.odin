package src

import "core:container/priority_queue"
import "core:slice"
import "core:math/rand"
import "core:math/linalg"
import "core:math"
import "core:image"
import "core:image/png"
import "core:bytes"

taxicab_heuristic :: proc(pos: [2]int, end: [2]int, udata: rawptr) -> int {
    return abs(pos.x - end.x) + abs(pos.y - end.y)
}

path_reconstruct :: proc(came_from: map[[2]int][2]int, start: [2]int, end: [2]int) -> [dynamic][2]int {
    cur := end
    path : [dynamic][2]int
    if end not_in came_from {
        return path
    }

    for cur != start {
        append(&path, cur)
        cur = came_from[cur]
    }

    append(&path, start)
    slice.reverse(path[:])

    return path
}

// Assumes a rectangular grid map, but searches diagonals.
// Takes the following functions:
// traverse_cost(cur: [2]int, next: [2]int, udata) -> int
//      Return how costly it's to traverse the tile from the given position
//      Return MAX_INT for untraversable!
// heuristic(pos: [2]int, end: [2]int, udata) -> int
//      Return how good is pos with respect to end. This is usually distance
// Returns the list of tiles visited on the path from start to end, including both
astar :: proc(start: [2]int, end: [2]int,
    traverse_cost: proc(cur: [2]int, next: [2]int, udata: rawptr)->int,
    udata: rawptr,
    search_diagonals: bool,
    heuristic := taxicab_heuristic) -> [dynamic][2]int {

    come_from: map[[2]int][2]int
    cost_so_far: map[[2]int]int
    defer delete(come_from)
    defer delete(cost_so_far)

    come_from[start] = start
    cost_so_far[start] = 0

    PointAndPriority :: struct {
        p: [2]int,
        priority: int,
    }

    less :: proc(a, b: PointAndPriority) -> bool {
        return a.priority < b.priority
    }

    // IntelliJ odin plugin reports an error on next line, it's not correct
    frontier := priority_queue.Priority_Queue(PointAndPriority){}
    priority_queue.init(&frontier, less, priority_queue.default_swap_proc(PointAndPriority))

    priority_queue.push(&frontier, PointAndPriority{start, 0})

    for priority_queue.len(frontier) != 0 {
        cur := priority_queue.pop(&frontier)

        if cur.p == end {
            break
        }

        for dx := -1; dx < 1; dx += 1 {
            for dy := -1; dy < 1; dy += 1 {
                if abs(dx) + abs(dy) == 0 do continue
                if !search_diagonals && (abs(dx) + abs(dy) != 1) do continue
                next := cur.p + [2]int{dx, dy}

                delta_cost := traverse_cost(cur.p, next, udata)
                new_cost := cost_so_far[cur.p] + delta_cost

                next_cost_so_far, next_explored := cost_so_far[next]
                if !next_explored || new_cost < next_cost_so_far {
                    cost_so_far[next] = new_cost
                    priority := new_cost + heuristic(next, end, udata)
                    priority_queue.push(&frontier, PointAndPriority{next, priority})
                    come_from[next] = cur.p
                }
            }
        }


    }

    return path_reconstruct(come_from, start, end)
}

DungeonSettings :: struct {
    max_room_size: [2]int,
    min_room_size: [2]int,
    // It's only a suggestion
    num_rooms: int,
}

WallMap :: struct {
    wall: []bool,
    width: int
}

// Shrinks the given wall outline by applying the kernel:
//      [1][1][1]
// 1 if [1][1][1]  0 otherwise
//      [1][1][1]
// The returned array has the same dimensions as the original!
shrink_wall :: proc(wall: []bool, width: int) -> [dynamic]bool {
    height := len(wall) / width
    owall := make([dynamic]bool, width * height)

    for y := 0; y < height; y += 1 {
        for x := 0; x < width; x += 1 {
            good := true
            outer: for dy := -1; dy <= 1; dy += 1 {
                cy := y + dy
                if cy < 0 || cy >= height {
                    good = false
                    break outer
                }
                for dx := -1; dx <= 1; dx += 1 {
                    cx := x + dx

                    if cx < 0 || cx >= width {
                        good = false
                        break outer
                    }

                    if !wall[cy * width + cx] {
                        good = false
                        break outer
                    }
                }
            }

            owall[y * width + x] = good
        }
    }

    return owall
}

wall_from_image :: proc(imagepath: string) -> (out: [dynamic]bool, width: int) {
    img, err := png.load_from_file(imagepath, image.Options{})
    assert(err == nil)
    defer png.destroy(img)

    out = make_dynamic_array_len([dynamic]bool, img.width * img.height)
    width = img.width

    pixels := bytes.buffer_to_bytes(&img.pixels)

    assert(img.depth == 8, "Unsupported PNG, use 8-bit depth for walls!")
    assert(img.channels <= 4, "Unsupported PNG, use at most RGBA channels for walls!")
    assert(len(pixels) >= img.width * img.height * int(img.channels) * img.depth / 8)

    // Each pixel is img.channels bytes long, indexed as
    for yi := 0; yi < img.height; yi+=1 {
        for xi := 0; xi < img.width; xi+=1 {
            pix := [4]u8{0, 0, 0, 0}
            for ci := 0; ci < img.channels; ci+=1 {
                pix[ci] = pixels[(yi * img.width + xi) * img.channels + ci]
            }
            is_wall := pix[0] != 0 || pix[1] != 0 || pix[2] != 0 || pix[3] != 0
            out[yi * img.width + xi] = is_wall
        }
    }

    return
}

DungeonRoom :: struct {
    tl: [2]int, // top-left
    br: [2]int, // bottom-right
}

DungeonCorridor :: struct {

}

DungeonElement :: union {
    DungeonRoom,
    DungeonCorridor,
}

// Generates a dungeon within any space in wall that's true. Spaces set to false
// will remain false (i.e. it will only dig), and it will not break the "envelope"
// of the given wall. All rooms will be connected
// wall is assumed to be indexed y * width + x
// Note that it modifies wall!
dungeon_gen :: proc(wall: []bool, width: int, sets: DungeonSettings) ->
    (owall: []bool, elems: [dynamic]DungeonElement) {

    swall := shrink_wall(wall, width)
    defer delete(swall)
    owall = slice.clone(wall)
    defer delete(wall)


    height := len(wall) / width


    // Place non-intersecting rooms
    MAX_ITER :: 1000
    MAX_PLACE_ITER :: 50
    placed_rooms := 0
    for it := 0; it < MAX_ITER; it += 1 {
        dim := [2]int{
            int(math.round(rand.float32_range(f32(sets.min_room_size.x), f32(sets.max_room_size.x)))),
            int(math.round(rand.float32_range(f32(sets.min_room_size.y), f32(sets.max_room_size.y))))
        }

        // Try to find an spot in which the room fits
        tl := [2]int{}
        br := [2]int{}
        place_loop: for sit := 0; sit < MAX_PLACE_ITER; sit += 1 {
            tl = [2]int {
                int(math.round(rand.float32_range(0, f32(width)))),
                int(math.round(rand.float32_range(0, f32(height)))),
            }
            br = tl + br

            // Check that it doesn't intersect any other room element
            for other_room in elems {
                room, is_room := other_room.(DungeonRoom)
                if !is_room do continue

                // Overlap check
                if room.tl.x <= br.x && room.br.x >= tl.x do continue place_loop
                if room.tl.y <= br.y && room.br.y >= tl.y do continue place_loop
            }


            // Check that it doesn't intersect any non-wall element of the
            // shrunk wall set (thus guaranteeing the envelope is good)
            for ty := tl.y; ty <= br.y; ty += 1 {
                for tx := tl.x; tx <= br.x; tx += 1 {
                    if tx < 0 || ty < 0 || tx >= width || ty >= height do continue place_loop
                    if swall[ty * width + tx] == false do continue place_loop
                }
            }

            // It's okay! It doesn't intersect anything
            break
        }

        // It's okay! Place the room
        placed_rooms += 1
        room := DungeonRoom{
            tl = tl,
            br = br
        }
        append(&elems, room)

        if placed_rooms > sets.num_rooms {
            break
        }
    }

    return

}