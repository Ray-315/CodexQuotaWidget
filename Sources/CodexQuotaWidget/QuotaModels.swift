import Foundation

struct QuotaWindow: Equatable {
    let usedPercent: Double
    let remainingPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    init?(usedPercent: Double?, windowMinutes: Int?, resetsAtEpoch: Double?) {
        guard let usedPercent, let windowMinutes, let resetsAtEpoch else {
            return nil
        }

        let normalizedUsed = min(max(usedPercent, 0), 100)
        self.usedPercent = normalizedUsed
        self.remainingPercent = min(max(100 - normalizedUsed, 0), 100)
        self.windowMinutes = windowMinutes
        self.resetsAt = Date(timeIntervalSince1970: resetsAtEpoch)
    }

    var roundedRemainingPercent: Int {
        Int(remainingPercent.rounded())
    }
}

struct QuotaSnapshot: Equatable {
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let planType: String?
    let capturedAt: Date
    let sourceFile: URL

    var tightestRemainingPercent: Int? {
        [primary?.roundedRemainingPercent, secondary?.roundedRemainingPercent].compactMap { $0 }.min()
    }
}
