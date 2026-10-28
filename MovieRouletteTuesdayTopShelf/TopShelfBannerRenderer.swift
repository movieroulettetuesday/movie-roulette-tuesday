import UIKit
import MRTCore

/// Draws the approved latest-episode banner (poster on the left, title on the
/// right). Pixel sizes come from `TopShelfBannerMetrics`; this only paints them.
/// Final show art replaces the placeholder poster when the download succeeds.
@MainActor
enum TopShelfBannerRenderer {
    static func png(episode: TopShelfEpisode, artwork: UIImage?, canvas: TopShelfPixelSize) -> Data? {
        let layout = TopShelfBannerMetrics.layout(for: episode, canvas: canvas)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: layout.canvas.width, height: layout.canvas.height),
            format: format
        )
        let image = renderer.image { context in
            draw(layout, artwork: artwork, in: context.cgContext)
        }
        return image.pngData()
    }

    private static func draw(_ layout: TopShelfBannerLayout, artwork: UIImage?, in context: CGContext) {
        let width = CGFloat(layout.canvas.width)
        let height = CGFloat(layout.canvas.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                UIColor(red: 0.18, green: 0.28, blue: 0.30, alpha: 1).cgColor,
                UIColor(red: 0.10, green: 0.15, blue: 0.17, alpha: 1).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: width, y: height),
                options: []
            )
        } else {
            UIColor(red: 0.12, green: 0.18, blue: 0.20, alpha: 1).setFill()
            context.fill(bounds)
        }

        context.saveGState()
        context.setFillColor(UIColor(red: 0.22, green: 0.62, blue: 0.66, alpha: 0.22).cgColor)
        context.fillEllipse(in: CGRect(x: width * 0.42, y: -height * 0.55, width: width * 0.75, height: height))
        context.restoreGState()

        let poster = CGRect(
            x: layout.poster.x,
            y: layout.poster.y,
            width: layout.poster.width,
            height: layout.poster.height
        )
        let radius = CGFloat(layout.cornerRadius)
        let posterPath = UIBezierPath(roundedRect: poster, cornerRadius: radius)
        context.saveGState()
        posterPath.addClip()
        if let artwork, artwork.size.width > 0, artwork.size.height > 0 {
            artwork.draw(in: aspectFill(artwork.size, in: poster))
        } else {
            UIColor(red: 0.86, green: 0.78, blue: 0.68, alpha: 1).setFill()
            context.fill(poster)
        }
        context.restoreGState()
        UIColor.white.withAlphaComponent(0.2).setStroke()
        posterPath.lineWidth = max(2, radius * 0.08)
        posterPath.stroke()

        let columnX = CGFloat(layout.textColumnX)
        let columnWidth = CGFloat(layout.textColumnWidth)
        var cursorY = CGFloat(layout.textTop)

        if layout.showsNewBadge {
            let badge = drawBadge(layout.badgeText, fontSize: CGFloat(layout.badgeFontSize), at: CGPoint(x: columnX, y: cursorY))
            let metaFont = UIFont.systemFont(ofSize: CGFloat(layout.metaFontSize), weight: .medium)
            let meta = layout.metaLine as NSString
            let metaSize = meta.size(withAttributes: [.font: metaFont])
            let metaX = badge.maxX + CGFloat(layout.badgeFontSize)
            let maxMetaWidth = columnX + columnWidth - metaX
            if maxMetaWidth > metaSize.height {
                meta.draw(
                    in: CGRect(x: metaX, y: badge.midY - metaFont.lineHeight / 2, width: maxMetaWidth, height: metaFont.lineHeight),
                    withAttributes: [
                        .font: metaFont,
                        .foregroundColor: UIColor.white.withAlphaComponent(0.78),
                    ]
                )
            }
            cursorY = badge.maxY + CGFloat(layout.badgeFontSize)
        } else if !layout.metaLine.isEmpty {
            cursorY = drawLine(
                layout.metaLine,
                font: .systemFont(ofSize: CGFloat(layout.metaFontSize), weight: .medium),
                color: UIColor.white.withAlphaComponent(0.78),
                x: columnX,
                y: cursorY,
                width: columnWidth,
                lines: 1
            )
        }

        cursorY += CGFloat(layout.titleFontSize) * 0.15
        cursorY = drawLine(
            layout.title,
            font: .systemFont(ofSize: CGFloat(layout.titleFontSize), weight: .bold),
            color: .white,
            x: columnX,
            y: cursorY,
            width: columnWidth,
            lines: 2
        )

        if let detail = layout.detailLine, !detail.isEmpty {
            cursorY += CGFloat(layout.detailFontSize) * 0.35
            cursorY = drawLine(
                detail,
                font: .systemFont(ofSize: CGFloat(layout.detailFontSize), weight: .regular),
                color: UIColor.white.withAlphaComponent(0.82),
                x: columnX,
                y: cursorY,
                width: columnWidth,
                lines: 2
            )
        }

        cursorY += CGFloat(layout.showFontSize) * 0.9
        let dot = CGFloat(layout.showFontSize) * 0.85
        let dotRect = CGRect(x: columnX, y: cursorY + (CGFloat(layout.showFontSize) - dot) / 2, width: dot, height: dot)
        UIColor(red: 0.18, green: 0.62, blue: 0.65, alpha: 1).setFill()
        UIBezierPath(ovalIn: dotRect).fill()
        let nameX = dotRect.maxX + dot * 0.45
        _ = drawLine(
            layout.showName,
            font: .systemFont(ofSize: CGFloat(layout.showFontSize), weight: .semibold),
            color: .white,
            x: nameX,
            y: cursorY,
            width: max(1, columnX + columnWidth - nameX),
            lines: 1
        )
    }

    private static func drawBadge(_ text: String, fontSize: CGFloat, at origin: CGPoint) -> CGRect {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        let string = text as NSString
        let textSize = string.size(withAttributes: [.font: font])
        let padX = textSize.height * 0.55
        let padY = textSize.height * 0.28
        let rect = CGRect(x: origin.x, y: origin.y, width: textSize.width + padX * 2, height: textSize.height + padY * 2)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        UIColor(red: 0.16, green: 0.62, blue: 0.66, alpha: 1).setFill()
        path.fill()
        string.draw(
            at: CGPoint(x: rect.minX + padX, y: rect.minY + padY),
            withAttributes: [.font: font, .foregroundColor: UIColor.white]
        )
        return rect
    }

    @discardableResult
    private static func drawLine(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        lines: Int
    ) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let height = font.lineHeight * CGFloat(lines) * 1.05
        let rect = CGRect(x: x, y: y, width: width, height: height)
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: style,
            ],
            context: nil
        )
        return y + height
    }

    private static func aspectFill(_ imageSize: CGSize, in frame: CGRect) -> CGRect {
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
