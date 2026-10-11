import Foundation

/// Rotating subtitle / theme flavor for the Roulette header.
enum RouletteTaglines {
    static let lines: [String] = [
        "Spin responsibly",
        "May contain regrets",
        "Theme rounds never sleep",
        "Listener picks welcome",
        "Shake it like Season 1–3",
        "Criterion tonight?",
        "Love Hurts — sometimes literally",
        "Cult classics & questionable takes",
        "What would the MRT Crew spin?",
        "No take-backsies",
        "Dinner, discussion, and dice",
        "Before they were famous…",
    ]

    static func random(excluding current: String? = nil) -> String {
        let pool = lines.filter { $0 != current }
        return (pool.isEmpty ? lines : pool).randomElement() ?? "Spin responsibly"
    }
}
