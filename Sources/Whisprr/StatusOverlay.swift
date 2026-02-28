import AppKit

final class StatusOverlay {
    private var panel: NSPanel?

    func show(message: String, symbolName: String) {
        DispatchQueue.main.async { [self] in
            let panel = panel ?? makePanel()
            self.panel = panel

            // Update content
            if let effectView = panel.contentView?.subviews.first as? NSVisualEffectView {
                for subview in effectView.subviews {
                    if let imageView = subview as? NSImageView {
                        imageView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: message)?
                            .withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
                    } else if let label = subview as? NSTextField {
                        label.stringValue = message
                    }
                }
            }

            // Center on screen with mouse cursor
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main {
                let screenFrame = screen.visibleFrame
                let x = screenFrame.midX - panel.frame.width / 2
                let y = screenFrame.midY - panel.frame.height / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        DispatchQueue.main.async { [self] in
            guard let panel = panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                panel.orderOut(nil)
                self?.panel = nil
            })
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView(frame: panel.contentView!.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 16

        let icon = NSImageView(frame: .zero)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = .white

        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center

        effect.addSubview(icon)
        effect.addSubview(label)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            icon.topAnchor.constraint(equalTo: effect.topAnchor, constant: 14),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            label.centerXAnchor.constraint(equalTo: effect.centerXAnchor),
            label.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 4),
        ])

        panel.contentView!.addSubview(effect)
        return panel
    }
}
