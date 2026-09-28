import SwiftUI
import CoreData
import UIKit

/// Was ausgewertet werden soll: ein Foto oder ein Text (geteilt oder eingefügt).
enum ImportSource {
    case image(Data)
    case text(String)
}

/// Liest ein Foto oder einen Text ein und zeigt danach die Vorschläge zur Prüfung.
struct PhotoImportSheet: View {

    let source: ImportSource
    let household: CDHousehold
    let me: CDMember

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CDSuggestionDraft?
    @State private var failure: String?
    @State private var foundNothing = false

    var body: some View {
        NavigationStack {
            Group {
                if let draft {
                    SuggestionReviewList(draft: draft, me: me)
                } else if foundNothing {
                    ContentUnavailableView("Keine Termine erkannt",
                                           systemImage: "doc.text.magnifyingglass",
                                           description: Text(isText
                                                ? "Im Text wurde kein Datum gefunden. Erkannt werden z. B. „14.10.“, „14. Oktober“ oder „Dienstag 19 Uhr“."
                                                : "Auf dem Foto wurde kein Datum gefunden. Tipp: Den Text möglichst gerade und formatfüllend fotografieren."))
                } else if let failure {
                    ContentUnavailableView(isText ? "Text konnte nicht gelesen werden" : "Foto konnte nicht gelesen werden",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(failure))
                } else {
                    VStack(spacing: Spacing.m) {
                        ProgressView()
                        Text(SuggestionExtractor.modelIsAvailable
                             ? "Text wird gelesen und mit Apple Intelligence ausgewertet …"
                             : "Text wird gelesen und nach Daten durchsucht …")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .navigationTitle(isText ? "Termine aus Text" : "Termine aus Foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task { await run() }
        }
    }

    private var isText: Bool {
        if case .text = source { return true }
        return false
    }

    private func run() async {
        guard draft == nil, failure == nil, !foundNothing else { return }
        do {
            switch source {
            case .image(let data):
                guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                    failure = "Das Bildformat wird nicht unterstützt."
                    return
                }
                let result = try await SuggestionExtractor.extract(from: cgImage)
                if result.suggestions.isEmpty { foundNothing = true; return }
                draft = SuggestionService.saveDraft(image: image, result: result,
                                                    household: household, author: me, in: context)
            case .text(let text):
                let result = try await SuggestionExtractor.extract(text: text)
                if result.suggestions.isEmpty { foundNothing = true; return }
                draft = SuggestionService.saveDraft(text: text, result: result,
                                                    household: household, author: me, in: context)
            }
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Offene Vorschläge aller Fotos (Einstieg über "+ → Vorschläge").
struct PendingSuggestionsScreen: View {

    let me: CDMember

    @Environment(\.dismiss) private var dismiss
    @FetchRequest(fetchRequest: SuggestionService.pendingRequest())
    private var drafts: FetchedResults<CDSuggestionDraft>

    var body: some View {
        NavigationStack {
            List {
                ForEach(drafts, id: \.objectID) { draft in
                    NavigationLink {
                        SuggestionReviewList(draft: draft, me: me)
                    } label: {
                        let open = SuggestionService.suggestions(of: draft).filter { $0.decision == nil }.count
                        VStack(alignment: .leading) {
                            Text("\(open) offene Vorschläge")
                            Text(draft.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if drafts.isEmpty {
                    ContentUnavailableView("Keine offenen Vorschläge", systemImage: "tray")
                }
            }
            .navigationTitle("Vorschläge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

/// Vorschläge eines Fotos prüfen: jeden einzeln übernehmen oder verwerfen.
struct SuggestionReviewList: View {

    @ObservedObject var draft: CDSuggestionDraft
    let me: CDMember

    @Environment(\.managedObjectContext) private var context
    @FetchRequest(fetchRequest: HouseholdService.activeMembersRequest())
    private var members: FetchedResults<CDMember>

    @State private var items: [SuggestedEvent] = []
    @State private var subjects: [UUID: Set<NSManagedObjectID>] = [:]
    @State private var showPhoto = false

    private var isAdult: Bool { me.role == .adult }

    var body: some View {
        List {
            if let data = draft.sourceAsset, let image = UIImage(data: data) {
                Section {
                    Button { showPhoto = true } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Vorschläge prüfen: Datum, Uhrzeit und Personen können falsch erkannt sein. Nichts wird ohne deine Bestätigung eingetragen.")
                }
            }

            if draft.sourceAsset == nil, let text = draft.sourceTextExcerpt, !text.isEmpty {
                Section {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(12)
                        .textSelection(.enabled)
                } header: {
                    Text("Geteilter Text")
                } footer: {
                    Text("Vorschläge prüfen: Datum, Uhrzeit und Personen können falsch erkannt sein. Nichts wird ohne deine Bestätigung eingetragen.")
                }
            }

            ForEach($items) { $item in
                Section {
                    suggestionCard($item)
                }
            }
        }
        .navigationTitle("Vorschläge prüfen")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPhoto) {
            if let data = draft.sourceAsset, let image = UIImage(data: data) {
                ScrollView([.vertical, .horizontal]) {
                    Image(uiImage: image)
                }
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private func suggestionCard(_ item: Binding<SuggestedEvent>) -> some View {
        let decided = item.wrappedValue.decision
        if let decided {
            Label(decided == .accepted ? "Eingetragen: \(item.wrappedValue.title)"
                                       : "Verworfen: \(item.wrappedValue.title)",
                  systemImage: decided == .accepted ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(.secondary)
        } else {
            LabeledContent("Titel") {
                TextField("Titel", text: item.title).multilineTextAlignment(.trailing)
            }
            if item.wrappedValue.isAllDay == true {
                allDayPickers(item)
            } else {
                DatePicker("Beginn", selection: item.start)
                    .onChange(of: item.wrappedValue.start) { old, new in
                        // Dauer beibehalten, mindestens 30 Minuten.
                        let length = max(item.wrappedValue.end.timeIntervalSince(old), EventService.defaultDuration)
                        item.wrappedValue.end = new.addingTimeInterval(length)
                        item.wrappedValue.timeIsGuessed = false
                    }
                DatePicker("Ende", selection: item.end, in: item.wrappedValue.start...)
            }
            if item.wrappedValue.timeIsGuessed {
                Label("Keine Uhrzeit erkannt – bitte prüfen", systemImage: "clock.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            if let location = item.wrappedValue.location {
                LabeledContent("Ort", value: location)
            }
            DisclosureGroup("Für wen: \(subjectNames(for: item.wrappedValue))") {
                ForEach(members, id: \.objectID) { member in
                    Button {
                        toggle(member, for: item.wrappedValue.id)
                    } label: {
                        HStack {
                            Text(member.displayName ?? "")
                            Spacer()
                            if subjects[item.wrappedValue.id, default: []].contains(member.objectID) {
                                Image(systemName: "checkmark").foregroundStyle(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if isAdult {
                HStack {
                    Button("Verwerfen", role: .destructive) { reject(item.wrappedValue) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Eintragen") { accept(item.wrappedValue) }
                        .buttonStyle(.borderedProminent)
                        .disabled(subjects[item.wrappedValue.id, default: []].isEmpty
                                  || item.wrappedValue.title.trimmed.isEmpty)
                }
            }
        }
    }

    /// Ganztägig (z. B. Klassenfahrt): nur Tage, Ende einschließlich angezeigt.
    @ViewBuilder
    private func allDayPickers(_ item: Binding<SuggestedEvent>) -> some View {
        let calendar = Calendar.current
        LabeledContent("Ganztägig", value: "ja")
        DatePicker("Von", selection: Binding(
            get: { item.wrappedValue.start },
            set: { new in
                let days = calendar.dateComponents([.day], from: item.wrappedValue.start, to: item.wrappedValue.end).day ?? 1
                let start = calendar.startOfDay(for: new)
                item.wrappedValue.start = start
                item.wrappedValue.end = calendar.date(byAdding: .day, value: max(days, 1), to: start) ?? start
            }), displayedComponents: .date)
        DatePicker("Bis", selection: Binding(
            get: { calendar.date(byAdding: .day, value: -1, to: item.wrappedValue.end) ?? item.wrappedValue.end },
            set: { new in
                item.wrappedValue.end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: new))
                    ?? item.wrappedValue.end
            }), in: item.wrappedValue.start..., displayedComponents: .date)
    }

    private func load() {
        items = SuggestionService.suggestions(of: draft)
        for item in items where subjects[item.id] == nil {
            subjects[item.id] = [me.objectID]
        }
    }

    private func subjectNames(for item: SuggestedEvent) -> String {
        let ids = subjects[item.id, default: []]
        let names = members.filter { ids.contains($0.objectID) }.compactMap(\.shortName)
        return names.isEmpty ? "niemand" : names.joined(separator: ", ")
    }

    private func toggle(_ member: CDMember, for id: UUID) {
        var set = subjects[id, default: []]
        if set.contains(member.objectID) { set.remove(member.objectID) } else { set.insert(member.objectID) }
        subjects[id] = set
    }

    private func accept(_ item: SuggestedEvent) {
        let ids = subjects[item.id, default: []]
        let chosen = members.filter { ids.contains($0.objectID) }
        SuggestionService.accept(item, subjects: Array(chosen), in: draft, by: me, context: context)
        load()
    }

    private func reject(_ item: SuggestedEvent) {
        SuggestionService.reject(item, in: draft, by: me, context: context)
        load()
    }
}
