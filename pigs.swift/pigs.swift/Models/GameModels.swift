import Foundation

struct GridPosition: Equatable {
    var x: Int
    var y: Int
    
    init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

struct Player {
    var position: GridPosition
    var emoji: String
    
    init() {
        self.position = GridPosition(x: 1, y: 1)
        self.emoji = "🐷"
    }
}

struct Enemy {
    let id: UUID
    var position: GridPosition
    let emoji: String
    let speed: Double
    var direction: Direction
    
    init(id: UUID, position: GridPosition, emoji: String, speed: Double, direction: Direction) {
        self.id = id
        self.position = position
        self.emoji = emoji
        self.speed = speed
        self.direction = direction
    }
}

struct Treasure {
    let id: UUID
    let position: GridPosition
    let emoji: String
    let value: Int
    var collected: Bool
    
    init(id: UUID, position: GridPosition, emoji: String, value: Int, collected: Bool) {
        self.id = id
        self.position = position
        self.emoji = emoji
        self.value = value
        self.collected = collected
    }
}

struct MazeCell {
    let isWall: Bool
    let x: Int
    let y: Int
    
    init(isWall: Bool, x: Int, y: Int) {
        self.isWall = isWall
        self.x = x
        self.y = y
    }
}
