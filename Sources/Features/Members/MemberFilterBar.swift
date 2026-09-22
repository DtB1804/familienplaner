import SwiftUI
import CoreData

/// Personen-Chips als primäre Filterachse.
/// Leere Auswahl bedeutet "alle anzeigen" – nicht "nichts anzeigen".
/// Das ist der Zustand, in dem die App die meiste Zeit steht.
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
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, Spacing.m)
                        .padding(.vertical, Spacing.s)
                }
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
        }
        .background(Palette.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5)
        }
    }

    private func chip(for member: CDMember) -> some View {
        let tint = Palette.color(member.colorToken ?? "person1")
        let isOn = selection.contains(member.objectID)

        return Button {
            withAnimation(.snappy(duration: 0.18)) { toggle(member) }
        } label: {
            HStack(spacing: Spacing.xs) {
                Circle().fill(tint).frame(width: 7, height: 7)
                Text(member.displayName ?? "?")
                    .font(.system(size: 13, weight: isOn ? .semibold : .regular))
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
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func toggle(_ member: CDMember) {
        if selection.contains(member.objectID) {
            selection.remove(member.objectID)
        } else {
            selection.insert(member.objectID)
        }
    }
}
