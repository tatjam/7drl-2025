package src

import rl "vendor:raylib"

// A tilemap is where the gameplay takes places. It's a
// rectangular grid of tiles which may contain entities
// Tiles are drawn
Tile :: struct {
    scale_color: rl.Color,
    // Texture index in the tilemap
    tex: [2]int,
}

Tilemap :: struct {
    tex: rl.Texture2D,
    tile_size: int,
    tiles: [dynamic]Tile,
}


