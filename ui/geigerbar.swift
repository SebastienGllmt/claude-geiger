// geigerbar.swift — a macOS menu bar toggle for claude-geiger.
//
// Puts a ☢ (atom) icon in the menu bar. Click it for a menu that mutes /
// unmutes the geiger clicks. The choice is persisted to
// ~/.config/claude-geiger/enabled (a file containing "1" or "0"), which
// geiger.sh reads on every poll — so muting takes effect live, with no
// Claude Code restart.
//
// Uses SwiftUI's MenuBarExtra (macOS 13+) — the modern, declarative way to
// add a menu bar item, with less boilerplate than AppKit's NSStatusItem.
// Build & run via ./menubar.sh (compiled with -parse-as-library so @main
// works). Runs as an accessory app (no Dock icon).

import SwiftUI

let configDir = ("~/.config/claude-geiger" as NSString).expandingTildeInPath
let stateFile = (configDir as NSString).appendingPathComponent("enabled")

func readEnabled() -> Bool {
    guard let s = try? String(contentsOfFile: stateFile, encoding: .utf8) else {
        return true  // no file yet -> default on, matching geiger.sh
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines) != "0"
}

func writeEnabled(_ on: Bool) {
    try? FileManager.default.createDirectory(
        atPath: configDir, withIntermediateDirectories: true)
    try? (on ? "1" : "0").write(toFile: stateFile, atomically: true, encoding: .utf8)
}

@main
struct GeigerBarApp: App {
    @State private var enabled = readEnabled()

    var body: some Scene {
        MenuBarExtra {
            Button(enabled ? "Mute geiger clicks" : "Unmute geiger clicks") {
                enabled.toggle()
                writeEnabled(enabled)
            }
            Divider()
            Button("Quit Geiger Menu Bar") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            // Atom glyph, dimmed when muted.
            Image(systemName: "atom")
                .opacity(enabled ? 1.0 : 0.4)
        }
        .menuBarExtraStyle(.menu)
    }
}
