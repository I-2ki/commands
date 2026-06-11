import CoreServices
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: dict <word>\n", stderr)
    exit(1)
}

let word = CommandLine.arguments[1]

let base = "/System/Library/AssetsV2/com_apple_MobileAsset_DictionaryServices_dictionary3macOS"
let fm = FileManager.default

guard let wisdomPath = (try? fm.contentsOfDirectory(atPath: base))?
    .map({ "\(base)/\($0)/AssetData/Sanseido The WISDOM English-Japanese Japanese-English Dictionary.dictionary" })
    .first(where: { fm.fileExists(atPath: $0) }) else {
    fputs("WISDOM dictionary not found\n", stderr)
    exit(1)
}

let defaults = UserDefaults.standard
var prefs = (defaults.persistentDomain(forName: "com.apple.DictionaryServices") ?? [:]) as! [String: Any]
let original = prefs["DCSActiveDictionaries"]
prefs["DCSActiveDictionaries"] = [wisdomPath]
defaults.setPersistentDomain(prefs, forName: "com.apple.DictionaryServices")

let range = CFRangeMake(0, word.utf16.count)
guard let def = DCSCopyTextDefinition(nil, word as CFString, range) else {
    prefs["DCSActiveDictionaries"] = original
    defaults.setPersistentDomain(prefs, forName: "com.apple.DictionaryServices")
    fputs("Not found: \(word)\n", stderr)
    exit(1)
}

var text = def.takeRetainedValue() as String

prefs["DCSActiveDictionaries"] = original
defaults.setPersistentDomain(prefs, forName: "com.apple.DictionaryServices")

// 丸数字を番号に変換
func convertCircled(_ s: String) -> String {
    var result = ""
    for char in s {
        if let scalar = char.unicodeScalars.first,
           scalar.value >= 0x2460 && scalar.value <= 0x2473 {
            let num = scalar.value - 0x2460 + 1
            result += "\n\(num). "
        } else {
            result += String(char)
        }
    }
    return result
}

// 例文行の英日分割（英字が3文字以上続いた後に日本語が来たとき）
func splitEnJp(_ s: String) -> String {
    var result = ""
    var asciiCount = 0
    var prev: Character = " "
    for char in s {
        let scalar = char.unicodeScalars.first!.value
        let isJp = scalar >= 0x3040 && scalar <= 0x9FFF
        let isAsciiLetter = (scalar >= 0x41 && scalar <= 0x5A) || (scalar >= 0x61 && scalar <= 0x7A)
        let isPunct = scalar == 0x2E || scalar == 0x21 || scalar == 0x3F // . ! ?

        if isAsciiLetter {
            asciiCount += 1
        } else if !isPunct {
            asciiCount = 0
        }

        if isJp && asciiCount >= 3 {
            result += "\n     "
            asciiCount = 0
        }
        result += String(char)
        prev = char
    }
    return result
}

// 品詞を先に変換（正規表現で前後にスペースや数字がある場合）
for pos in ["前置詞", "接続詞", "他動詞", "自動詞", "名詞", "形容詞", "副詞"] {
    text = text.replacingOccurrences(
        of: "\(pos)([0-9])",
        with: "\n\n【\(pos)】\n\n$1",
        options: .regularExpression
    )
    text = text.replacingOccurrences(of: "\(pos)", with: "\n\n【\(pos)】\n")
}

// 丸数字変換
text = convertCircled(text)

// a. b. c. サブ番号に改行
text = text.replacingOccurrences(of: " ([a-z]\\.) ", with: "\n  $1 ", options: .regularExpression)

// 例文 ▸ を改行+インデント、英日分割
text = text.components(separatedBy: "\n").map { line -> String in
    if line.contains("▸") {
        let converted = line.replacingOccurrences(of: "▸", with: "\n  ▸")
        return converted.components(separatedBy: "\n").map { l in
            l.hasPrefix("  ▸") ? splitEnJp(l) : l
        }.joined(separator: "\n")
    }
    return line
}.joined(separator: "\n")

// 注釈 (! を別行インデント（ただし文中の括弧は除く）
text = text.replacingOccurrences(of: "\\(!", with: "\n     (!", options: .regularExpression)

// ≒ の前で改行
text = text.replacingOccurrences(of: "≒", with: "\n     ≒ ")

// セクション見出し
for section in ["語法", "類義", "コーパスの窓", "コーパス", "表現"] {
    text = text.replacingOccurrences(of: "── \(section)", with: "\n\n── \(section)\n")
    text = text.replacingOccurrences(of: " \(section) \n", with: "\n\n── \(section)\n")
}

// 〖〗 スペース整理
text = text.replacingOccurrences(of: "〖", with: " 〖")
text = text.replacingOccurrences(of: "〗", with: "〗 ")

// 連続改行・スペース整理
text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
text = text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

print(text)
