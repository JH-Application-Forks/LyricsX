//
//  MenuBarLyrics.swift
//  LyricsX - https://github.com/ddddxxx/LyricsX
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Cocoa
import CXExtensions
import CXShim
import GenericID
import LyricsCore
import MusicPlayer
import OpenCC
import SwiftCF
import AccessibilityExt
import OSLog
import MarqueeLabel

class MenuBarLyricsController {
    let logger = Logger(subsystem: "com.JH.LyricsX", category: "MenuBarLyricsController")

    static let shared = MenuBarLyricsController()

    let statusItem: NSStatusItem
    var lyricsItem: NSStatusItem?
    var buttonImage = #imageLiteral(resourceName: "status_bar_icon")
    var buttonlength: CGFloat = 30

    private let marqueeLabel = MarqueeLabel(frame: .init(x: 0, y: 0, width: 183, height: 22))

    private var lastDisplayMode: DisplayMode?

    private enum DisplayMode {
        case separate
        case combine
    }

    private static let defaultLyric = "LyricsX"

    private var screenLyrics: (lyrics: String, duration: TimeInterval) = (MenuBarLyricsController.defaultLyric, 2) {
        didSet {
            DispatchQueue.main.async {
                self.updateStatusItem()
            }
        }
    }

    private var cancelBag = Set<AnyCancellable>()

    private init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        AppController.shared.$currentLyrics
            .combineLatest(AppController.shared.$currentLineIndex)
            .receive(on: DispatchQueue.lyricsDisplay.cx)
            .invoke(MenuBarLyricsController.handleLyricsDisplay, weaklyOn: self)
            .store(in: &cancelBag)
        workspaceNC.cx
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .signal()
            .invoke(MenuBarLyricsController.updateStatusItem, weaklyOn: self)
            .store(in: &cancelBag)
        defaults.publisher(for: [.menuBarLyricsEnabled, .combinedMenubarLyrics])
            .prepend()
            .invoke(MenuBarLyricsController.updateStatusItem, weaklyOn: self)
            .store(in: &cancelBag)
    }

    private func handleLyricsDisplay(event: (lyrics: Lyrics?, index: Int?)) {
        guard !defaults[.disableLyricsWhenPaused] || selectedPlayer.playbackState.isPlaying,
              let lyrics = event.lyrics,
              let index = event.index else {
//            screenLyrics = (MenuBarLyricsController.defaultLyric, 2)
            return
        }
        let currentLine = lyrics.lines[index]
        var newScreenLyrics = currentLine.content
        if let converter = ChineseConverter.shared, lyrics.metadata.language?.hasPrefix("zh") == true {
            newScreenLyrics = converter.convert(newScreenLyrics)
        }
        if newScreenLyrics == screenLyrics.lyrics {
            return
        }
        let lineDisplayTime: TimeInterval
        if let duration = currentLine.attachments.timetag?.duration {
            lineDisplayTime = duration
        } else if let nextLine = lyrics.lines[safe: index + 1] {
            lineDisplayTime = nextLine.position - currentLine.position
        } else {
            lineDisplayTime = 2
        }
        screenLyrics = (newScreenLyrics, lineDisplayTime)
    }

    @objc private func updateStatusItem() {
        guard defaults[.menuBarLyricsEnabled] else {
            setImageStatusItem()
            marqueeLabel.removeFromSuperview()
            lyricsItem = nil
            lastDisplayMode = nil
            return
        }

        if defaults[.combinedMenubarLyrics] {
            updateCombinedStatusLyrics()
            lastDisplayMode = .combine
        } else {
            updateSeparateStatusLyrics()
            lastDisplayMode = .separate
        }
    }

    private func updateSeparateStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .combine {
            setImageStatusItem()
            marqueeLabel.removeFromSuperview()
            lyricsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            lyricsItem?.button?.frame = marqueeLabel.bounds
            lyricsItem?.button?.addSubview(marqueeLabel)
        }

        marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
    }

    private func updateCombinedStatusLyrics() {
        if lastDisplayMode == nil || lastDisplayMode == .separate {
            marqueeLabel.removeFromSuperview()
            lyricsItem = nil
            statusItem.button?.title = ""
            statusItem.button?.image = nil
            statusItem.length = NSStatusItem.variableLength
            statusItem.button?.frame = marqueeLabel.bounds
            statusItem.button?.addSubview(marqueeLabel)
        }

        marqueeLabel.setStringValue(screenLyrics.lyrics, lineDisplayTime: screenLyrics.duration)
    }

    private func setImageStatusItem() {
        statusItem.button?.title = ""
        statusItem.button?.image = buttonImage
        statusItem.length = buttonlength
    }
}

// MARK: - Status Item Visibility

extension NSStatusItem {
    fileprivate var isVisibe: Bool {
        guard let buttonFrame = button?.frame,
              let frame = button?.window?.convertToScreen(buttonFrame) else {
            return false
        }

        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else {
            return false
        }
        let carbonPoint = CGPoint(x: point.x, y: screen.frame.height - point.y - 1)

        guard let element = try? AXUIElement.systemWide().element(at: carbonPoint),
              let pid = try? element.pid() else {
            return false
        }

        return getpid() == pid
    }
}

extension String {
    fileprivate func components(options: String.EnumerationOptions) -> [String] {
        var components: [String] = []
        let range = Range(uncheckedBounds: (startIndex, endIndex))
        enumerateSubstrings(in: range, options: options) { _, _, range, _ in
            components.append(String(self[range]))
        }
        return components
    }
}

extension Array {
    subscript(safe safeIndex: Int) -> Element? {
        if safeIndex >= 0, safeIndex < count {
            return self[safeIndex]
        } else {
            return nil
        }
    }
}
