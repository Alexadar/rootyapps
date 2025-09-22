//  ContentView.swift
//  mojirows.swift
//
//  Created by Oleksandr Koreniuk on 21.09.2025.
//  Reimplemented: emoji-only 3-in-a-row game (swap to match)

import SwiftUI
import Combine

// Simple match-3 (3-in-a-row) emoji game.
// - Tap one tile, then tap an adjacent tile to swap.
// - If the swap creates a match (3+ in a row horizontally or vertically),
//   matched tiles are removed, score increases, tiles fall down and new emojis appear.
// UI uses emoji for all game art and labels.

fileprivate let EMOJIS = ["🍎","🍋","🍇","🍒","🍊","🍉","🍓","🍩"]

struct Tile: Identifiable, Equatable {
    let id = UUID()
    var emoji: String
    var row: Int
    var col: Int
    var isRemoving: Bool = false
    static func ==(a: Tile, b: Tile) -> Bool { a.id == b.id }
}

final class GameViewModel: ObservableObject {
    let rows: Int
    let cols: Int

    @Published var grid: [[Tile]] = []
    @Published var score: Int = 0
    @Published var selected: Tile? = nil
    @Published var animFlag: Bool = false // toggle to trigger simple animation

    init(rows: Int = 6, cols: Int = 6) {
        self.rows = rows
        self.cols = cols
        resetGrid()
    }

    func resetGrid() {
        score = 0
        grid = Array(repeating: Array(repeating: Tile(emoji: EMOJIS.randomElement()!, row:0, col:0), count: cols), count: rows)
        for r in 0..<rows {
            for c in 0..<cols {
                grid[r][c] = Tile(emoji: EMOJIS.randomElement()!, row: r, col: c)
            }
        }
        // remove any starting matches
        while true {
            let matches = findMatches()
            if matches.isEmpty { break }
            for pair in matches {
                let r = pair[0], c = pair[1]
                grid[r][c].emoji = EMOJIS.randomElement()!
            }
        }
    }

    func tile(atRow r:Int, col c:Int) -> Tile { grid[r][c] }

    func tap(row r:Int, col c:Int) {
        let tapped = grid[r][c]
        if let first = selected {
            if first.row == r && first.col == c {
                // deselect same
                selected = nil
                return
            }
            // if adjacent, attempt swap
            if areAdjacent(a: first, b: tapped) {
                swapAndResolve(a: first, b: tapped)
                selected = nil
            } else {
                // select new
                selected = tapped
            }
        } else {
            selected = tapped
        }
    }

    private func areAdjacent(a: Tile, b: Tile) -> Bool {
        let dr = abs(a.row - b.row)
        let dc = abs(a.col - b.col)
        return (dr == 1 && dc == 0) || (dr == 0 && dc == 1)
    }

    private func swapAndResolve(a: Tile, b: Tile) {
        withAnimation(.easeInOut(duration: 0.18)) {
            swapTiles(a: a, b: b)
        }
        // small delay to let animation happen, then check matches
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self = self else { return }
            let matches = self.findMatches()
            if matches.isEmpty {
                // swap back
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.swapTiles(a: b, b: a)
                }
            } else {
                self.handleMatches()
            }
        }
    }

    private func swapTiles(a: Tile, b: Tile) {
        let ar = a.row, ac = a.col, br = b.row, bc = b.col
        var ta = grid[ar][ac]
        var tb = grid[br][bc]
        // swap emojis only (keep ids and coordinates persistent to animate)
        Swift.swap(&ta.emoji, &tb.emoji)
        grid[ar][ac] = ta
        grid[br][bc] = tb
        // trigger small UI animation
        animFlag.toggle()
    }

    // Find all matched positions (r,c) that are part of 3+ contiguous identical emojis horizontally or vertically.
    func findMatches() -> Set<[Int]> {
        var matches = Set<[Int]>()
        // horizontal
        for r in 0..<rows {
            var runEmoji: String? = nil
            var runStart = 0
            var runLen = 0
            for c in 0..<cols {
                let e = grid[r][c].emoji
                if e == runEmoji {
                    runLen += 1
                } else {
                    if runLen >= 3 {
                        for cc in runStart..<(runStart+runLen) { matches.insert([r, cc]) }
                    }
                    runEmoji = e
                    runStart = c
                    runLen = 1
                }
            }
            if runLen >= 3 {
                for cc in runStart..<(runStart+runLen) { matches.insert([r, cc]) }
            }
        }
        // vertical
        for c in 0..<cols {
            var runEmoji: String? = nil
            var runStart = 0
            var runLen = 0
            for r in 0..<rows {
                let e = grid[r][c].emoji
                if e == runEmoji {
                    runLen += 1
                } else {
                    if runLen >= 3 {
                        for rr in runStart..<(runStart+runLen) { matches.insert([rr, c]) }
                    }
                    runEmoji = e
                    runStart = r
                    runLen = 1
                }
            }
            if runLen >= 3 {
                for rr in runStart..<(runStart+runLen) { matches.insert([rr, c]) }
            }
        }
        return matches
    }

    private func handleMatches() {
        let matches = findMatches()
        guard !matches.isEmpty else { return }
        // Mark removing (for animation)
        for pair in matches {
            let r = pair[0], c = pair[1]
            grid[r][c].isRemoving = true
        }
        // increase score
        score += matches.count * 10
        // small delay to show removal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard let self = self else { return }
            // clear matched emojis
            for pair in matches {
                let r = pair[0], c = pair[1]
                self.grid[r][c].emoji = "" // empty cell
                self.grid[r][c].isRemoving = false
            }
            // drop and refill with animation
            withAnimation(.easeIn(duration: 0.28)) {
                self.collapseColumns()
            }
            // chain further matches after gravity settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                let more = self.findMatches()
                if more.isEmpty {
                    // finished cascade
                    self.animFlag.toggle()
                } else {
                    // continue cascade
                    self.handleMatches()
                }
            }
        }
    }

    private func collapseColumns() {
        for c in 0..<cols {
            var columnEmojis: [String] = []
            for r in (0..<rows).reversed() {
                let e = grid[r][c].emoji
                if e != "" { columnEmojis.append(e) }
            }
            // fill from bottom to top
            var r = rows - 1
            for e in columnEmojis {
                grid[r][c].emoji = e
                r -= 1
            }
            // fill remaining with new random emojis
            while r >= 0 {
                grid[r][c].emoji = EMOJIS.randomElement()!
                r -= 1
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var vm = GameViewModel(rows: 6, cols: 6)
    // grid layout
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: vm.cols) }

    var body: some View {
        ZStack {
            // background
            LinearGradient(colors: [.init(red: 0.08, green: 0.04, blue: 0.08), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // emoji-only header / plot (visual story)
                Text("🌌🍬🍭  ➰  3️⃣➖in➖a➖row  ➰  🎯✨")
                    .font(.title2)
                    .padding(.horizontal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundColor(.white)
                    .shadow(radius: 4)

                // score and controls (emoji labels)
                HStack {
                    HStack(spacing: 8) {
                        Text("💯")
                        Text("\(vm.score)")
                            .monospacedDigit()
                    }
                    .font(.title3)
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundColor(.white)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut) {
                            vm.resetGrid()
                        }
                    } label: {
                        HStack { Text("🔁"); Text("NEW") }
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                    Button {
                        // small nudge animation
                        vm.animFlag.toggle()
                    } label: {
                        Text("✨")
                            .font(.title3)
                            .padding(8)
                    }
                    .foregroundColor(.white)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)

                // grid
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(0..<vm.rows, id: \.self) { r in
                            ForEach(0..<vm.cols, id: \.self) { c in
                                let tile = vm.grid[r][c]
                                TileView(tile: tile, isSelected: vm.selected?.id == tile.id)
                                    .frame(width: (size - CGFloat(vm.cols-1)*8) / CGFloat(vm.cols), height: (size - CGFloat(vm.rows-1)*8) / CGFloat(vm.rows))
                                    .onTapGesture {
                                        vm.tap(row: r, col: c)
                                    }
                            }
                        }
                    }
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                }
                .aspectRatio(1, contentMode: .fit)

                // footer hint in emoji
                Text("👆➡️👆 Tap a tile, then an adjacent tile to swap")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.bottom, 8)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 6)
        }
    }
}

struct TileView: View {
    let tile: Tile
    let isSelected: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.linearGradient(Gradient(colors: [Color.white.opacity(0.04), Color.white.opacity(0.02)]), startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.yellow : Color.white.opacity(0.06), lineWidth: isSelected ? 3 : 1)
                )

            if tile.emoji.isEmpty {
                // invisible placeholder during removal
                Text("")
            } else {
                Text(tile.emoji)
                    .font(.system(size: 34))
                    .scaleEffect(tile.isRemoving ? 0.01 : 1)
                    .opacity(tile.isRemoving ? 0 : 1)
                    .animation(.easeInOut(duration: 0.26), value: tile.isRemoving)
                    .transition(.scale)
            }
        }
        .padding(4)
    }
}

#Preview {
    ContentView()
}
