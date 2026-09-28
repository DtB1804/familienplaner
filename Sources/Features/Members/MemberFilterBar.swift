import SwiftUI
import CoreData

/// Personen-Chips als primäre Filterachse.
/// Leere Auswahl bedeutet "alle anzeigen"; dann erscheinen alle Chips als eingeschaltet.
/// Antippen blendet eine Person aus bzw. wieder ein (UX-Prüfung B6). Die letzte sichtbare
/// Person lässt sich nicht ausblenden.
public struct MemberFilterBar: View {

    let members: [CDMember]
    @Binding var selection: Set<NSManagedObjectID>

    public init(members: [CDMember], selection: Binding<Set<NSManagedObjectID>>) {
        self.members = members
        self._selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s) {
                ForEach(members, id: \.objectID) { member in
                    chip(for: member)
                }
                if !selection.isEmpty {
                    Button("Alle") { withAnimation(.snappy(duration: 0.18)) { selection.removeAll() } }
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
        }
        // Rechts weich ausblenden: zeigt, dass weitere Personen folgen, statt hart abzuschneiden.
        .mask(
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Spacing.l)
            }
        )
    }

    /// Vorname reicht im Chip; der volle Name steht im Vorlesetext.
    private func chipName(_ member: CDMember) -> String {
        let name = member.displayName ?? "?"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private func chip(for member: CDMember) -> some View {
        let tint = Palette.color(member.colorToken ?? "person1")
        let isOn = selection.isEmpty || selection.contains(member.objectID)

        return Button {
            withAnimation(.snappy(duration: 0.18)) { toggle(member) }
        } label: {
            HStack(spacing: Spacing.xs) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(chipName(member))
                    .lineLimit(1)
                    .font(.footnote.weight(isOn ? .semibold : .regular))
            }
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(isOn ? tint.opacity(0.18) : Palette.surfaceSunken,
                        in: Capsule())
            .overlay {
                Capsule().stroke(isOn ? tint.opacity(0.5) : .clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(member.displayName ?? ""))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn ? "Blendet diese Person aus" : "Blendet diese Person ein")
    }

    private func toggle(_ member: CDMember) {
        let all = Set(members.map(\.objectID))
        var visible = selection.isEmpty ? all : selection
        if visible.contains(member.objectID) {
            guard visible.count > 1 else { return }   // mindestens eine Person bleibt sichtbar
            visible.remove(member.objectID)
        } else {
            visible.insert(member.objectID)
        }
        selection = visible == all ? [] : visible
    }
}
