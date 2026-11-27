import Foundation

/// Tiny ergonomic wrapper for traversing InnerTube's deeply nested JSON.
struct JSON {
    let raw: Any?

    init(raw: Any?) { self.raw = raw }
    init(data: Data) {
        self.raw = try? JSONSerialization.jsonObject(with: data)
    }

    subscript(_ key: String) -> JSON {
        JSON(raw: (raw as? [String: Any])?[key])
    }

    subscript(_ index: Int) -> JSON {
        if let arr = raw as? [Any], index >= 0, index < arr.count {
            return JSON(raw: arr[index])
        }
        return JSON(raw: nil)
    }

    var string: String? { raw as? String }
    var array: [JSON] { (raw as? [Any])?.map { JSON(raw: $0) } ?? [] }

    /// Depth-first search: collect every value stored under `key` anywhere below.
    func findAll(_ key: String) -> [JSON] {
        var out: [JSON] = []
        collect(key, into: &out)
        return out
    }

    func findFirst(_ key: String) -> JSON? {
        var out: [JSON] = []
        collect(key, into: &out, firstOnly: true)
        return out.first
    }

    private func collect(_ key: String, into out: inout [JSON], firstOnly: Bool = false) {
        if firstOnly && !out.isEmpty { return }
        if let dict = raw as? [String: Any] {
            if let hit = dict[key] {
                out.append(JSON(raw: hit))
                if firstOnly { return }
            }
            for (_, v) in dict {
                JSON(raw: v).collect(key, into: &out, firstOnly: firstOnly)
                if firstOnly && !out.isEmpty { return }
            }
        } else if let arr = raw as? [Any] {
            for v in arr {
                JSON(raw: v).collect(key, into: &out, firstOnly: firstOnly)
                if firstOnly && !out.isEmpty { return }
            }
        }
    }
}
