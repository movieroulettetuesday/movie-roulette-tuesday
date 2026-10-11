import MessageUI
import SwiftUI
import UIKit

/// "Suggest a movie" (approved v4 mockup). Opens a pre-filled email to the
/// show; nothing is sent unless the user taps Send in their mail app.
/// Order: Mail's compose sheet, else a `mailto:` link (other mail apps),
/// else copy the address and say so.
struct SuggestMovieSheet: View {
    var categories: [RouletteCategory] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var title = ""
    @State private var why = ""
    @State private var categoryName = ""
    @State private var showsComposer = false
    @State private var copiedAddress = false
    @FocusState private var titleFocused: Bool

    static let footer = "Opens Mail with this filled in, addressed to \(MovieSuggestion.address). Nothing is sent until you tap Send in Mail. No Mail account? We copy the address instead."

    private var suggestion: MovieSuggestion {
        MovieSuggestion(title: title, why: why, category: categoryName.isEmpty ? nil : categoryName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Movie title", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.next)
                        .accessibilityIdentifier("suggest-title")
                } header: { Text("Movie") }
                Section {
                    TextField("Why should the crew watch it?", text: $why, axis: .vertical)
                        .lineLimit(3...5)
                        .accessibilityIdentifier("suggest-why")
                } header: { Text("Why") }
                Section {
                    Picker("Category (optional)", selection: $categoryName) {
                        Text("None").tag("")
                        ForEach(categories) { Text($0.displayName).tag($0.displayName) }
                    }
                    .accessibilityIdentifier("suggest-category")
                } footer: {
                    Text(Self.footer)
                }
            }
            .cleanProListScreen()
            .navigationTitle("Suggest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Compose", action: compose)
                        .fontWeight(.semibold)
                        .disabled(!suggestion.isValid)
                        .accessibilityIdentifier("suggest-compose")
                }
            }
            .sheet(isPresented: $showsComposer) {
                MailComposeView(suggestion: suggestion) { sent in
                    showsComposer = false
                    if sent { dismiss() }
                }
                .ignoresSafeArea()
            }
            .alert("Email address copied", isPresented: $copiedAddress) {
                Button("OK") { dismiss() }
            } message: {
                Text("No mail app is set up, so we copied \(MovieSuggestion.address). Paste it into any email app to send your pick.")
            }
        }
    }

    private func compose() {
        let suggestion = self.suggestion
        guard suggestion.isValid else { return }
        if MFMailComposeViewController.canSendMail() {
            showsComposer = true
        } else if let url = suggestion.mailtoURL {
            openURL(url) { accepted in
                if accepted { dismiss() } else { copyAddress() }
            }
        } else {
            copyAddress()
        }
    }

    private func copyAddress() {
        UIPasteboard.general.string = MovieSuggestion.address
        copiedAddress = true
    }
}

/// Mail's own compose sheet, pre-filled.
struct MailComposeView: UIViewControllerRepresentable {
    let suggestion: MovieSuggestion
    /// Called on the main actor by `Coordinator`. Plain (non-`@Sendable`)
    /// closure: it is never converted or passed across isolation domains.
    let onFinish: (_ sent: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([MovieSuggestion.address])
        vc.setSubject(suggestion.subject)
        vc.setMessageBody(suggestion.body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    /// Standard representable coordinator: a main-actor class holding its
    /// parent view, with an isolated (`@MainActor`) delegate conformance.
    /// MessageUI calls the delegate on the main thread, so `parent.onFinish`
    /// runs on the main actor with no closure conversion and nothing sent
    /// across isolation domains. Warning-free in the default build (Swift 5 +
    /// Approachable Concurrency, as Xcode builds it) and in strict mode.
    @MainActor
    final class Coordinator: NSObject, @MainActor MFMailComposeViewControllerDelegate {
        let parent: MailComposeView
        init(parent: MailComposeView) { self.parent = parent }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            parent.onFinish(result == .sent || result == .saved)
        }
    }
}

/// The Movies tab entry row (approved v4 mockup).
struct SuggestMovieRow: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "envelope.badge")
                    .font(.title2).foregroundStyle(Brand.teal)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggest a movie").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("Email the crew a pick for a future episode").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggest a movie")
        .accessibilityHint("Email the crew a pick for a future episode")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("suggest-movie-row")
    }
}
