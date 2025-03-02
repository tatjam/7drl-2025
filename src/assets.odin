package src

import rl "vendor:raylib"

AssetManager :: struct {
    textures: map[cstring]rl.Texture2D
}

get_texture :: proc(assets: ^AssetManager, name: cstring) -> rl.Texture2D {
    tex, has_tex := assets.textures[name]
    if has_tex {
        return tex
    } else {
        ntex := rl.LoadTexture(name)
        assets.textures[name] = ntex
        return ntex
    }
}

destroy_assets :: proc(assets: ^AssetManager) {
    for name, tex in assets.textures {
        rl.UnloadTexture(tex)
    }
    delete(assets.textures)
}