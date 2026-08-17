import SwiftUI
import AppKit

enum ConnectionMode: String, CaseIterable, Identifiable {
    case usb = "USB"
    case network = "Wi‑Fi"

    var id: String { rawValue }
}

@MainActor
final class BooxController: ObservableObject {
    @Published var status = "Prêt"
    @Published var isRunning = false

    private var scrcpyProcess: Process?

    private func executable(named name: String) -> String? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func start(mode: ConnectionMode, address: String) {
        guard let adbPath = executable(named: "adb"),
              let scrcpyPath = executable(named: "scrcpy") else {
            status = "Installe scrcpy avec : brew install scrcpy"
            return
        }

        stopScrcpy(updateStatus: false)

        if mode == .usb {
            launchScrcpy(at: scrcpyPath, arguments: ["--select-usb", "--no-audio", "--max-fps", "15"])
            return
        }

        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]{1,5}$"#, options: .regularExpression) != nil else {
            status = "Adresse invalide — utilise la forme 192.168.1.138:5555"
            return
        }

        status = "Connexion à \(trimmed)…"
        let connect = Process()
        let output = Pipe()
        connect.executableURL = URL(fileURLWithPath: adbPath)
        connect.arguments = ["connect", trimmed]
        connect.standardOutput = output
        connect.standardError = output
        connect.terminationHandler = { [weak self] process in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            DispatchQueue.main.async {
                guard let self else { return }
                if process.terminationStatus == 0 && !message.localizedCaseInsensitiveContains("failed") {
                    self.launchScrcpy(at: scrcpyPath, arguments: ["--serial", trimmed, "--no-audio", "--max-fps", "15"])
                } else {
                    self.status = message.isEmpty ? "Connexion ADB impossible" : message
                }
            }
        }

        do {
            try connect.run()
        } catch {
            status = "Impossible de lancer adb : \(error.localizedDescription)"
        }
    }

    func stop() {
        stopScrcpy(updateStatus: true)
    }

    private func launchScrcpy(at path: String, arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.status = "Session terminée"
            }
        }

        do {
            try process.run()
            scrcpyProcess = process
            isRunning = true
            status = "BOOX connectée"
        } catch {
            status = "Impossible de lancer scrcpy : \(error.localizedDescription)"
        }
    }

    private func stopScrcpy(updateStatus: Bool) {
        if let process = scrcpyProcess, process.isRunning {
            process.terminate()
        }
        scrcpyProcess = nil
        isRunning = false
        if updateStatus { status = "Session arrêtée" }
    }
}

struct ContentView: View {
    @StateObject private var controller = BooxController()
    @AppStorage("connectionMode") private var storedMode = ConnectionMode.usb.rawValue
    @AppStorage("networkAddress") private var address = "192.168.1.138:5555"

    private var mode: Binding<ConnectionMode> {
        Binding(
            get: { ConnectionMode(rawValue: storedMode) ?? .usb },
            set: { storedMode = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.orange)

            VStack(spacing: 5) {
                Text("BOOX Remote")
                    .font(.title.bold())
                Text("Contrôle ta tablette depuis ton Mac avec scrcpy")
                    .foregroundStyle(.secondary)
            }

            Picker("Connexion", selection: mode) {
                ForEach(ConnectionMode.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)

            if mode.wrappedValue == .network {
                TextField("192.168.1.138:5555", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else {
                Label("Branche la tablette avec un câble USB‑C de données", systemImage: "cable.connector")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button {
                    controller.start(mode: mode.wrappedValue, address: address)
                } label: {
                    Label("Connecter", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button {
                    controller.stop()
                } label: {
                    Label("Arrêter", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!controller.isRunning)
            }
            .controlSize(.large)

            HStack(spacing: 8) {
                Circle()
                    .fill(controller.isRunning ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(controller.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(28)
        .frame(width: 440)
    }
}

@main
struct BooxRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
