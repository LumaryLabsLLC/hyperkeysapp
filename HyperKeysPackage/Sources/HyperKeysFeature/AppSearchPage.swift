import AppSwitcher
import EventEngine
import KeyBindings
import KeyboardUI
import Shared
import SwiftUI

/// "Search & Switch": settings for App Search and the App Switcher.
struct AppSearchPage: View {
    @Bindable var bindingStore: BindingStore

    @State private var provider = InstalledAppProvider.shared
    @AppStorage(Preferences.switcherStaysOpen) private var switcherStaysOpen = false
    private var searchModel: AppSearchModel { AppSearchController.shared.model }

    var body: some View {
        PageScroll {
            PageHeader(
                pane: .appSearch,
                subtitle: "Open any app, jump between open ones, paste an emoji, or quit a stuck process — from anywhere."
            )

            featureCard(
                action: .appSearch,
                detail: "Type a few letters of an app's name and press Return to open it.",
                tryIt: { AppSearchController.shared.show() }
            )

            featureCard(
                action: .appSwitcher,
                detail: switcherStaysOpen
                    ? "Opens a grid of your apps and windows. Move with h j k l or the arrows, Return to switch, / to filter."
                    : "Like ⌘-Tab, as a grid: hold Hyper, tap the shortcut to move, let go to switch. A quick tap jumps back to your last app.",
                tryIt: { AppSwitcherController.shared.show() }
            ) {
                Picker("Style", selection: $switcherStaysOpen) {
                    Text("Hold to switch").tag(false)
                    Text("Stay open (h j k l)").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            featureCard(
                action: .emojiPicker,
                detail: "Search emoji and symbols — arrows, math, currency, ⌘⌥⇧ keys. Return pastes into the app you were in; ⌘Return copies.",
                tryIt: { EmojiPickerController.shared.show() }
            )

            featureCard(
                action: .menuSearch,
                detail: "Find any menu command in the app you're using and run it. Shortcuts show on the right, so you learn them as you go.",
                tryIt: { MenuSearchController.shared.show() }
            )

            featureCard(
                action: .gifSearch,
                detail: "Search GIPHY and Klipy for GIFs and clips. Return copies, ⌘Return pastes into the app you were in, ⌘F stars, ⇥ switches source.",
                tryIt: { GifSearchController.shared.show() }
            ) {
                GifKeysEditor()
            }

            featureCard(
                action: .killProcess,
                detail: "Every app and process, by CPU or memory. Return quits the one you pick; ⌘Return force quits it.",
                tryIt: { KillProcessController.shared.show() }
            )

            AliasesSection()

            VStack(alignment: .leading, spacing: 10) {
                Text("Keys")
                    .font(.headline)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    keyHint(["⇥"], "Switcher: tap again (or hold) to move on", detail: "Hold to switch: let go to switch")
                    Divider().padding(.leading, 14)
                    keyHint(["↑", "↓", "←", "→"], "Move the selection", detail: "h j k l work in the switcher")
                    Divider().padding(.leading, 14)
                    keyHint(["/"], "Filter the switcher", detail: "Stay open")
                    Divider().padding(.leading, 14)
                    keyHint(["f"], "Show jump letters, then type one to switch", detail: "Stay open")
                    Divider().padding(.leading, 14)
                    keyHint(["↩"], "Open the app, or switch to the window")
                    Divider().padding(.leading, 14)
                    keyHint(["⌘", "↩"], "Show the app in Finder", detail: "App Search")
                    Divider().padding(.leading, 14)
                    keyHint(["esc"], "Clear what you typed, then close")
                    Divider().padding(.leading, 14)
                    keyHint(["⌘", ","], "Open these settings")
                }
                .hkCard()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Apps")
                    .font(.headline)
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.isLoading ? "Looking for apps…" : "\(provider.apps.count) apps found")
                            Text("App Search looks in your Applications folders and anything Spotlight knows about.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Rescan", systemImage: "arrow.clockwise") { provider.refresh() }
                            .disabled(provider.isLoading)
                    }
                    .padding(14)
                    Divider().padding(.leading, 14)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent apps")
                            Text("Apps you open from App Search are suggested first next time.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Recents") { searchModel.clearRecents() }
                            .disabled(searchModel.recentIds.isEmpty)
                    }
                    .padding(14)
                }
                .hkCard()
            }
        }
        .onAppear {
            provider.loadIfNeeded()
            searchModel.loadRecents()
        }
    }

    private func featureCard(action: BoundAction, detail: String, tryIt: @escaping () -> Void) -> some View {
        featureCard(action: action, detail: detail, tryIt: tryIt) { EmptyView() }
    }

    private func featureCard<Accessory: View>(
        action: BoundAction,
        detail: String,
        tryIt: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        let kind = ActionKind(action) ?? .appSearch

        return HStack(spacing: 16) {
            IconTile(symbol: kind.symbol, color: kind.color, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ActionShortcutField(action: action, bindingStore: bindingStore)
                accessory()
            }
            Spacer(minLength: 12)
            Button("Try It", action: tryIt)
                .hkProminentButtonStyle()
        }
        .padding(18)
        .hkGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: kind.color.opacity(0.06))
    }

    private func keyHint(_ keys: [String], _ title: String, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { KeycapChip($0, height: 22) }
            }
            .frame(width: 104, alignment: .leading)
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
