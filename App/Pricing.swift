import Foundation

/// USD／100万トークン。キャッシュ単価を省略すると入力単価から求める。
struct ModelPrice: Codable, Equatable, Sendable {
    var input: Double
    var output: Double
    var cacheRead: Double?
    var cacheWrite5m: Double?
    var cacheWrite1h: Double?
    /// Claude 4.5仕様以降（リージョナル係数の対象）か。
    var regional: Bool?
}

struct PriceFile: Codable {
    var models: [String: ModelPrice]
}

struct PriceTable: Sendable {
    static let regionalMultiplier = 1.1

    var models: [String: ModelPrice]

    static func decode(_ data: Data) throws -> PriceTable {
        PriceTable(models: try JSONDecoder().decode(PriceFile.self, from: data).models)
    }

    /// 同梱の単価表に、ユーザーの prices.json を上書きして返す。
    static func loadMerged() -> (table: PriceTable, error: String?) {
        var table = PriceTable(models: [:])
        var problem: String?
        if let url = Bundle.main.url(forResource: "prices", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let bundled = try? decode(data) {
            table = bundled
        } else {
            problem = "同梱の単価表を読み込めません"
        }
        if let data = try? Data(contentsOf: AppPaths.userPrices) {
            do {
                table.models.merge(try decode(data).models) { _, user in user }
            } catch {
                problem = "prices.json の形式が不正なため、同梱の単価を使っています"
            }
        }
        return (table, problem)
    }

    /// 単価表のキーと最長一致で照合する。
    /// "claude-opus-5" が "claude-opus-5-1" のような別バージョンに一致しないよう、続きが数字のものは除外する。
    func price(for model: String) -> ModelPrice? {
        if let exact = models[model] { return exact }
        let candidates = models.keys.filter { key in
            guard model.hasPrefix(key + "-") else { return false }
            let next = model.dropFirst(key.count + 1).prefix { $0 != "-" }
            return !next.allSatisfy(\.isNumber)
        }
        return candidates.max { $0.count < $1.count }.flatMap { models[$0] }
    }

    /// 単価が未登録なら nil。
    func cost(_ t: TokenCounts, model: String, regionalPricing: Bool) -> Double? {
        guard let p = price(for: model) else { return nil }
        let read = p.cacheRead ?? p.input * 0.1
        let write5m = p.cacheWrite5m ?? p.input * 1.25
        let write1h = p.cacheWrite1h ?? p.input * 2
        let sum = Double(t.input) * p.input
            + Double(t.output) * p.output
            + Double(t.cacheWrite5m) * write5m
            + Double(t.cacheWrite1h) * write1h
            + Double(t.cacheRead) * read
        let multiplier = regionalPricing && (p.regional ?? true) ? PriceTable.regionalMultiplier : 1
        return sum / 1_000_000 * multiplier
    }
}

enum ModelName {
    /// Haiku 5.5 はプロンプト長でリクエストごとに単価が変わるため、超過したものは別の行として集計する。
    /// プロンプト長にはキャッシュの読込・書込も含む。
    static func applyingLongPromptTier(_ model: String, promptTokens: Int) -> String {
        model == "claude-haiku-5-5" && promptTokens > 100_000 ? model + "-over-100k" : model
    }

    /// us.anthropic.claude-opus-5-5-v1:0 や日付付きIDを claude-opus-5-5 の形にする。
    static func normalize(_ raw: String) -> String {
        var name = raw
        if name.hasSuffix("[1m]") { name.removeLast(4) }
        if let range = name.range(of: "anthropic.") {
            name = String(name[range.upperBound...])
        } else if let range = name.range(of: #"^[a-z]+\."#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        if let range = name.range(of: #"-v[0-9]+(:[0-9a-z]+)*$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        if let range = name.range(of: #"-[0-9]{8}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }
}
