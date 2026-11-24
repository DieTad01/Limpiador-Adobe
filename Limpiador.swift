import Cocoa

// MARK: - Rutas a limpiar

struct TempRoot {
    let url: URL
    let maxDepth: Int
}

struct CleanupPaths {
    /// Registros (logs). Se pueden borrar aunque haya apps de Adobe abiertas.
    let logs: [String]
    /// Cachés normales. Solo con todas las apps de Adobe cerradas.
    let caches: [String]
    /// Media Cache de video. Solo con todas las apps de Adobe cerradas.
    let deep: [String]
    /// Carpetas temporales donde se buscan archivos temporales de Adobe.
    let tempRoots: [TempRoot]

    static func current() -> CleanupPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Carpeta temporal del usuario: /var/folders/xx/yyyy/T/ y su hermana C/
        let userTemp = URL(fileURLWithPath: NSTemporaryDirectory())
        let userCache = userTemp.deletingLastPathComponent().appendingPathComponent("C")

        return CleanupPaths(
            logs: [
                "\(home)/Library/Logs/Adobe",
                "\(home)/Library/Logs/CreativeCloud"
            ],
            caches: [
                "\(home)/Library/Caches/Adobe",
                "\(home)/Library/Caches/com.adobe.Photoshop",
                "\(home)/Library/Caches/com.adobe.illustrator",
                "\(home)/Library/Caches/com.adobe.PremierePro",
                "\(home)/Library/Caches/com.adobe.AfterEffects"
            ],
            // "Team Projects Cache" NO se toca: puede tener cambios sin sincronizar.
            deep: [
                "\(home)/Library/Application Support/Adobe/Common/Media Cache",
                "\(home)/Library/Application Support/Adobe/Common/Media Cache Files",
                "\(home)/Library/Application Support/Adobe/Common/Peak Files"
            ],
            tempRoots: [
                TempRoot(url: userTemp, maxDepth: 3),
                TempRoot(url: userCache, maxDepth: 2),
                TempRoot(url: URL(fileURLWithPath: "/private/tmp"), maxDepth: 1)
            ]
        )
    }
}

// MARK: - Borrado de archivos (corre en segundo plano, no toca la interfaz)

enum Cleaner {
    static func clearDirectoryContents(_ path: String) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return }
        for item in items {
            try? fm.removeItem(atPath: (path as NSString).appendingPathComponent(item))
        }
    }

    static func isAdobeTemp(_ name: String) -> Bool {
        return name.hasPrefix("Photoshop Temp")
            || name.hasPrefix("PSTemp")
            || name.hasPrefix("AfterEffects")
            || name.hasPrefix("com.adobe.AfterEffects")
    }

    /// Busca temporales de Adobe sin bajar más de `maxDepth` niveles,
    /// para no recorrer todo el disco ni congelar la Mac.
    static func removeAdobeTemps(in root: TempRoot) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root.url,
                                             includingPropertiesForKeys: nil,
                                             options: [],
                                             errorHandler: { _, _ in true }) else { return }
        while let url = enumerator.nextObject() as? URL {
            if isAdobeTemp(url.lastPathComponent) {
                try? fm.removeItem(at: url)
                enumerator.skipDescendants()
            } else if enumerator.level >= root.maxDepth {
                enumerator.skipDescendants()
            }
        }
    }
}

enum CleanupResult {
    case complete
    case onlyLogs(String)   // había una app de Adobe abierta
    case stopped(String)    // se abrió una app de Adobe a media limpieza
}

// MARK: - App de barra de menú

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var autoCleanEnabled = true
    var isCleaning = false
    var statusMenuItem: NSMenuItem!
    var spaceMenuItem: NSMenuItem!
    var cleanNowItem: NSMenuItem!

    let workQueue = DispatchQueue(label: "com.agencia.Limpiador.limpieza", qos: .utility)

    /// Apps de Adobe que, si están abiertas, bloquean la limpieza.
    /// Además de esta lista, cualquier app de Adobe con ventana (en el Dock) también la bloquea.
    let adobeApps = [
        "photoshop", "illustrator", "premiere", "after effects", "afterfx",
        "media encoder", "indesign", "incopy", "audition", "lightroom",
        "bridge", "animate", "character animator", "acrobat", "dimension",
        "substance", "dreamweaver", "fresco"
    ]

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "Limpiador Adobe")
            button.imagePosition = .imageLeft
        }

        setupMenu()
        startTimer()
        runCleanup(manual: false)
    }

    // MARK: Menú

    func setupMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        spaceMenuItem = NSMenuItem(title: "Calculando espacio...", action: nil, keyEquivalent: "")
        spaceMenuItem.isEnabled = false
        menu.addItem(spaceMenuItem)

        statusMenuItem = NSMenuItem(title: "Estado: Esperando", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        cleanNowItem = NSMenuItem(title: "🧹 Limpiar caché de Adobe ahora", action: #selector(manualClean), keyEquivalent: "l")
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
        timer = Timer.scheduledTimer(timeInterval: 1800, target: self,
                                     selector: #selector(timerFired), userInfo: nil, repeats: true)
    }

    @objc func timerFired() {
        updateFreeSpaceLabel()
        if autoCleanEnabled {
            runCleanup(manual: false)
        }
    }

    @objc func toggleAutoClean(_ sender: NSMenuItem) {
        autoCleanEnabled.toggle()
        sender.state = autoCleanEnabled ? .on : .off
        if !isCleaning {
            statusMenuItem.title = autoCleanEnabled ? "Estado: Activo (cada 30 min)" : "Estado: Pausado"
        }
    }

    @objc func manualClean() {
        runCleanup(manual: true)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Detección de Adobe

    func getRunningAdobeApp() -> String? {
        for app in NSWorkspace.shared.runningApplications {
            if app == NSRunningApplication.current { continue }

            let name = (app.localizedName ?? "").lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()

            let isAdobe = bundle.hasPrefix("com.adobe.") || name.contains("adobe")
            guard isAdobe else { continue }

            // Creative Cloud siempre está abierto y no usa estas cachés; no debe bloquear.
            if bundle.hasPrefix("com.adobe.acc") || name.contains("creative cloud") { continue }

            let hasWindow = app.activationPolicy == .regular
            let isKnownApp = adobeApps.contains { name.contains($0) || bundle.contains($0) }
            if hasWindow || isKnownApp {
                return app.localizedName ?? "Una app de Adobe"
            }
        }
        return nil
    }

    // MARK: Limpieza

    func runCleanup(manual: Bool) {
        if isCleaning {
            if manual {
                showAlert(title: "Ya hay una limpieza en curso",
                          text: "Espera a que termine y vuelve a intentarlo.")
            }
            return
        }

        let openApp = getRunningAdobeApp()

        // Auto-limpieza: si hay algo de Adobe abierto, no se toca absolutamente nada.
        if let appName = openApp, !manual {
            statusMenuItem.title = "⏸️ \(currentTime()) - \(appName) abierto, no se limpió"
            updateFreeSpaceLabel()
            return
        }

        setCleaning(true)
        let paths = CleanupPaths.current()

        if let appName = openApp {
            // Limpieza manual con Adobe abierto: solo registros (logs).
            workQueue.async {
                paths.logs.forEach(Cleaner.clearDirectoryContents)
                DispatchQueue.main.async {
                    self.finishCleanup(manual: manual, result: .onlyLogs(appName))
                }
            }
            return
        }

        // Paso 1: logs y cachés normales.
        workQueue.async {
            (paths.logs + paths.caches).forEach(Cleaner.clearDirectoryContents)
            DispatchQueue.main.async {
                self.runDeepCleanup(manual: manual, paths: paths)
            }
        }
    }

    /// Paso 2: Media Cache y temporales. Se vuelve a revisar que Adobe siga cerrado.
    func runDeepCleanup(manual: Bool, paths: CleanupPaths) {
        if let appName = getRunningAdobeApp() {
            finishCleanup(manual: manual, result: .stopped(appName))
            return
        }

        workQueue.async {
            paths.deep.forEach(Cleaner.clearDirectoryContents)
            paths.tempRoots.forEach(Cleaner.removeAdobeTemps)
            DispatchQueue.main.async {
                self.finishCleanup(manual: manual, result: .complete)
            }
        }
    }

    func setCleaning(_ cleaning: Bool) {
        isCleaning = cleaning
        cleanNowItem.isEnabled = !cleaning
        if cleaning {
            statusMenuItem.title = "🧹 Limpiando..."
        }
    }

    func finishCleanup(manual: Bool, result: CleanupResult) {
        setCleaning(false)
        updateFreeSpaceLabel()
        let time = currentTime()

        switch result {
        case .complete:
            statusMenuItem.title = "✅ \(time) - Caché de Adobe limpia"
            if manual {
                showAlert(title: "Limpieza completa de Adobe",
                          text: "Se borraron Media Cache, cachés y temporales de Adobe.\n\(freeSpaceText())")
            }
        case .onlyLogs(let appName):
            statusMenuItem.title = "⚠️ \(time) - \(appName) abierto (solo logs)"
            if manual {
                showAlert(title: "\(appName) está abierto",
                          text: "Para no afectar tu trabajo solo se borraron los registros (logs). Cierra todas las apps de Adobe y vuelve a limpiar para borrar cachés y Media Cache.")
            }
        case .stopped(let appName):
            statusMenuItem.title = "⚠️ \(time) - Se detuvo: se abrió \(appName)"
            if manual {
                showAlert(title: "Limpieza detenida",
                          text: "Se abrió \(appName), así que no se borró Media Cache ni temporales. Ciérralo y vuelve a limpiar.")
            }
        }
    }

    // MARK: Espacio libre

    func freeSpaceGB() -> Double? {
        let root = URL(fileURLWithPath: "/")
        if let values = try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage, bytes > 0 {
            return Double(bytes) / 1_000_000_000
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
           let bytes = attrs[.systemFreeSize] as? Int64 {
            return Double(bytes) / 1_000_000_000
        }
        return nil
    }

    func freeSpaceText() -> String {
        guard let gb = freeSpaceGB() else { return "" }
        return String(format: "Espacio libre ahora: %.1f GB", gb)
    }

    func updateFreeSpaceLabel() {
        guard let gb = freeSpaceGB() else { return }
        spaceMenuItem.title = String(format: "💾 Espacio libre: %.1f GB", gb)
        statusItem.button?.title = String(format: " %.0fGB", gb)
    }

    // MARK: Utilidades

    func currentTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }

    func showAlert(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.runModal()
    }
}
