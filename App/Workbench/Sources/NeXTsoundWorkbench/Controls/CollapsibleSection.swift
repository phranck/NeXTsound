import SwiftUI

/// A titled, collapsible section with a hierarchical SF Symbol and a larger header, replacing
/// ad hoc `GroupBox` usage so every form section in the app shares the same shape and the same
/// persisted expand/collapse behavior.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                content()
                    .padding(.top, 12)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Persisted expand/collapse state for every `CollapsibleSection` in the driver form, keyed by a
/// stable per-section identifier so the layout preference survives across launches and applies
/// regardless of which driver is currently selected.
struct SectionExpansionState: DynamicProperty {
    @AppStorage("driverForm.section.identity.expanded") var identity = true
    @AppStorage("driverForm.section.electrical.expanded") var electrical = true
    @AppStorage("driverForm.section.thieleSmall.expanded") var thieleSmall = true
    @AppStorage("driverForm.section.mechanical.expanded") var mechanical = true
    @AppStorage("driverForm.section.mounting.expanded") var mounting = true
    @AppStorage("driverForm.section.power.expanded") var power = true

    var allExpanded: Bool {
        identity && electrical && thieleSmall && mechanical && mounting && power
    }

    var identityBinding: Binding<Bool> {
        $identity
    }

    var electricalBinding: Binding<Bool> {
        $electrical
    }

    var thieleSmallBinding: Binding<Bool> {
        $thieleSmall
    }

    var mechanicalBinding: Binding<Bool> {
        $mechanical
    }

    var mountingBinding: Binding<Bool> {
        $mounting
    }

    var powerBinding: Binding<Bool> {
        $power
    }

    /// Not `mutating`: each binding writes straight to its own `@AppStorage` key, so toggling
    /// every section works from a non-mutating button action without needing `self` as `@State`.
    func setAll(_ expanded: Bool) {
        identityBinding.wrappedValue = expanded
        electricalBinding.wrappedValue = expanded
        thieleSmallBinding.wrappedValue = expanded
        mechanicalBinding.wrappedValue = expanded
        mountingBinding.wrappedValue = expanded
        powerBinding.wrappedValue = expanded
    }
}
