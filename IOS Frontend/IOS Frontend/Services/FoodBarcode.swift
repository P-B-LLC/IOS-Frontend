import Foundation

nonisolated enum FoodBarcode {
    static func validated(_ raw: String) -> String? {
        let code = NumberInput.latinDigits(raw).replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        let bytes = Array(code.utf8)
        guard [8, 12, 13, 14].contains(bytes.count), bytes.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let sum = bytes.dropLast().reversed().enumerated().reduce(0) {
            $0 + Int($1.element - 48) * ($1.offset.isMultiple(of: 2) ? 3 : 1)
        }
        guard (10 - sum % 10) % 10 == Int(bytes.last! - 48) else { return nil }
        return bytes.count == 12 ? "0" + code : code
    }

    static func expandUPCE(_ raw: String) -> String? {
        let chars = Array(raw)
        guard chars.count == 8, chars.allSatisfy({ $0.isASCII && $0.isNumber }), chars[0] == "0" || chars[0] == "1" else { return nil }
        let n = String(chars[0]), d = chars[1...6].map(String.init), check = String(chars[7])
        let body: String
        switch d[5] {
        case "0", "1", "2": body = n + d[0] + d[1] + d[5] + "0000" + d[2] + d[3] + d[4]
        case "3": body = n + d[0] + d[1] + d[2] + "00000" + d[3] + d[4]
        case "4": body = n + d[0] + d[1] + d[2] + d[3] + "00000" + d[4]
        default: body = n + d[0] + d[1] + d[2] + d[3] + d[4] + "0000" + d[5]
        }
        return validated(body + check)
    }
}
