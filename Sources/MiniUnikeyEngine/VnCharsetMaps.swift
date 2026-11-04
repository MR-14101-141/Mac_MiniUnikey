//
//  VnCharsetMaps.swift
//  MiniUnikey
//
//  Ánh xạ ký tự ↔ lexeme theo bảng chuẩn UniKey (VnStdChar).
//  Parity: giá trị chẵn = chữ hoa, lẻ = chữ thường (UniKey dùng phép +1/-1 để đổi hoa/thường).
//
import Foundation

enum VnCharset {
    /// Bảng lexeme -> Unicode scalar (index = giá trị VnLexi; 186..212 là ký tự Latin mở rộng không dùng khi gõ)
    static let lexiUnicode: [Int] = VnTables.lexiUnicode

    /// Giá trị lexeme cuối cùng (186) — ranh giới bảng chuẩn.
    static let lastLexiIndex = VnLexi.vnl_lastChar.rawValue

    /// Ánh xạ Unicode scalar -> giá trị VnLexi.
    static let unicodeToLexi: [Int: Int] = {
        var map: [Int: Int] = [:]
        for i in 0..<(VnLexi.vnl_lastChar.rawValue) {
            let cp = lexiUnicode[i]
            if cp >= 0 { map[cp] = i }
        }
        return map
    }()

    /// ASCII a-z, A-Z -> lexeme (rút gọn từ unicodeToLexi).
    static let asciiToLexi: [Int: Int] = {
        var map: [Int: Int] = [:]
        for i in 0..<(VnLexi.vnl_lastChar.rawValue) {
            let cp = lexiUnicode[i]
            if (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A) {
                map[cp] = i
            }
        }
        return map
    }()

    /// lexi -> ký tự (nếu thuộc bảng). Không in đậm: dùng cho hiển thị đệm từ về sau.
    static func unicode(of lexi: Int) -> Int? {
        guard lexi >= 0 && lexi < lexiUnicode.count else { return nil }
        let cp = lexiUnicode[lexi]
        return cp >= 0 ? cp : nil
    }

    /// Kiểm tra lexeme là nguyên âm (a, ă, â, e, ê, i, o, ô, ơ, u, ư, y và các biến thể có dấu thanh).
    static let isVowel: [Int] = VnTablesHelper.isVowelTable

    static func isVowelLexi(_ lexi: Int) -> Bool {
        lexi >= 0 && lexi < isVowel.count && isVowel[lexi] == 1
    }

    /// Các dấu câu UniKey coi là ngắt từ (bản chính xác của WordBreakSyms, bỏ ~, `, ^)
    static let wordBreakChars: Set<Character> = {
        let list = ",;:.\"'!? <> = +-*/\\_@#$%&(){}[]|"
        var set = Set<Character>()
        for ch in list { set.insert(ch) }
        set.insert(" ")  // dấu cách cũng là ngắt từ
        set.insert("\t")
        return set
    }()

    static func vnToLower(_ lexi: Int) -> Int {
        if lexi == VnLexi.vnl_nonVnChar.rawValue { return lexi }
        return (lexi & 1) == 0 ? lexi + 1 : lexi
    }

    static func changeCase(_ lexi: Int) -> Int {
        if lexi == VnLexi.vnl_nonVnChar.rawValue { return lexi }
        if (lexi & 1) == 0 { return lexi + 1 }
        return lexi - 1
    }
}
