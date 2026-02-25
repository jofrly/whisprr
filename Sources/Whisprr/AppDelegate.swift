import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!

    private let audioRecorder = AudioRecorder()
    private let transcriptionService = TranscriptionService()

    private var state: AppState = .idle {
        didSet { updateUI() }
    }

    private var apiKey: String {
        get {
            // Prefer environment variable (set in terminal before `swift run`)
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
                return envKey
            }
            return UserDefaults.standard.string(forKey: "gemini_api_key") ?? ""
        }
        set { UserDefaults.standard.set(newValue, forKey: "gemini_api_key") }
    }

    // Track Right Cmd key state to detect solo press (no combo)
    private var rightCmdDown = false
    private var otherKeysDuringRightCmd = false

    enum AppState {
        case idle, recording, transcribing, pasting
    }

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()

        // Check accessibility on launch
        if !TextPaster.checkAccessibility() {
            TextPaster.promptAccessibility()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Whisprr")
        }

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Idle — Right ⌘ to record", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Set API Key...", action: #selector(setAPIKey), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Whisprr", action: #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private func updateUI() {
        DispatchQueue.main.async { [self] in
            guard let button = statusItem.button else { return }

            switch state {
            case .idle:
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Whisprr")
                button.contentTintColor = nil
                statusMenuItem.title = "Idle — Right ⌘ to record"

            case .recording:
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Recording")
                button.contentTintColor = .systemRed
                statusMenuItem.title = "Recording... Right ⌘ to stop"

            case .transcribing:
                button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Transcribing")
                button.contentTintColor = .systemOrange
                statusMenuItem.title = "Transcribing..."

            case .pasting:
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pasting")
                button.contentTintColor = .systemBlue
                statusMenuItem.title = "Pasting..."
            }
        }
    }

    // MARK: - Hotkey (Right Command)

    private func setupHotkey() {
        // Global monitor for when app is not focused
        NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleHotkeyEvent(event)
        }

        // Local monitor for when app is focused
        NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleHotkeyEvent(event)
            return event
        }
    }

    private func handleHotkeyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            // Any key pressed while Right Cmd is held = combo, not solo
            if rightCmdDown {
                otherKeysDuringRightCmd = true
            }
            return
        }

        // flagsChanged event
        let rightCmdKeyCode: UInt16 = 54

        if event.keyCode == rightCmdKeyCode {
            if event.modifierFlags.contains(.command) {
                // Right Cmd pressed down
                rightCmdDown = true
                otherKeysDuringRightCmd = false
            } else if rightCmdDown {
                // Right Cmd released
                rightCmdDown = false
                if !otherKeysDuringRightCmd {
                    // Solo press — toggle recording
                    DispatchQueue.main.async { [self] in
                        toggle()
                    }
                }
            }
        }
    }

    // MARK: - Core Logic

    private func toggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopAndTranscribe()
        default:
            break // Ignore during transcribing/pasting
        }
    }

    private func startRecording() {
        guard !apiKey.isEmpty else {
            showError("No API key set. Use the menu bar to set your Gemini API key.")
            return
        }

        AudioRecorder.requestPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if granted {
                    if self.audioRecorder.startRecording() {
                        self.state = .recording
                    } else {
                        self.showError("Failed to start recording.")
                    }
                } else {
                    self.showError("Microphone access denied. Grant access in System Settings > Privacy > Microphone.")
                }
            }
        }
    }

    private func stopAndTranscribe() {
        guard let audioURL = audioRecorder.stopRecording() else {
            state = .idle
            showError("No audio recorded.")
            return
        }

        state = .transcribing

        transcriptionService.transcribe(audioFileURL: audioURL, apiKey: apiKey) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Clean up temp file
                try? FileManager.default.removeItem(at: audioURL)

                switch result {
                case .success(let text):
                    self.pasteText(text)
                case .failure(let error):
                    self.state = .idle
                    if let txError = error as? TranscriptionError {
                        switch txError {
                        case .quotaExceeded:
                            self.showError("Gemini API quota exceeded.\n\nCheck your billing at ai.google.dev or wait for the quota to reset.")
                        case .apiError(let msg) where msg.lowercased().contains("api key"):
                            self.showError("Gemini API key error: \(msg)\n\nUse \"Set API Key...\" in the menu bar to re-enter your key.")
                        default:
                            self.showError("Transcription failed: \(txError.localizedDescription)")
                        }
                    } else {
                        self.showError("Transcription failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func pasteText(_ text: String) {
        state = .pasting

        TextPaster.paste(text: text) { [weak self] in
            self?.state = .idle
        }
    }

    // MARK: - UI Actions

    @objc private func setAPIKey() {
        let alert = NSAlert()
        alert.messageText = "Gemini API Key"
        alert.informativeText = "Enter your Google Gemini API key.\nGet one free at: ai.google.dev"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = apiKey
        input.placeholderString = "AIza..."
        alert.accessoryView = input

        // Bring app to front for the dialog
        NSApp.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            var cleanedKey = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            cleanedKey = cleanedKey.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint }.map { String($0) }.joined()
            apiKey = cleanedKey
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Whisprr"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
