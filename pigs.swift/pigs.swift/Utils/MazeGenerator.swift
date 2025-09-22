import Foundation

struct MazeGenerator {
    // Simple randomized DFS maze generator with some walls retained to match GameConstants.wallDensity
    static func generateMaze(width: Int, height: Int) -> [[MazeCell]] {
        // Initialize all cells as walls with proper coordinates
        var maze = Array(repeating: Array(repeating: MazeCell(isWall: true, x: 0, y: 0), count: width), count: height)
        for y in 0..<height {
            for x in 0..<width {
                maze[y][x] = MazeCell(isWall: true, x: x, y: y)
            }
        }
        
        // Keep visited map
        var visited = Array(repeating: Array(repeating: false, count: width), count: height)
        
        func neighbors(of x: Int, _ y: Int) -> [(Int, Int, Int, Int)] {
            // returns cell two steps away and the intermediate cell coordinates: (nx, ny, mx, my)
            var result: [(Int, Int, Int, Int)] = []
            let dirs = [ (0, -2), (0, 2), (-2, 0), (2, 0) ]
            for (dx, dy) in dirs {
                let nx = x + dx
                let ny = y + dy
                let mx = x + dx/2
                let my = y + dy/2
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    result.append((nx, ny, mx, my))
                }
            }
            return result
        }
        
        // Start at a random odd coordinate (to ensure walls between cells)
        let startX = max(1, Int.random(in: 1..<(width-1)) | 1) // force odd
        let startY = max(1, Int.random(in: 1..<(height-1)) | 1)
        var stack: [(Int, Int)] = []
        visited[startY][startX] = true
        maze[startY][startX] = MazeCell(isWall: false, x: startX, y: startY)
        stack.append((startX, startY))
        
        while let (cx, cy) = stack.last {
            var nbors = neighbors(of: cx, cy)
            nbors.shuffle()
            var carved = false
            for (nx, ny, mx, my) in nbors {
                if !visited[ny][nx] {
                    // carve passage: intermediate and target
                    visited[ny][nx] = true
                    maze[my][mx] = MazeCell(isWall: false, x: mx, y: my)
                    maze[ny][nx] = MazeCell(isWall: false, x: nx, y: ny)
                    stack.append((nx, ny))
                    carved = true
                    break
                }
            }
            if !carved {
                _ = stack.popLast()
            }
        }
        
        // Apply additional random walls to reach approximate wall density while preserving connectivity roughly
        let targetWallDensity = GameConstants.wallDensity
        let totalCells = width * height
        var currentWallCount = maze.flatMap { $0 }.filter { $0.isWall }.count
        let targetWallCount = Int(Double(totalCells) * targetWallDensity)
        
        if currentWallCount < targetWallCount {
            var candidates: [(Int, Int)] = []
            for y in 0..<height {
                for x in 0..<width {
                    if !maze[y][x].isWall {
                        // avoid turning start cell or immediate neighbors into walls arbitrarily
                        candidates.append((x, y))
                    }
                }
            }
            candidates.shuffle()
            var i = 0
            while currentWallCount < targetWallCount && i < candidates.count {
                let (x, y) = candidates[i]
                // Prevent isolating large areas: only add wall if at least two adjacent open neighbors exist
                let openNeighbors = [
                    (x+1, y), (x-1, y), (x, y+1), (x, y-1)
                ].filter { nx, ny in
                    nx >= 0 && nx < width && ny >= 0 && ny < height && !maze[ny][nx].isWall
                }
                if openNeighbors.count >= 2 {
                    maze[y][x] = MazeCell(isWall: true, x: x, y: y)
                    currentWallCount += 1
                }
                i += 1
            }
        }
        
        return maze
    }
}
