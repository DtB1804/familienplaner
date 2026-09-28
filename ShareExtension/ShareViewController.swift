import PDFKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

/// Teilen-Erweiterung: "Family Planner" im Teilen-Menü von Mail, WhatsApp, Fotos, Dateien.
/// Nimmt Bilder, PDFs (erste drei Seiten) und Text (z. B. WhatsApp-Nachrichten) an, legt sie im gemeinsamen Eingang ab und
/// meldet per Mitteilung, dass die Termine in der App geprüft werden können.
/// Kein Core Data, keine Terminanlage hier (Regel 4 und 15).
final class ShareViewController: UIViewController {

    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        Task { await model.process(items) }
    }
}

@MainActor
final class ShareModel: ObservableObject {

    enum State: Equatable { case working, saved(Int), failed(String) }

    @Published var state: State = .working

    private let maxPixels: CGFloat = 2600
    private let maxPdfPages = 3

    func process(_ items: [NSExtensionItem]) async {
        var saved = 0
        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier),
               let data = await load(provider, type: .pdf),
               let document = PDFDocument(data: data) {
                for index in 0..<min(document.pageCount, maxPdfPages) {
                    if let page = document.page(at: index), let jpeg = render(page), SharedInbox.save(jpeg) {
                        saved += 1
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let text = await loadText(provider),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      SharedInbox.saveText(String(text.prefix(5000))) {
                saved += 1
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = await load(provider, type: .image),
                      let image = UIImage(data: data),
                      let jpeg = scaled(image).jpegData(compressionQuality: 0.85),
                      SharedInbox.save(jpeg) {
                saved += 1
            }
        }
        if saved > 0 {
            state = .saved(saved)
            await notify(count: saved)
        } else {
            state = .failed("Nichts Passendes gefunden. Family Planner erkennt Termine aus Fotos, Screenshots, PDFs und Text.")
        }
    }

    private func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map { $0 as String })
            }
        }
    }

    private func load(_ provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// Große Fotos verkleinern: Die Erweiterung hat wenig Arbeitsspeicher, und für die
    /// Texterkennung reichen etwa 2.600 Pixel an der langen Seite.
    private func scaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        guard longest > maxPixels else { return image }
        let factor = maxPixels / longest
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private func render(_ page: PDFPage) -> Data? {
        let bounds = page.bounds(for: .mediaBox)
        let factor = min(maxPixels / max(bounds.width, bounds.height), 3)
        let image = page.thumbnail(of: CGSize(width: bounds.width * factor, height: bounds.height * factor), for: .mediaBox)
        return image.jpegData(compressionQuality: 0.85)
    }

    /// Mitteilung "zum Prüfen öffnen" (nur wenn Mitteilungen für die App erlaubt sind).
    private func notify(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Family Planner"
        content.body = count == 1
            ? "Erhalten. Antippen, um die erkannten Termine zu prüfen."
            : "\(count) Einträge erhalten. Antippen, um die erkannten Termine zu prüfen."
        content.userInfo = ["fp.inbox": true]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "fp.inbox.\(UUID().uuidString)", content: content, trigger: nil))
    }
}

struct ShareView: View {
    @ObservedObject var model: ShareModel
    let done: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                switch model.state {
                case .working:
                    ProgressView("Wird übernommen …")
                case .saved(let count):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 48)).foregroundStyle(.green)
                    Text(count == 1 ? "Erhalten" : "\(count) Einträge erhalten").font(.headline)
                    Text("Öffne Family Planner, um die erkannten Termine zu prüfen und zu übernehmen.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                case .failed(let reason):
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(.orange)
                    Text(reason).multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .navigationTitle("Family Planner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: done).disabled(model.state == .working)
                }
            }
        }
    }
}
