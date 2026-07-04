import SwiftUI
import AppKit
import Combine
import ServiceManagement

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
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        colimaManager = ColimaManager()

        setupStatusItem()
        setupMenu()

        Publishers.MergeMany(
            colimaManager.$instances.map { _ in () }.eraseToAnyPublisher(),
            colimaManager.$loadState.map { _ in () }.eraseToAnyPublisher(),
            colimaManager.$actionError.map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] _ in
            self?.updateStatusIcon()
            self?.setupMenu()
        }
        .store(in: &cancellables)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }

        let hasRunning = colimaManager.hasRunningInstance
        let hasTransitioning = colimaManager.instances.contains { $0.status.isTransitioning }

        let symbolName: String
        let accessibilityLabel: String

        if hasTransitioning {
            symbolName = "shippingbox.and.arrow.backward.fill"
            accessibilityLabel = "Colima Transitioning"
        } else if hasRunning {
            symbolName = "shippingbox.fill"
            accessibilityLabel = "Colima Running"
        } else {
            symbolName = "shippingbox"
            accessibilityLabel = "Colima Stopped"
        }

        // Render the symbol at an explicit point size so it maps cleanly onto
        // the menu bar's pixel grid. Without a configuration the symbol is drawn
        // at its natural size and then downscaled by AppKit to fit the status
        // bar; on non-Retina (1x) external displays that downscale misaligns the
        // pixel grid and the icon looks blurry. See issue #2.
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
    }

    private func setupMenu() {
        let menu = NSMenu()

        if let actionError = colimaManager.actionError {
            let errorItem = NSMenuItem(title: "⚠ \(actionError)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
            menu.addItem(NSMenuItem.separator())
        }

        switch colimaManager.loadState {
        case .loading where colimaManager.instances.isEmpty:
            let loadingItem = NSMenuItem(title: "Loading…", action: nil, keyEquivalent: "")
            loadingItem.isEnabled = false
            menu.addItem(loadingItem)
        case .error(let message):
            let errorItem = NSMenuItem(title: message, action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        case .loaded, .loading:
            addInstanceItems(to: menu)
        }

        addBulkActions(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshStatus), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(refreshIntervalMenuItem())

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit ColimaBar", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// Bulk and lifecycle actions shown only once the instance list has loaded.
    private func addBulkActions(to menu: NSMenu) {
        guard case .error = colimaManager.loadState else {
            let anyStopped = colimaManager.instances.contains { $0.status.isStopped }
            let anyRunning = colimaManager.instances.contains { $0.status.isRunning }

            menu.addItem(NSMenuItem.separator())

            if colimaManager.instances.count > 1 {
                let startAllItem = NSMenuItem(title: "Start All", action: #selector(startAllInstances), keyEquivalent: "")
                startAllItem.target = self
                startAllItem.isEnabled = anyStopped
                menu.addItem(startAllItem)

                let stopAllItem = NSMenuItem(title: "Stop All", action: #selector(stopAllInstances), keyEquivalent: "")
                stopAllItem.target = self
                stopAllItem.isEnabled = anyRunning
                menu.addItem(stopAllItem)
            }

            let newItem = NSMenuItem(title: "New Instance…", action: #selector(newInstance), keyEquivalent: "n")
            newItem.target = self
            menu.addItem(newItem)
            return
        }
    }

    private func refreshIntervalMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let current = colimaManager.refreshInterval
        for seconds in [5.0, 10.0, 30.0, 60.0] {
            let item = NSMenuItem(title: "\(Int(seconds)) seconds", action: #selector(setInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            item.state = seconds == current ? .on : .off
            submenu.addItem(item)
        }
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        intervalItem.submenu = submenu
        return intervalItem
    }

    private var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func addInstanceItems(to menu: NSMenu) {
        if colimaManager.instances.isEmpty {
            let noInstancesItem = NSMenuItem(title: "No instances found", action: nil, keyEquivalent: "")
            noInstancesItem.isEnabled = false
            menu.addItem(noInstancesItem)
        } else {
            // Add each instance
            for instance in colimaManager.instances {
                let instanceMenu = NSMenu()
                instanceMenu.autoenablesItems = false

                // Info items
                let statusInfo = NSMenuItem(title: "Status: \(instance.status.rawValue)", action: nil, keyEquivalent: "")
                statusInfo.isEnabled = false
                instanceMenu.addItem(statusInfo)

                let archInfo = NSMenuItem(title: "Arch: \(instance.arch)", action: nil, keyEquivalent: "")
                archInfo.isEnabled = false
                instanceMenu.addItem(archInfo)

                let cpuInfo = NSMenuItem(title: "CPUs: \(instance.cpus)", action: nil, keyEquivalent: "")
                cpuInfo.isEnabled = false
                instanceMenu.addItem(cpuInfo)

                let memInfo = NSMenuItem(title: "Memory: \(instance.memoryFormatted)", action: nil, keyEquivalent: "")
                memInfo.isEnabled = false
                instanceMenu.addItem(memInfo)

                let diskInfo = NSMenuItem(title: "Disk: \(instance.diskFormatted)", action: nil, keyEquivalent: "")
                diskInfo.isEnabled = false
                instanceMenu.addItem(diskInfo)

                instanceMenu.addItem(NSMenuItem.separator())

                // Start/Stop actions
                if instance.status.isStopped {
                    let startItem = NSMenuItem(title: "Start", action: #selector(startInstance(_:)), keyEquivalent: "")
                    startItem.target = self
                    startItem.representedObject = instance.name
                    instanceMenu.addItem(startItem)
                } else if instance.status.isRunning {
                    let stopItem = NSMenuItem(title: "Stop", action: #selector(stopInstance(_:)), keyEquivalent: "")
                    stopItem.target = self
                    stopItem.representedObject = instance.name
                    instanceMenu.addItem(stopItem)

                    let restartItem = NSMenuItem(title: "Restart", action: #selector(restartInstance(_:)), keyEquivalent: "")
                    restartItem.target = self
                    restartItem.representedObject = instance.name
                    instanceMenu.addItem(restartItem)
                } else {
                    let transitionItem = NSMenuItem(title: instance.status.rawValue, action: nil, keyEquivalent: "")
                    transitionItem.isEnabled = false
                    instanceMenu.addItem(transitionItem)
                }

                instanceMenu.addItem(NSMenuItem.separator())
                let deleteItem = NSMenuItem(title: "Delete…", action: #selector(deleteInstance(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = instance.name
                deleteItem.isEnabled = !instance.status.isTransitioning
                instanceMenu.addItem(deleteItem)

                // Instance header with submenu
                let statusIcon = instance.status.isRunning ? "●" : "○"
                let instanceItem = NSMenuItem(title: "\(statusIcon) \(instance.name)", action: nil, keyEquivalent: "")
                instanceItem.submenu = instanceMenu
                menu.addItem(instanceItem)
            }
        }
    }

    @objc private func startInstance(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        colimaManager.start(profile: profile)
    }

    @objc private func stopInstance(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        colimaManager.stop(profile: profile)
    }

    @objc private func restartInstance(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }
        colimaManager.restart(profile: profile)
    }

    @objc private func deleteInstance(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? String else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Delete “\(profile)”?"
        alert.informativeText = "This permanently deletes the instance and all its data. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            colimaManager.delete(profile: profile)
        }
    }

    @objc private func startAllInstances() {
        colimaManager.startAll()
    }

    @objc private func stopAllInstances() {
        colimaManager.stopAll()
    }

    @objc private func newInstance() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "New Colima Instance"
        alert.informativeText = "Configure the instance to create."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "name"
        let cpuField = NSTextField(string: "2")
        let memField = NSTextField(string: "4")
        let diskField = NSTextField(string: "60")

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Name:"), nameField],
            [NSTextField(labelWithString: "CPUs:"), cpuField],
            [NSTextField(labelWithString: "Memory (GiB):"), memField],
            [NSTextField(labelWithString: "Disk (GiB):"), diskField]
        ])
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.column(at: 1).width = 160
        grid.frame = NSRect(x: 0, y: 0, width: 260, height: 120)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        colimaManager.create(
            name: name,
            cpus: Int(cpuField.stringValue) ?? 2,
            memoryGiB: Int(memField.stringValue) ?? 4,
            diskGiB: Int(diskField.stringValue) ?? 60
        )
    }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        colimaManager.setRefreshInterval(seconds)
        setupMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Could not update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        setupMenu()
    }

    @objc private func refreshStatus() {
        colimaManager.refreshInstances()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
