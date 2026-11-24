import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var autoCleanEnabled = true
    var statusMenuItem: NSMenuItem!
    var spaceMenuItem: NSMenuItem!

    // Lista de procesos de Adobe a vigilar antes de borrar temporales activos
    let adobeApps = [
        "photoshop", "illustrator", "premiere", "after effects",
        "afterfx", "media encoder", "indesign", "audition", "lightroom"
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Adobe Cleaner")
        }

        setupMenu()
        startTimer()
        runCleanup(manual: false)
    }

    func setupMenu() {
        let menu = NSMenu()

        spaceMenuItem = NSMenuItem(title: "Calculando espacio...", action: nil, keyEquivalent: "")
        menu.addItem(spaceMenuItem)

        statusMenuItem = NSMenuItem(title: "Estado: Esperando", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        let cleanNowItem = NSMenuItem(title: "🧹 Limpiar caché de Adobe ahora", action: #selector(manualClean), keyEquivalent: "l")
        cleanNowItem.target = self
        menu.addItem(cleanNowItem)

        let toggleItem = NSMenuItem(title: "⏱️ Auto-limpieza cada 30 min", action: #selector(toggleAutoClean(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = .on
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Salir", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateFreeSpaceLabel()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            guard let self = self, self.autoCleanEnabled else { return }
            self.runCleanup(manual: false)
        }
    }

    @objc func toggleAutoClean(_ sender: NSMenuItem) {
        autoCleanEnabled.toggle()
        sender.state = autoCleanEnabled ? .on : .off
        statusMenuItem.title = autoCleanEnabled ? "Estado: Activo (cada 30 min)" : "Estado: Pausado"
    }

    @objc func manualClean() {
        runCleanup(manual: true)
    }

    func getRunningAdobeApp() -> String? {
        let apps = NSWorkspace.shared.runningApplications
        for app in apps {
            let name = (app.localizedName ?? "").lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()
            for target in adobeApps {
                if name.contains(target) || bundle.contains(target) {
                    return app.localizedName ?? "Adobe App"
                }
            }
        }
        return nil
    }

    func updateFreeSpaceLabel() {
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let freeSize = attrs[.systemFreeSize] as? Int64 {
            let gb = Double(freeSize) / 1_073_741_824.0
            spaceMenuItem.title = String(format: "💾 Espacio libre: %.1f GB", gb)
            statusItem.button?.title = String(format: " %.0fGB", gb)
        }
    }

    func runCleanup(manual: Bool) {
        let activeApp = getRunningAdobeApp()
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // 1. Limpieza ligera segura (se puede ejecutar aunque haya apps abiertas)
        let safePaths = [
            "\(home)/Library/Caches/Adobe",
            "\(home)/Library/Caches/com.adobe.Photoshop",
            "\(home)/Library/Caches/com.adobe.illustrator",
            "\(home)/Library/Caches/com.adobe.PremierePro",
            "\(home)/Library/Caches/com.adobe.AfterEffects",
            "\(home)/Library/Logs/Adobe",
            "\(home)/Library/Logs/CreativeCloud"
        ]
        for path in safePaths {
            clearDirectoryContents(at: path)
        }

        // 2. Limpieza profunda (Media Cache de video + Scratch Disks) solo si todo Adobe está cerrado
        if activeApp == nil {
            let deepCachePaths = [
                "\(home)/Library/Application Support/Adobe/Common/Media Cache",
                "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
                "\(home)/Library/Application Support/Adobe/Common/Peak Files",
                "\(home)/Library/Application Support/Adobe/Common/Team Projects Cache"
            ]
            for path in deepCachePaths {
                clearDirectoryContents(at: path)
            }

            // Temporales del sistema de Photoshop, Illustrator y After Effects
            let tempRoots = ["/tmp", "/private/var/folders"]
            for root in tempRoots {
                removeAdobeSystemTemps(in: root)
            }
        }

        updateFreeSpaceLabel()

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let hora = formatter.string(from: Date())

        if let appName = activeApp {
            statusMenuItem.title = "⚠️ \(hora) - \(appName) abierto (caché ligera)"
            if manual {
                showAlert(title: "\(appName) está abierto",
                          text: "Se limpiaron logs y cachés ligeras. Cierra todas las apps de Adobe para purgar Media Cache y Scratch Disks pesados.")
            }
        } else {
            statusMenuItem.title = "✅ \(hora) - Suite Adobe limpia"
            if manual {
                showAlert(title: "Limpieza completa de Adobe",
                          text: "Se eliminaron Media Cache, archivos temporales de Photoshop/Illustrator y cachés de Creative Cloud.")
            }
        }
    }

    func clearDirectoryContents(at path: String) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return }
        for item in items {
            try? fm.removeItem(atPath: "\(path)/\(item)")
        }
    }

    func removeAdobeSystemTemps(in directory: String) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return }
        while let file = enumerator.nextObject() as? String {
            if file.contains("Photoshop Temp") ||
               file.contains("PSTemp") ||
               file.contains("AfterEffects") ||
               file.hasPrefix("AI_") {
                try? fm.removeItem(atPath: "\(directory)/\(file)")
            }
        }
    }

    func showAlert(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()