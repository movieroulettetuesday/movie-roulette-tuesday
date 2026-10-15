import MessageUI
import SwiftUI
import UIKit

/// "Suggest a Movie": one sheet. The primary action, Send, saves a `Suggestion`
/// record to the CloudKit public database (anonymous, create-only for
/// listeners). "Send by email instead" opens Mail's compose sheet, else a
/// `mailto:` link (other mail apps), else copies the address and says so.
/// When iCloud isn't available the email option still works.
struct SuggestMovieSheet: View {
    var categories: [RouletteCategory] = []
    var onSent: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(CommunityService.self) private var community

    @State private var draft = InAppSuggestion(title: "")
    @State private var sending = false
    @State private var errorMessage: String?
    @State private var sent = false
    @State private var showsComposer = false
    @State private var copiedAddress = false

    private var iCloudUnavailable: Bool {
        switch community.accountStatus {
        case .noAccount, .unavailable: return true
        case .unknown, .available: return false
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Movie title", text: $draft.title, prompt: Text("Tremors (1990)"))
                        .onChange(of: draft.title) { _, v in
                            let c = InAppSuggestion.capped(v, to: InAppSuggestion.titleLimit)
                            if c != v { draft.title = c }
                        }
                        .accessibilityIdentifier("suggest-title")
                    Picker("Category", selection: Binding(
                        get: { draft.category ?? "" },
                        set: { draft.category = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(categories) { Text($0.displayName).tag($0.displayName) }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityIdentifier("suggest-category")
                } header: { Text("What should the hosts spin?") }

                Section {
                    TextField("Why it belongs on the wheel", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: draft.note) { _, v in
                            let c = InAppSuggestion.capped(v, to: InAppSuggestion.noteLimit)
                            if c != v { draft.note = c }
                        }
                        .accessibilityIdentifier("suggest-why")
                } header: { Text("Why (optional)") } footer: {
                    Text("\(max(draft.noteCharactersLeft, 0)) characters left")
                        .monospacedDigit()
                }

                Section {
                    TextField("Credit me as", text: $draft.creditName, prompt: Text("e.g. “Laura from Ohio”"))
                        .onChange(of: draft.creditName) { _, v in
                            let c = InAppSuggestion.capped(v, to: InAppSuggestion.nameLimit)
                            if c != v { draft.creditName = c }
                        }
                        .accessibilityIdentifier("suggest-credit")
                } header: { Text("Credit me as (optional)") } footer: {
                    Text("Only what you type here is sent.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: iCloudUnavailable ? "icloud.slash" : "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("suggest-error")
                    }
                }

                Section {
                    Button {
                        sendByEmail()
                    } label: {
                        HStack {
                            Text("Send by email instead")
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("suggest-email")
                }
            }
            .cleanProListScreen()
            .navigationTitle("Suggest a Movie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if sending {
                        ProgressView()
                    } else {
                        Button("Send", action: send)
                            .fontWeight(.semibold)
                            .disabled(!draft.isValid)
                            .accessibilityIdentifier("suggest-send")
                    }
                }
            }
            .sheet(isPresented: $showsComposer) {
                MailComposeView(suggestion: draft.asEmail) { sentByMail in
                    showsComposer = false
                    if sentByMail { dismiss(); onSent() }
                }
                .ignoresSafeArea()
            }
            .alert("Thanks! Suggestion sent.", isPresented: $sent) {
                Button("OK") { dismiss(); onSent() }
            } message: {
                Text("The hosts will see your pick.")
            }
            .alert("Email address copied", isPresented: $copiedAddress) {
                Button("OK") { dismiss() }
            } message: {
                Text("No mail app is set up, so we copied \(MovieSuggestion.address). Paste it into any email app to send your pick.")
            }
            .task {
                await community.refreshAccountStatus()
                if iCloudUnavailable, errorMessage == nil {
                    errorMessage = "iCloud isn’t available, so Send won’t work. Use email instead."
                }
            }
        }
    }

    private func send() {
        guard draft.isValid, !sending else { return }
        let defaults = UserDefaults.standard
        var limit = SuggestionRateLimit.load(from: defaults)
        if let seconds = limit.secondsRemaining() {
            errorMessage = SuggestionRateLimit.message(seconds: seconds)
            return
        }
        sending = true
        errorMessage = nil
        let suggestion = draft
        Task {
            let error = await community.submitSuggestion(suggestion)
            sending = false
            if let error {
                errorMessage = error
            } else {
                limit.recordSend()
                limit.save(to: defaults)
                sent = true
            }
        }
    }

    private func sendByEmail() {
        let email = draft.asEmail
        guard email.isValid else { return }
        if MFMailComposeViewController.canSendMail() {
            showsComposer = true
        } else if let url = email.mailtoURL {
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
                    Text("Suggest a movie for the show").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("Send the hosts a pick for a future episode").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggest a movie for the show")
        .accessibilityHint("Send the hosts a pick for a future episode")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("suggest-movie-row")
    }
}
