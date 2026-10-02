import SwiftUI

/// Lets the user choose which sources are queried and which one wins for each field.
struct MetadataSourcesView: View {
    @State private var prefs = MetadataPreferences.load()

    var body: some View {
        Form {
            Section {
                ForEach(MetadataSource.allCases) { source in
                    Toggle(source.label, isOn: Binding(
                        get: { !prefs.disabled.contains(source) },
                        set: { on in
                            if on { prefs.disabled.remove(source) } else { prefs.disabled.insert(source) }
                        }
                    ))
                }
            } header: {
                Text("Sources")
            } footer: {
                Text("Disabled sources are never queried.")
            }
            Section {
                ForEach(MetadataField.allCases) { field in
                    Picker(field.label, selection: Binding(
                        get: { prefs.source(for: field) },
                        set: { prefs.setSource($0, for: field) }
                    )) {
                        Text("Automatic").tag(MetadataSource?.none)
                        ForEach(MetadataSource.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                }
            } header: {
                Text("Preferred source per field")
            } footer: {
                Text("If the preferred source has nothing for a field, the next available source fills it in.")
            }
            Section {
                Button("Reset to Automatic") { prefs = MetadataPreferences() }
            }
        }
        .formStyle(.grouped)
        .onChange(of: prefs) { _, new in new.save() }
    }
}

struct MetadataSourcesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            MetadataSourcesView()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 620)
    }
}
