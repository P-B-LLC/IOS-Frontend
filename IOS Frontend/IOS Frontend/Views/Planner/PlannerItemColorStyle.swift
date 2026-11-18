import SwiftUI

extension PlannerItemColor {
    var tint: Color {
        Color("Calendar" + rawValue.prefix(1).uppercased() + rawValue.dropFirst())
    }
}

/// Named choices plus a checkmark make selection distinguishable without color.
struct PlannerColorPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Binding var selection: PlannerItemColor?
    let title: String
    let fallback: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title).font(.community(.headline))
                        .foregroundStyle(scheme == .dark ? RepbasePalette.ink : .white)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(selection?.tint ?? fallback, in: RoundedRectangle(cornerRadius: 8))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))], spacing: 12) {
                        ForEach(PlannerItemColor.allCases) { color in
                            Button { selection = color } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: selection == color ? "checkmark.circle.fill" : "circle.fill")
                                        .font(.community(.title))
                                        .foregroundStyle(color.tint)
                                    Text(color.title).font(.community(.footnote))
                                        .foregroundStyle(RytivoSunriseDesign.ink)
                                }
                                .frame(maxWidth: .infinity, minHeight: 68)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(selection == color ? color.tint : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(RepbaseTactilePressStyle())
                            .accessibilityAddTraits(selection == color ? .isSelected : [])
                        }
                    }
                    Button { selection = nil } label: {
                        Label("Use default color", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                }.padding(24)
            }
            .navigationTitle("Choose a color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .tint(RepbaseTactileDesign.accentText)
            .background(Color(.systemBackground))
        }
        .presentationDetents([.medium, .large])
    }
}
