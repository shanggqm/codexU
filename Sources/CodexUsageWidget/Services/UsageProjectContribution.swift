import CryptoKit
import Foundation

private struct UsageProjectContribution: Codable {
    let path: String
    let day: String
    var tokens: Int64 = 0
    var cost: Double = 0
    var lastActiveAt: Date
}

extension UsageIndexStore {
    func accumulateProject(projection: String, path: String, date: Date, priced: PricedTokenUsage, statistics: StatisticsContext) throws {
        let day = statistics.dayKey(for: date)
        let dimension = "project:" + SHA256.hash(data: Data((path+"\n"+day).utf8)).map { String(format:"%02x",$0) }.joined()
        var value = UsageProjectContribution(path: path, day: day, lastActiveAt: date)
        if let previous = try rows("SELECT payload FROM source_day WHERE projection_id=? AND day_key='' AND dimension_key=?",
            [.text(projection),.text(dimension)],limit:1).first?.first?.text {
            value = try JSONDecoder().decode(UsageProjectContribution.self, from: Data(previous.utf8))
        }
        let sum = value.tokens.addingReportingOverflow(priced.tokens.visibleTotalTokens)
        guard !sum.overflow else { throw UsageIndexError.resourceLimited }
        value.tokens = sum.partialValue; value.cost += priced.estimatedCostUSD
        value.lastActiveAt = max(value.lastActiveAt,date)
        guard value.cost.isFinite else { throw UsageIndexError.resourceLimited }
        let payload = String(decoding: try JSONEncoder().encode(value),as:UTF8.self)
        try execute("INSERT INTO source_day(projection_id,day_key,dimension_key,payload) VALUES (?,'',?,?) ON CONFLICT(projection_id,day_key,dimension_key) DO UPDATE SET payload=excluded.payload",
                    [.text(projection),.text(dimension),.text(payload)])
    }
}
