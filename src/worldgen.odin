package src

import "core:container/priority_queue"
import "core:slice"
import "core:math/linalg"
import "core:math"
import "core:image"
import "core:image/png"
import "core:bytes"
import rl "vendor:raylib"
import "core:c"
import "core:log"
import "core:math/rand"

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
//      Return max(int) for untraversable!
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
    defer priority_queue.destroy(&frontier)

    priority_queue.init(&frontier, less, priority_queue.default_swap_proc(PointAndPriority))

    priority_queue.push(&frontier, PointAndPriority{start, 0})

    for priority_queue.len(frontier) != 0 {
        cur := priority_queue.pop(&frontier)

        if cur.p == end {
            break
        }

        for dx := -1; dx <= 1; dx += 1 {
            for dy := -1; dy <= 1; dy += 1 {
                if abs(dx) + abs(dy) == 0 do continue
                if !search_diagonals && (abs(dx) + abs(dy) != 1) do continue
                next := cur.p + [2]int{dx, dy}

                delta_cost := traverse_cost(cur.p, next, udata)
                if delta_cost == max(int) do continue

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

// Paths through wall with given wall and empty costs, but
// includes an additional, optional (pass nil if unused)
// frontier value, which is blocks that MAY NOT BE TRANSVERSED
astar_wall :: proc(start, end: [2]int, wall: []bool, width: int,
    wall_cost:=max(int), empty_cost:=0, frontier:[]bool=nil) -> [dynamic][2]int {

    if frontier != nil do assert(len(frontier) == len(wall))

    WallPair :: struct {
        wall: []bool,
        frontier: []bool,
        width: int,
        height: int,
        wall_cost: int,
        empty_cost: int
    }
    cost_func :: proc(cur, next: [2]int, wallptr: rawptr) -> int {
        wall := (^WallPair)(wallptr)


        if next.x < 0 || next.y < 0 || next.x > wall.width || next.y > wall.height {
            return max(int)
        }

        if wall.frontier != nil && wall.frontier[next.y * wall.width + next.x] {
            return max(int)
        }

        if wall.wall[next.y * wall.width + next.x] {
            return wall.wall_cost
        } else {
            return wall.empty_cost
        }
    }
    pair := WallPair{
        wall=wall, width=width, height=len(wall) / width,
        wall_cost=wall_cost, empty_cost=empty_cost, frontier=frontier
    }

    return astar(start, end, cost_func, &pair, false)
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

// Grows the given wall outline by applying the kernel
//      [x][x][x]
// 1 if [x][0][x]  0 otherwise
//      [x][x][x]
// (if any of the x is 1, then we return 1)
grow_wall :: proc(wall: []bool, width: int) -> [dynamic]bool {
    height := len(wall) / width
    owall := make([dynamic]bool, width * height)

    for y := 0; y < height; y += 1 {
        for x := 0; x < width; x += 1 {
            good := false

            outer: for dy := -1; dy <= 1; dy += 1 {
                cy := y + dy
                if cy < 0 || cy >= height do continue
                for dx := -1; dx <= 1; dx += 1 {
                    cx := x + dx

                    if cx < 0 || cx >= width do continue

                    if wall[cy * width + cx] {
                        good = true
                        break outer
                    }
                }
            }

            owall[y * width + x] = good
        }
    }

    return owall
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

wall_xor :: proc(wall1, wall2: []bool, width: int) -> [dynamic]bool {
    assert(len(wall1) == len(wall2))
    height := len(wall1) / width

    owall := make([dynamic]bool, width * height)

    for yi:=0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            i := yi * width + xi
            owall[i] = wall1[i] ~ wall2[i]
        }
    }

    return owall
}

wall_nand :: proc(wall1, wall2: []bool, width: int) -> [dynamic]bool {
    assert(len(wall1) == len(wall2))
    height := len(wall1) / width

    owall := make([dynamic]bool, width * height)

    for yi:=0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            i := yi * width + xi
            owall[i] = !(wall1[i] && wall2[i])
        }
    }

    return owall
}


MapTag :: struct {
    pos: [2]int,
    tag: [3]u8
}

wall_from_image :: proc(imagepath: string) -> (out: [dynamic]bool, width: int, tags: [dynamic]MapTag) {
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
            is_wall := pix[0] == 255  && pix[1] == 255 && pix[2] == 255
            is_empty := pix[0] == 0 && pix[1] == 0 && pix[2] == 0
            if !is_wall && !is_empty {
                // tag
                append(&tags, MapTag{[2]int{xi, yi}, pix.xyz})
            }
            out[yi * img.width + xi] = !is_empty
        }
    }

    return
}

// FOR DEBUGGING ONLY
preview_wall :: proc(wall: []bool, width: int, off: [2]c.int, tint: rl.Color) {
    for yi:=0; yi < len(wall) / width; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            if wall[yi*width + xi] {
                for sxi := -1; sxi <= 1; sxi += 1 {
                    for syi := -1; syi <= 1; syi += 1 {
                        rl.DrawPixel(c.int(xi * 3 + sxi) + off.x, c.int(yi * 3 + syi) + off.y, tint)
                    }
                }
            }
        }
    }
}

DungeonRoom :: struct {
    tl: [2]int, // top-left
    br: [2]int, // bottom-right
    center: [2]int,
    cgroup: int,
}

DungeonCorridor :: struct {

}

// Generates a dungeon within any space in wall that's true. Spaces set to false
// will remain false (i.e. it will only dig), and it will not break the "envelope"
// of the given wall. All rooms will be connected
// wall is assumed to be indexed y * width + x
dungeon_gen :: proc(wall: []bool, width: int, sets: DungeonSettings) ->
    (owall: [dynamic]bool, rooms: [dynamic]DungeonRoom, mapedge: [dynamic]bool) {

    swall := shrink_wall(wall, width)
    defer delete(swall)
    owall = slice.clone_to_dynamic(wall)
    frontier := wall_xor(swall[:], wall[:], width)
    defer delete(frontier)

    gwall := grow_wall(wall, width)
    defer delete(gwall)
    mapedge = wall_nand(gwall[:], wall[:], width)


    height := len(wall) / width


    // Place non-intersecting rooms
    MAX_ITER :: 100
    MAX_PLACE_ITER :: 10
    placed_rooms := 0
    for it := 0; it < MAX_ITER; it += 1 {
        dim := [2]int{
            int(rl.GetRandomValue(c.int(sets.min_room_size.x), c.int(sets.max_room_size.x))),
            int(rl.GetRandomValue(c.int(sets.min_room_size.y), c.int(sets.max_room_size.y))),
        }

        // Try to find an spot in which the room fits
        tl := [2]int{}
        br := [2]int{}
        found := false
        place_loop: for sit := 0; sit < MAX_PLACE_ITER; sit += 1 {
            tl = [2]int {
                int(rl.GetRandomValue(0, c.int(width))),
                int(rl.GetRandomValue(0, c.int(height)))
            }
            br = tl + dim

            // Check that it doesn't intersect any other room element
            for room in rooms {
                // Overlap check (with extension to prevent no walls)
                if  (room.tl.x <= br.x + 1 && room.br.x >= tl.x - 1) &&
                    (room.tl.y <= br.y + 1 && room.br.y >= tl.y - 1) {
                    continue place_loop
                }
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
            found = true
            break
        }

        if !found do continue

        // It's okay! Place the room
        room := DungeonRoom{
            tl = tl,
            br = br,
            center = (tl + br) / 2,
            cgroup = max(int) // (unconnected)
        }
        append(&rooms, room)
        for ty := tl.y; ty <= br.y; ty += 1 {
            for tx := tl.x; tx <= br.x; tx += 1 {
                assert(tx >= 0 && ty >= 0 && tx < width && ty < height)
                owall[ty * width + tx] = false
            }
        }

        placed_rooms += 1

        if placed_rooms >= sets.num_rooms {
            break
        }
    }


    // We now run a corridor for random pairs of room until all of them
    // have been connected. We start with the full array:
    unconnected := make_dynamic_array_len([dynamic]int, len(rooms))
    defer delete(unconnected)
    for i := 0; i < len(rooms); i+=1 {
        unconnected[i] = i
    }

    // We expand the rooms so corridors leave perpendicular to them
    // (To expand them, we must shrink the walls, as walls are carved into them)
    expand_rooms := shrink_wall(owall[:], width)
    defer delete(expand_rooms)

    cgroup := 0

    join_rooms :: proc(rooms: []DungeonRoom, owall: []bool,
        expand_rooms: []bool, frontier: []bool, width: int,
        room1, room2: int, cgroup: ^int) {

        path := astar_wall(rooms[room1].center, rooms[room2].center,
        expand_rooms, width, 0, 100, frontier)
        defer delete(path)

        assert(len(path) != 0, "Somehow, unreachable rooms were generated!")

        if cgroup != nil {
            if rooms[room1].cgroup == max(int) && rooms[room2].cgroup == max(int) {
                rooms[room1].cgroup = cgroup^
                cgroup^ += 1
            }

            ngroup := min(rooms[room1].cgroup, rooms[room2].cgroup)
            rooms[room1].cgroup = ngroup
            rooms[room2].cgroup = ngroup
        }

        for step in path {
            owall[step.y * width + step.x] = false
        }

    }

    for len(unconnected) > 0 {
        room1, room2 : int
        if len(unconnected) >= 2 {
            // Connect a random pair of rooms
            room1i := rl.GetRandomValue(0, c.int(len(unconnected) - 1))
            room1 = unconnected[room1i]
            unordered_remove(&unconnected, room1i)

            room2i := rl.GetRandomValue(0, c.int(len(unconnected) - 1))
            room2 = unconnected[room2i]
            unordered_remove(&unconnected, room2i)

        } else {
            assert(len(unconnected) == 1)
            // Connect remaining room to a random one
            room1 = unconnected[0]
            if room1 + 1 < len(rooms) {
                room2 = room1 + 1
            } else {
                assert(room1 > 0)
                room2 = room1 - 1
            }

            unordered_remove(&unconnected, 0)
        }


        join_rooms(rooms[:], owall[:], expand_rooms[:], frontier[:], width, room1, room2, &cgroup)

    }

    // Now connect two pairs of rooms with different cgroup, until
    // no such groups can be found. This will usually complete very fast
    cgroups_seen: map[int]int
    defer delete(cgroups_seen)
    for i:=0; i < len(rooms); i+=1 {
        cgroups_seen[rooms[i].cgroup] = i
    }

    for len(cgroups_seen) >= 2 {
        // The two groups will become the same, thus one may be removed
        cgroup0, cgroup1, room0, room1: int
        it := 0
        for icgroup, iroom in cgroups_seen {
            if it == 0 {
                cgroup0 = icgroup
                room0 = iroom
            } else {
                cgroup1 = icgroup
                room1 = iroom
            }
            it += 1
            if it == 2 do break
        }

        delete_key(&cgroups_seen, cgroup1)
        for &room in rooms {
            if room.cgroup == cgroup1 {
                room.cgroup = cgroup0
            }
        }

        join_rooms(rooms[:], owall[:], expand_rooms[:], frontier[:], width, room0, room1, nil)
    }


    return

}

create_world :: proc(width, height: int, sets: DungeonSettings) -> Tilemap {
    empty_wall := make_dynamic_array_len([dynamic]bool, width * height)
    for yi := 0; yi < height; yi+=1 {
        for xi:=0; xi < width; xi+=1 {
            empty_wall[yi * width + xi] = true
        }
    }

    dungeon, dungeon_rooms, frontier := dungeon_gen(empty_wall[:], width, sets)
    delete(empty_wall)
    worldmap := create_tilemap(dungeon, frontier, width, dungeon_rooms)

    return worldmap
}