// Lanciatore Mac di Secret Santa: avvia il programma che serve la pagina, mostra l'icona nel Dock
// finché è in esecuzione, riapre la pagina con un clic sull'icona e chiude tutto con "Esci".
import AppKit

final class Lanciatore: NSObject, NSApplicationDelegate {
    private var server: Process?
    private var url: URL?
    private var bufferUscita = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = creaMenu()
        avviaServer()
    }

    private func creaMenu() -> NSMenu {
        let barra = NSMenu()
        let voce = NSMenuItem()
        barra.addItem(voce)
        let menu = NSMenu(title: "Secret Santa")
        menu.addItem(withTitle: "Apri Secret Santa nel browser", action: #selector(apri), keyEquivalent: "o").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Esci da Secret Santa", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        voce.submenu = menu
        return barra
    }

    private func avviaServer() {
        guard let eseguibile = Bundle.main.url(forAuxiliaryExecutable: "secret-santa-server") else {
            errore("Manca il programma secret-santa-server dentro l'app.")
            return
        }
        let p = Process()
        p.executableURL = eseguibile
        let tubo = Pipe()
        p.standardOutput = tubo
        tubo.fileHandleForReading.readabilityHandler = { [weak self] h in
            let dati = h.availableData
            guard !dati.isEmpty, let testo = String(data: dati, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.leggi(testo) }
        }
        p.terminationHandler = { _ in
            // il programma si è chiuso (pagina chiusa o pulsante "Chiudi"): chiudo anche l'app
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        do {
            try p.run()
            server = p
        } catch {
            errore("Non riesco ad avviare Secret Santa: \(error.localizedDescription)")
        }
    }

    private func leggi(_ testo: String) {
        bufferUscita += testo
        while let a = bufferUscita.firstIndex(of: "\n") {
            let riga = String(bufferUscita[..<a])
            bufferUscita.removeSubrange(...a)
            if riga.hasPrefix("URL=") { url = URL(string: String(riga.dropFirst(4))) }
        }
    }

    @objc func apri() {
        if let url { NSWorkspace.shared.open(url) }
    }

    // clic sull'icona nel Dock quando l'app è già aperta
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        apri()
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Apri nel browser", action: #selector(apri), keyEquivalent: "").target = self
        return m
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let server, server.isRunning else { return }
        server.terminationHandler = nil
        server.terminate() // SIGTERM: il programma chiude il server in modo ordinato
        let limite = Date().addingTimeInterval(3)
        while server.isRunning && Date() < limite { usleep(50_000) }
    }

    private func errore(_ msg: String) {
        let a = NSAlert()
        a.messageText = "Secret Santa"
        a.informativeText = msg
        a.alertStyle = .critical
        a.runModal()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegato = Lanciatore()
app.delegate = delegato
app.setActivationPolicy(.regular)
app.run()
