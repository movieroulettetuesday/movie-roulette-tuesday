import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit
import MRTCore
import MRTShared

/// Suggest a movie by scanning a QR code on a phone (mockup 15).
/// The code opens the show’s Buzzsprout fan-mail page. Nothing is typed on the TV.
struct TVSuggestView: View {
    var url: URL
    var onClose: () -> Void

    @Environment(\.colorScheme) private var scheme
    @FocusState private var doneFocused: Bool
    @State private var codeImage: UIImage?

    private var theme: TVTheme { TVTheme(scheme: scheme) }

    var body: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.45 : 0.25).ignoresSafeArea()
            HStack(alignment: .center, spacing: 56) {
                qr
                copy
            }
            .padding(56)
            .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(theme.card))
            .padding(.horizontal, 160)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tv.screen.suggest")
        .defaultFocus($doneFocused, true)
        .onAppear {
            if codeImage == nil { codeImage = Self.code(for: url.absoluteString) }
            TVFocus.soon { doneFocused = true }
        }
        .onExitCommand(perform: onClose)
    }

    private var qr: some View {
        ZStack {
            if let image = codeImage {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            }
            Circle()
                .fill(Brand.teal)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "film").font(.system(size: 28, weight: .bold)).foregroundStyle(.white))
        }
        .frame(width: 420, height: 420)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.white))
        .accessibilityLabel("QR code")
        .accessibilityIdentifier("tv.suggest.qr")
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Suggest a movie")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(theme.text)
            Text("on your phone")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(theme.teal)
            step(1, "Point your phone’s camera at the code")
            step(2, "Tap the link that appears")
            step(3, "Send Rachael, Karl & Matt your pick")
            HStack {
                Text(displayHost)
                    .font(.system(size: 24))
                    .foregroundStyle(theme.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("tv.suggest.url")
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(TVPillButtonStyle(width: 220, height: 84, fontSize: 34))
                    .focused($doneFocused)
                    .accessibilityIdentifier("tv.suggest.done")
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(theme.teal))
            Text(text)
                .font(.system(size: 32))
                .foregroundStyle(theme.text)
        }
    }

    private var displayHost: String {
        let host = url.host?.replacingOccurrences(of: "www.", with: "") ?? "buzzsprout.com"
        let path = url.path
        return host + path
    }

    static let fallbackURL = URL(string: "https://www.buzzsprout.com/2117292/fan_mail")!

    static func fanMailURL(in episodes: [PodcastEpisode]) -> URL {
        episodes.compactMap(\.fanMailURL).first ?? fallbackURL
    }

    private static func code(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "Q"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 14, y: 14))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
