package src

Direction :: enum {
    NORTH,
    EAST,
    SOUTH,
    WEST
}

BaseEntity :: struct {
    pos: [2]int,
    dir: Direction,
}

SubscaleEntity :: struct {
    using base: BaseEntity,
}

BigEntity :: struct {
    using base: BaseEntity,
}

Entity :: union {
    SubscaleEntity,
    BigEntity
}