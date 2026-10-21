import Foundation
import MRTCore

/// Rotating subtitle / theme flavor for the Roulette header.
enum RouletteTaglines {
    static let lines: [String] = [
        "Spin responsibly",
        "May contain regrets",
        "Theme rounds never sleep",
        "Listener picks welcome",
        "Criterion tonight?",
        "Love Hurts — sometimes literally",
        "Cult classics & questionable takes",
        "No take-backsies",
        "Dinner, discussion, and the wheel",
    ]

    static func random(excluding current: String? = nil) -> String {
        let pool = lines.filter { $0 != current }
        return (pool.isEmpty ? lines : pool).randomElement() ?? "Spin responsibly"
    }
}
