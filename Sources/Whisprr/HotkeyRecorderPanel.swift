import AppKit

final class HotkeyRecorderPanel {
    private var panel: NSPanel?
    private var displayLabel: NSTextField?
    private var warningLabel: NSTextField?
    private var saveButton: NSButton?

    private var capturedHotkey: Hotkey?
    private var completion: ((Hotkey?) -> Void)?

    // Solo modifier detection state
    private var modifierKeyCode: UInt16?
    private var modifierFlag: UInt?
    private var keyDownDuringModifier = false

    private var localMonitor: Any?
    private var flagMonitor: Any?

    // System shortcuts to block
    private static let blockedCombinations: [(keyCode: UInt16, modifiers: NSEvent.ModifierFlags)] = [
        (12, .command),  // Cmd+Q
        (8, .command),   // Cmd+C
        (9, .command),   // Cmd+V
        (48, .command),  // Cmd+Tab
        (49, .command),  // Cmd+Space
    ]

    func show(completion: @escaping (Hotkey?) -> Void) {
        self.completion = completion
        self.capturedHotkey = nil

        let panel = makePanel()
        self.panel = panel

        // Center on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.midY - panel.frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startMonitoring()
    }

    private func startMonitoring() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleEvent(event) ? nil : event
        }
    }

    private func stopMonitoring() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleEvent(_ event: NSEvent) -> Bool {
        if event.type == .keyDown {
            // Escape cancels
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                cancel()
                return true
            }

            // Skip key repeat
            if event.isARepeat { return true }

            // If a modifier key is down, this is a combination, not a solo modifier
            keyDownDuringModifier = true
            modifierKeyCode = nil
            modifierFlag = nil

            let mods = event.modifierFlags.intersection([.command, .option, .shift, .control, .function])
            guard !mods.isEmpty else { return true }  // Need at least one modifier for a combo

            // Check for blocked system shortcuts
            for blocked in Self.blockedCombinations {
                if event.keyCode == blocked.keyCode && mods == blocked.modifiers {
                    showWarning("That shortcut conflicts with a system shortcut.")
                    return true
                }
            }

            let hotkey = Hotkey.combination(keyCode: event.keyCode, modifiers: mods.rawValue)
            capturedHotkey = hotkey
            displayLabel?.stringValue = hotkey.displayName
            warningLabel?.isHidden = true
            saveButton?.isEnabled = true
            return true
        }

        if event.type == .flagsChanged {
            let keyCode = event.keyCode
            let isModifierKey = [54, 55, 56, 60, 58, 61, 59, 62, 63].contains(keyCode)
            guard isModifierKey else { return true }

            // Filter out Fn/Caps Lock — only allow ⌘ ⌥ ⇧ ⌃
            let relevantFlags = event.modifierFlags.intersection([.command, .option, .shift, .control, .function])

            if !relevantFlags.isEmpty {
                // Modifier pressed down
                modifierKeyCode = keyCode
                modifierFlag = relevantFlags.rawValue
                keyDownDuringModifier = false

                // Show preview
                let preview = Hotkey.soloModifier(keyCode: keyCode, modifierFlag: relevantFlags.rawValue)
                displayLabel?.stringValue = preview.displayName
                warningLabel?.isHidden = true
            } else if let mkc = modifierKeyCode, mkc == keyCode, !keyDownDuringModifier {
                // Modifier released with no key press in between → solo modifier
                let hotkey = Hotkey.soloModifier(keyCode: mkc, modifierFlag: modifierFlag ?? 0)
                capturedHotkey = hotkey
                displayLabel?.stringValue = hotkey.displayName
                saveButton?.isEnabled = true
                modifierKeyCode = nil
                modifierFlag = nil
            } else {
                modifierKeyCode = nil
                modifierFlag = nil
            }
            return true
        }

        return false
    }

    private func showWarning(_ message: String) {
        warningLabel?.stringValue = message
        warningLabel?.isHidden = false
    }

    @objc private func saveAction() {
        let hotkey = capturedHotkey
        dismiss()
        completion?(hotkey)
    }

    @objc private func cancelAction() {
        cancel()
    }

    private func cancel() {
        dismiss()
        completion?(nil)
    }

    private func dismiss() {
        stopMonitoring()
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Panel Construction

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Change Hotkey"
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let contentView = NSView(frame: panel.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]

        // Instruction label
        let instruction = NSTextField(labelWithString: "Press your desired shortcut...")
        instruction.translatesAutoresizingMaskIntoConstraints = false
        instruction.font = .systemFont(ofSize: 14, weight: .medium)
        instruction.alignment = .center
        contentView.addSubview(instruction)

        // Display label for current capture
        let display = NSTextField(labelWithString: "—")
        display.translatesAutoresizingMaskIntoConstraints = false
        display.font = .systemFont(ofSize: 28, weight: .bold)
        display.alignment = .center
        display.textColor = .labelColor
        contentView.addSubview(display)
        self.displayLabel = display

        // Tip text
        let tip = NSTextField(labelWithString: "Tap a modifier alone (like Right ⌘) or press a key combo")
        tip.translatesAutoresizingMaskIntoConstraints = false
        tip.font = .systemFont(ofSize: 11)
        tip.textColor = .secondaryLabelColor
        tip.alignment = .center
        contentView.addSubview(tip)

        // Warning label
        let warning = NSTextField(labelWithString: "")
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.font = .systemFont(ofSize: 11)
        warning.textColor = .systemRed
        warning.alignment = .center
        warning.isHidden = true
        contentView.addSubview(warning)
        self.warningLabel = warning

        // Buttons
        let save = NSButton(title: "Save", target: self, action: #selector(saveAction))
        save.translatesAutoresizingMaskIntoConstraints = false
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.isEnabled = false
        contentView.addSubview(save)
        self.saveButton = save

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelAction))
        cancel.translatesAutoresizingMaskIntoConstraints = false
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancel)

        NSLayoutConstraint.activate([
            instruction.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            instruction.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            display.topAnchor.constraint(equalTo: instruction.bottomAnchor, constant: 16),
            display.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            display.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 20),
            display.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -20),

            tip.topAnchor.constraint(equalTo: display.bottomAnchor, constant: 8),
            tip.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            warning.topAnchor.constraint(equalTo: tip.bottomAnchor, constant: 4),
            warning.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            save.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            save.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            cancel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancel.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -8),
        ])

        panel.contentView = contentView
        return panel
    }
}
