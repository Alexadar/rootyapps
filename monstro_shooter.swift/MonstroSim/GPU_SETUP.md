# Running the GPU (MLX) target

mlx-swift's Metal kernel library (`default.metallib`) is built by Xcode's Metal toolchain,
NOT by plain `swift build`. One-time setup so `swift build`/`swift test`/`swift run` can run GPU code:

1. Build once via Xcode's build system to produce the metallib:
   xcodebuild build -scheme MonstroSim-Package -destination 'platform=macOS' 2>/dev/null || true
2. Stage it where MLX looks at runtime (CWD fallback + colocated):
   MLIB=$(find ~/Library/Developer/Xcode/DerivedData/MonstroSim-* -name default.metallib -path '*mlx-swift_Cmlx*' | head -1)
   cp "$MLIB" ./default.metallib
   cp "$MLIB" .build/arm64-apple-macosx/debug/mlx.metallib

Then run normally from this dir: `swift test`, `swift run monstrosim ...`.
(`default.metallib` is git-ignored; regenerate with the steps above.)
