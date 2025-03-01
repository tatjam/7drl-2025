package src

import "core:container/priority_queue"
import "core:slice"

taxicab_heuristic :: proc(pos: [2]int, end: [2]int, udata: rawptr) -> int {
    return abs(pos.x - end.x) + abs(pos.y - end.y)
}

path_reconstruct :: proc(came_from: map[[2]int][2]int, start: [2]int, end: [2]int) -> [dynamic][2]int {
    cur := end
    path : [dynamic][2]int
    if end in came_from {
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