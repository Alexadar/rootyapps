// For licensing see accompanying LICENSE.md file.
// Copyright (C) 2022 Apple Inc. All Rights Reserved.

/// Protocol for managing internal resources
public protocol ResourceManaging {

    /// Request resources to be loaded and ready if possible
    func loadResources() throws

    /// Request resources are unloaded / remove from memory if possible
    func unloadResources()
}

extension ResourceManaging {
    /// Request resources are pre-warmed by loading and unloading.
    ///
    /// Widened from `internal` to `public` — the second and last change to Apple's sources. The app
    /// forces the Neural Engine compile at launch so the first generation does not pay minutes for
    /// it, and that has to be callable from outside the module.
    public func prewarmResources() throws {
        try loadResources()
        unloadResources()
    }
}
