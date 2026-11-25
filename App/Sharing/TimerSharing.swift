import CoreImage.CIFilterBuiltins
import Foundation
import SwiftUI
import TimerKit
import UniformTypeIdentifiers

extension UTType {
    /// A shared timer file, "Tabata.intervaltimer". Declared in project.yml.
    static let intervalTimer = UTType(exportedAs: "com.mrmallon.intervaltimer.timer", conformingTo: .json)
}

/// A timer as it travels between people: in a file or a QR-code link.
/// Contains only the timer itself, nothing about the sender.
struct SharedTimer: Codable, Equatable {
    /// Format version, so a future app can still read old files.
    var v = 1
    var name: String
    var color: String
    var definition: TimerDefinition

    init(name: String, color: ThemeColor, definition: TimerDefinition) {
        self.name = name
        self.color = color.rawValue
        self.definition = definition
    }

    var themeColor: ThemeColor { ThemeColor(rawValue: color) ?? .red }

    // MARK: - File

    func fileData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) -> SharedTimer? {
        guard let timer = try? JSONDecoder().decode(SharedTimer.self, from: data),
              timer.v <= 1,
              !timer.definition.segments().isEmpty else { return nil }
        return timer
    }

    // MARK: - Link (for QR codes)

    static let importHost = "import"

    /// `intervaltimer://import?t=<compressed timer>`, or nil when too long for a QR code.
    var link: URL? {
        guard let json = try? JSONEncoder().encode(self),
              let packed = try? (json as NSData).compressed(using: .zlib) as Data else { return nil }
        let token = packed.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard token.count <= 2000 else { return nil }
        var components = URLComponents()
        components.scheme = DeepLink.scheme
        components.host = Self.importHost
        components.queryItems = [URLQueryItem(name: "t", value: token)]
        return components.url
    }

    static func from(link url: URL) -> SharedTimer? {
        guard url.scheme?.lowercased() == DeepLink.scheme,
              url.host?.lowercased() == importHost,
              let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "t" })?.value else { return nil }
        var base64 = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let packed = Data(base64Encoded: base64),
              let json = try? (packed as NSData).decompressed(using: .zlib) as Data else { return nil }
        return decode(json)
    }

    /// Reads a file someone opened with the app (AirDrop, Messages, Files).
    static func from(fileURL url: URL) -> SharedTimer? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), data.count < 1_000_000 else { return nil }
        return decode(data)
    }
}

/// What the share sheet sends: a small `.intervaltimer` file named after the timer.
struct SharedTimerFile: Transferable {
    let timer: SharedTimer

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .intervalTimer) { item in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(Self.fileName(item.timer.name)).appendingPathExtension("intervaltimer")
            try item.timer.fileData().write(to: url)
            return SentTransferredFile(url)
        }
    }

    private static func fileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Timer" : String(cleaned.prefix(60))
    }
}

/// Share sheet for one timer: a QR code to scan, plus a button to send the file.
struct ShareTimerView: View {
    let timer: SharedTimer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let link = timer.link, let image = QRCode.image(for: link.absoluteString) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(16)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("QR code for this timer")
                            .accessibilityIdentifier("shareQRCode")
                        Text("Scan with the iPhone Camera to add this timer to Interval Timer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    ShareLink(item: SharedTimerFile(timer: timer), preview: SharePreview(timer.name)) {
                        Label("Send timer", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(timer.themeColor.color)
                    .accessibilityIdentifier("sendTimerButton")

                    Text("Sends a small file with this timer's intervals. Your history and settings stay on your iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .navigationTitle(timer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

enum QRCode {
    static func image(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
