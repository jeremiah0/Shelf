import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var library: Library
    @AppStorage("igdbClientID") private var igdbID = ""
    @AppStorage("igdbClientSecret") private var igdbSecret = ""
    @AppStorage("sgdbAPIKey") private var sgdbKey = ""
    @AppStorage("navigationStyle") private var navStyle: NavigationStyle = .sidebar

    let onFinish: () -> Void

    @State private var step = 0
    @State private var selectedPlatforms: Set<GamePlatform> = []
    @State private var importWizard: GamePlatform?

    private let steps = ["Welcome", "Getting started", "API Keys", "Layout", "Platform setup", "Let's game!"]
    private let platforms: [GamePlatform] = [.steam, .epic, .gog, .crossover]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)

            Group {
                switch step {
                case 0: welcomeStep
                case 1: gettingStartedStep
                case 2: apiKeysStep
                case 3: layoutStep
                case 4: platformSetupStep
                default: finishStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 48)

            Divider()
            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                Spacer()
                if step < steps.count - 1 {
                    Button(step == 4 ? "Skip setup" : "Skip") { step += 1 }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Let's game!") { onFinish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 20)
        }
        .frame(minWidth: 720, minHeight: 520)
        .sheet(item: $importWizard) { platform in
            if platform == .crossover {
                CrossOverWizard(onFinish: {})
                    .environmentObject(library)
            } else {
                StoreWizard(platform: platform)
                    .environmentObject(library)
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIcon.image)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Shelf!")
                .font(.largeTitle.bold())
            Text("Your games, together in one place.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var gettingStartedStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("Let's get you started")
                .font(.largeTitle.bold())
            Text("A couple of quick steps can help Shelf find your games and fill in details like descriptions and artwork.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
        }
    }

    private var apiKeysStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Keys")
                .font(.largeTitle.bold())
            Text("These optional keys unlock richer game details and artwork. You can add them now or later in Settings.")
                .foregroundStyle(.secondary)

            Form {
                Section("IGDB — descriptions, genres, ratings") {
                    TextField("Client ID", text: $igdbID)
                    SecureField("Client Secret", text: $igdbSecret)
                    Link("Get free credentials", destination: URL(string: "https://dev.twitch.tv/console/apps")!)
                    Text("Register an app with redirect URL http://localhost and category Application Integration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("SteamGridDB — artwork") {
                    SecureField("API Key", text: $sgdbKey)
                    Link("Get a SteamGridDB API key",
                         destination: URL(string: "https://www.steamgriddb.com/profile/preferences/api")!)
                }
                Section("Steam Store") {
                    Label("Ready to use — no API key needed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: 540, maxHeight: .infinity, alignment: .center)
    }

    private var layoutStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your layout")
                .font(.largeTitle.bold())
            Text("Pick how you'd like to navigate your library. You can change this any time in Settings.")
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                ForEach(NavigationStyle.allCases) { style in
                    let selected = navStyle == style
                    VStack(spacing: 8) {
                        LayoutPreview(style: style)
                            .allowsHitTesting(false)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3),
                                              lineWidth: selected ? 2.5 : 1))
                        Label(style.label, systemImage: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? Color.accentColor : .secondary)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                    .onTapGesture { navStyle = style }
                }
            }
        }
        .frame(maxWidth: 540, maxHeight: .infinity, alignment: .center)
    }

    private var platformSetupStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Platform setup")
                .font(.largeTitle.bold())
            Text("Which launchers do you use? Choose any, then open its setup wizard to add installed games.")
                .foregroundStyle(.secondary)

            ForEach(platforms) { platform in
                HStack(spacing: 14) {
                    Toggle(platform.label, isOn: selectionBinding(for: platform))
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button("Set up…") { importWizard = platform }
                        .disabled(!selectedPlatforms.contains(platform))
                }
                .padding(14)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            }

            Text("You can also import launchers or Mac games any time from the Import menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: 540, maxHeight: .infinity, alignment: .center)
    }

    private var finishStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Let's game!")
                .font(.largeTitle.bold())
            Text("Your Shelf is ready. You can import more games or update your API keys any time.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
        }
    }

    private func selectionBinding(for platform: GamePlatform) -> Binding<Bool> {
        Binding(
            get: { selectedPlatforms.contains(platform) },
            set: { isSelected in
                if isSelected {
                    selectedPlatforms.insert(platform)
                } else {
                    selectedPlatforms.remove(platform)
                }
            }
        )
    }
}
