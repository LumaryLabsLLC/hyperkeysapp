// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HyperKeysPackage",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "HyperKeysFeature",
            targets: ["HyperKeysFeature"]
        ),
    ],
    targets: [
        // Umbrella target that re-exports all modules
        .target(
            name: "HyperKeysFeature",
            dependencies: [
                "EventEngine",
                "KeyBindings",
                "AppSwitcher",
                "ContextEngine",
                "WindowEngine",
                "Permissions",
                "KeyboardUI",
                "Shared",
            ]
        ),

        // Core event tap and hyper key state machine
        .target(
            name: "EventEngine",
            dependencies: ["Shared"]
        ),

        // Binding models, store, persistence, action executor
        .target(
            name: "KeyBindings",
            dependencies: ["Shared", "EventEngine", "AppSwitcher", "ContextEngine", "WindowEngine"]
        ),

        // App launch/focus, app groups
        .target(
            name: "AppSwitcher",
            dependencies: ["Shared", "WindowEngine"]
        ),

        // Frontmost app observer, menu bar reading
        .target(
            name: "ContextEngine",
            dependencies: ["Shared"]
        ),

        // Window move/resize via Accessibility API
        .target(
            name: "WindowEngine",
            dependencies: ["Shared"]
        ),

        // Permission checking and onboarding
        .target(
            name: "Permissions",
            dependencies: ["Shared"]
        ),

        // SwiftUI keyboard renderer and binding UI
        .target(
            name: "KeyboardUI",
            dependencies: ["Shared", "KeyBindings", "AppSwitcher", "ContextEngine", "EventEngine", "WindowEngine"]
        ),

        // Common types, extensions, persistence helpers
        .target(
            name: "Shared"
        ),

        // Tests
        .testTarget(
            name: "HyperKeysFeatureTests",
            dependencies: ["HyperKeysFeature"]
        ),
    ]
)
