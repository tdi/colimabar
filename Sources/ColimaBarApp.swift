import SwiftUI
import AppKit

@main
struct ColimaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var colimaManager: ColimaManager!
    private var statusObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        colimaManager = ColimaManager()

        setupStatusItem()
        setupMenu()

        // Observe status changes
        Task {
            for await _ in colimaManager.$status.values {
                updateStatusIcon()
                setupMenu()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let symbolName: String
        let accessibilityLabel: String

        switch colimaManager.status {
        case .running:
            symbolName = "shippingbox.fill"
            accessibilityLabel = "Colima Running"
        case .stopped:
            symbolName = "shippingbox"
            accessibilityLabel = "Colima Stopped"
        case .checking:
            symbolName = "shippingbox.and.arrow.backward"
            accessibilityLabel = "Checking Colima Status"
        case .starting, .stopping:
            symbolName = "shippingbox.and.arrow.backward.fill"
            accessibilityLabel = "Colima \(colimaManager.status.displayName)"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel) {
            image.isTemplate = true
            button.image = image
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        // Status item
        let statusMenuItem = NSMenuItem(title: "Status: \(colimaManager.status.displayName)", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Start/Stop items
        let startItem = NSMenuItem(title: "Start", action: #selector(startColima), keyEquivalent: "s")
        startItem.target = self
        startItem.isEnabled = colimaManager.status == .stopped
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopColima), keyEquivalent: "x")
        stopItem.target = self
        stopItem.isEnabled = colimaManager.status == .running
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh Status", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit ColimaBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func startColima() {
        colimaManager.start()
    }

    @objc private func stopColima() {
        colimaManager.stop()
    }

    @objc private func refreshStatus() {
        colimaManager.checkStatus()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
