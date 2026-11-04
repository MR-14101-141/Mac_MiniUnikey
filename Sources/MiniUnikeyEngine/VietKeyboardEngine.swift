//
//  VietKeyboardEngine.swift
//  MiniUnikey
//
//  Engine cốt lõi kiểu gõ VNI — port 1:1 thuật toán engine UniKey
//  (Phạm Kim Long, ukengine — nguồn: fcitx5-unikey, LGPL-2.1+).
//  Bảng vần/dữ liệu được sinh 1:1 từ nguồn gốc trong VniTables[Helper].swift.
//
import Foundation

/// Dạng của từ đang gõ trong bộ đệm (bản dịch VnWordForm)
public enum VnWordForm: Int {
    case nonVn = 0
    case empty
    case cons
    case vowel
    case cv
    case vc
    case cvc
}

/// Kiểu phân loại sự kiện (bản dịch UkCharType)
public enum UkCharType {
    case reset
    case wordBreak
    case nonVn
    case vn
}

/// Phương thức gõ (mirrors UkInputMethod của UniKey)
public enum VnInputMethod: String {
    case vni
    case telex
    case simpleTelex   // w chỉ làm móc khi có nguyên âm trước đó (không ép ư)
}

/// Hành động bấm phím theo kiểu gõ VNI
public enum VniAction: Equatable {
    case normal
    case txW           // Telex: phím w (gán móc hoặc ép ư/literal tùy ngữ cảnh)
    case roofAll
    case roofA, roofE, roofO
    case hookAll
    case hookUO
    case hookU, hookO
    case bowl
    case dd
    case tone(Int)   // 0..5
}

/// Sự kiện phím theo kiểu UniKey
public struct UkKeyEvent {
    var keyCode: UInt32 = 0
    var action: VniAction = .normal
    var vnSym: Int = VnLexi.vnl_nonVnChar.rawValue
    var chType: UkCharType = .nonVn
    var tone: Int = 0
}

/// Cấu hình engine
public struct EngineOptions {
    public var vietKey = true
    public var spellCheckEnabled = true
    public var freeMarking = true
    public var modernStyle = false
}

public final class VietKeyboardEngine {
    // MARK: - API công khai

    /// Chạy một ký tự. Kết quả:
    /// - changed == false → để hệ thống chèn phím gốc.
    /// - changed == true  → hệ thống tự xoá `backs` ký tự cuối rồi chèn `output`.
    ///   (output rỗng tương ứng trường hợp "đảo dấu": chèn lại chính phím gốc)
    public func process(_ key: UInt32) -> (backs: Int, output: String, changed: Bool) {
        prepareBuffer()
        backs = 0
        changePos = current + 1
        outString = ""
        outputWritten = false

        var ev = VietKeyboardEngine.eventFrom(key, method: method)
        var ret = dispatch(&ev)

        if options.vietKey, current >= 0, buffer[current].form == .nonVn,
           ev.chType == .vn, (!options.spellCheckEnabled || singleMode) {
            ret = processNoSpellCheck(&ev)
        }

        if ret == 0 { return (0, "", false) }
        if !outputWritten { writeOutput() }
        return (backs, outString, true)
    }

    /// Backspace: nếu việc xoá chữ cần dời lại dấu thanh, trả về số lần xoá + chuỗi phải chèn.
    public func processBackspace() -> (backs: Int, output: String, changed: Bool) {
        guard options.vietKey, current >= 0 else { return (1, "", false) }
        prepareBuffer()
        backs = 0
        changePos = current + 1
        markChange(current)

        if current == 0 || buffer[current].form == .empty || buffer[current].form == .nonVn ||
            buffer[current].form == .cons || buffer[current - 1].form == .cons ||
            buffer[current - 1].form == .cvc || buffer[current - 1].form == .vc ||
            !VietKeyboardEngine.isValidVSeq(buffer[current - 1].vseq) {
            current -= 1
            return (max(backs, 1), "", true)
        }

        let vEnd = current - buffer[current].vOffset
        let vsRaw = buffer[vEnd].vseq
        guard VietKeyboardEngine.isValidVSeq(vsRaw) else { return (max(backs, 1), "", true) }
        let vs = VnVowelSeq(rawValue: vsRaw)!
        let newVs = buffer[current - 1].vseq
        guard VietKeyboardEngine.isValidVSeq(newVs) else { return (max(backs, 1), "", true) }
        let lenRow = VietKeyboardEngine.vSeqList[vs.rawValue][0] - 1
        let vStart = vEnd - lenRow
        let curTonePos = vStart + getTonePosition(vs, vEnd == current)
        let newTonePos = vStart + getTonePosition(VnVowelSeq(rawValue: newVs)!, true)
        let tone = buffer[curTonePos].tone

        if tone == 0 || curTonePos == newTonePos ||
            (curTonePos == current && buffer[current].tone != 0) {
            current -= 1
            return (backs, "", true)
        }

        markChange(newTonePos)
        buffer[newTonePos].tone = tone
        markChange(curTonePos)
        buffer[curTonePos].tone = 0
        current -= 1
        writeOutput()
        return (backs, outString, true)
    }

    public func reset() {
        current = -1
        singleMode = false
    }

    public func atWordBeginning() -> Bool {
        current < 0 || buffer[current].form == .empty
    }

    public func debugBufferSize() -> Int { buffer.count }

    // MARK: - Bảng & trạng thái

    private static let vSeqList = VnTables.vSeqList    // [len, complete, conSuf, v0..2, sub0..2, roofPos, withRoof, hookPos, withHook]
    private static let cSeqList = VnTables.cSeqList    // [len, c0..2, suffix]
    private static let vcPairs: Set<[Int]> = Set(VnTables.vcPairs.map { [$0[0], $0[1]] })

    /// Phương thức gõ hiện hành (VNI / Telex)
    public var method: VnInputMethod = .vni

    public struct WordInfo {
        var form: VnWordForm = .empty
        var c1Offset: Int = -1
        var vOffset: Int = -1
        var c2Offset: Int = -1
        var vseq: Int = VnVowelSeq.vs_nil.rawValue
        var cseq: Int = VnConSeq.cs_nil.rawValue
        var caps: Int = 0
        var tone: Int = 0
        var vnSym: Int = VnLexi.vnl_nonVnChar.rawValue
        var keyCode: UInt32 = 0
    }

    private var buffer: [WordInfo] = []
    private var bufferCapacity = 128
    public var current = -1
    private var changePos = -1
    private var backs = 0
    private var singleMode = false

    private var outString = ""
    private var outputWritten = false

    public var options = EngineOptions()

public init() { reset() }

    // MARK: - Phân loại phím

    static func eventFrom(_ key: UInt32, method: VnInputMethod? = nil) -> UkKeyEvent {
        var ev = UkKeyEvent()
        ev.keyCode = key
        let method = method ?? .vni

        if key == 0 {
            ev.chType = .wordBreak
            return ev
        }
        guard let scalar = UnicodeScalar(key) else {
            ev.chType = .nonVn
            return ev
        }
        let c = Character(scalar)

        if c == "\n" || c == "\r" || key <= UInt32(31) {
            ev.chType = .reset
            return ev
        }

        switch method {
        case .vni:
            // Chữ số → hành động VNI
            if key >= 48 && key <= 57 {
                ev.chType = .nonVn
                switch key {
                case 48: ev.action = .tone(0)
                case 49: ev.action = .tone(1); ev.tone = 1
                case 50: ev.action = .tone(2); ev.tone = 2
                case 51: ev.action = .tone(3); ev.tone = 3
                case 52: ev.action = .tone(4); ev.tone = 4
                case 53: ev.action = .tone(5); ev.tone = 5
                case 54: ev.action = .roofAll
                case 55: ev.action = .hookUO
                case 56: ev.action = .bowl
                default: ev.action = .dd
                }
                return ev
            }

        case .telex, .simpleTelex:
            // Chữ cái ưu tiên → hành động Telex (phản chiếu TelexMethodMapping của UniKey)
            switch key {
            case 122, 90:   ev.action = .tone(0); ev.tone = 0    // z Z ← xoá dấu
            case 115, 83:   ev.action = .tone(1); ev.tone = 1    // s S sắc
            case 102, 70:   ev.action = .tone(2); ev.tone = 2    // f F huyền
            case 114, 82:   ev.action = .tone(3); ev.tone = 3    // r R hỏi
            case 120, 88:   ev.action = .tone(4); ev.tone = 4    // x X ngã
            case 106, 74:   ev.action = .tone(5); ev.tone = 5    // j J nặng
            case 97, 65:    ev.action = .roofA                   // a A → â
            case 101, 69:   ev.action = .roofE                   // e E → ê
            case 111, 79:   ev.action = .roofO                   // o O → ô
            case 100, 68:   ev.action = .dd                      // d D → đ
            default: break
            }
            if key == 119 || key == 87 {   // w W
                ev.action = method == .telex ? .txW : .hookAll
                ev.chType = .nonVn        // như C: UkcMap['w'] = ukcNonVn
                return ev
            }
            // nếu không map thành action đặc biệt → đi tiếp phần chung bên dưới

        }

        // Chữ cái ASCII
        if (key >= 65 && key <= 90) || (key >= 97 && key <= 122) {
            // UniKey gốc coi f, j, w là ký tự không phải tiếng Việt
            let isNonVnLetter = (key == 102 || key == 70 ||   // f F
                                 key == 106 || key == 74 ||   // j J
                                 key == 119 || key == 87)     // w W
            if let lexi = VnCharset.asciiToLexi[Int(key)] {
                ev.vnSym = lexi        // giữ sym (ví dụ dd-escape cần thấy 'd'... f/j/w không tham gia)
                ev.chType = isNonVnLetter ? .nonVn : .vn
            } else {
                ev.chType = .nonVn
            }
            return ev
        }

        // Ký tự Việt (Unicode > 127) → ánh xạ qua bảng chuẩn
        if key > 127, let lexi = VnCharset.unicodeToLexi[Int(key)], lexi < VnLexi.vnl_lastChar.rawValue {
            ev.vnSym = lexi
            ev.chType = .vn
            return ev
        }

        // Dấu câu ngắt từ
        if VnCharset.wordBreakChars.contains(c) {
            ev.chType = .wordBreak
            return ev
        }

        ev.chType = .nonVn
        return ev
    }

    // MARK: - Dispatcher

    private func dispatch(_ ev: inout UkKeyEvent) -> Int {
        switch ev.action {
        case .roofAll, .roofA, .roofE, .roofO:
            return processRoof(&ev)
        case .hookAll, .hookUO, .hookU, .hookO, .bowl:
            return processHook(&ev)
        case .dd:
            return processDd(&ev)
        case .tone:
            return processTone(&ev)
        case .txW:
            return processTelexW(&ev)
        case .normal:
            return processAppend(&ev)
        }
    }

    // MARK: - processTelexW (phím w trong Telex — port 1:1 C processTelexW)

    private var usedAsMapChar = false

    private func processTelexW(_ ev: inout UkKeyEvent) -> Int {
        if !options.vietKey { return processAppend(&ev) }

        if usedAsMapChar {
            var mapEv = ev
            mapEv.action = .normal
            mapEv.chType = .vn
            mapEv.vnSym = keyUpper(ev.keyCode) ? VnLexi.vnl_Uh.rawValue : VnLexi.vnl_uh.rawValue
            let ret = processMapCharVN(&mapEv, rawKey: ev.keyCode)
            if ret == 0 {
                if current >= 0 { current -= 1 }
                usedAsMapChar = false
                mapEv.action = .hookAll
                mapEv.chType = .nonVn
                return processHook(&mapEv)
            }
            return ret
        }

        usedAsMapChar = false
        var hookEv = ev
        hookEv.action = .hookAll
        let ret = processHook(&hookEv)
        if ret == 0 {
            if current >= 0 { current -= 1 }        // pop ô 'w' nonVN vừa append
            var mapEv = ev
            mapEv.action = .normal
            mapEv.chType = .vn
            mapEv.vnSym = keyUpper(ev.keyCode) ? VnLexi.vnl_Uh.rawValue : VnLexi.vnl_uh.rawValue
            usedAsMapChar = true
            return processMapCharVN(&mapEv, rawKey: ev.keyCode)
        }
        return ret
    }

    private func keyUpper(_ code: UInt32) -> Bool {
        (65...90).contains(code)
    }

    /// Port 1:1 C processMapChar: thử chèn ký tự VN; nếu từ vẫn hợp lệ → nuốt phím (backs=0, output=ư);
    /// nếu từ kỳ dị → pop, undo ô 'ư' trùng (nếu có), rồi append literal 'w'.
    private func processMapCharVN(_ ev: inout UkKeyEvent, rawKey: UInt32) -> Int {
        _ = processAppend(&ev)                       // chèn 'ư' như ký tự VN (ev.chType=.vn)
        if !options.vietKey { return 0 }

        if current >= 0 && buffer[current].form != .empty && buffer[current].form != .nonVn {
            return 1                                  // từ vẫn hợp lệ: nuốt phím, chèn 'ư'
        }
        if current < 0 { return 0 }

        // mapChar doesn't apply — pop ô 'ư' vừa thử
        current -= 1
        var undo = false
        if current >= 0 {
            let entry = buffer[current]
            if entry.form != .empty && entry.form != .nonVn {
                var prevSym = entry.vnSym
                if entry.caps == 1 { prevSym -= 1 }
                if prevSym == ev.vnSym {              // ô trước là 'ư' tương tự → undo (gõ w chữ 2)
                    if entry.form != .cons {
                        // dịch lại tông như C trong processMapChar-undo
                        let vs = VnVowelSeq(rawValue: entry.vseq)!
                        let info = VietKeyboardEngine.vSeqList[vs.rawValue]
                        let vEnd = current - entry.vOffset
                        let vStart = vEnd - (info[0] - 1)
                        let curTonePos = vStart + getTonePosition(vs, vEnd == current)
                        let tone = buffer[curTonePos].tone
                        markChange(current)
                        current -= 1
                        if tone != 0 && current >= 0 &&
                            (buffer[current].form == .vowel || buffer[current].form == .cv) {
                            let newVs = VnVowelSeq(rawValue: buffer[current].vseq)!
                            let newTonePos = vStart + getTonePosition(newVs, true)
                            if newTonePos != curTonePos {
                                markChange(newTonePos)
                                buffer[newTonePos].tone = tone
                                markChange(curTonePos)
                                buffer[curTonePos].tone = 0
                            }
                        }
                    } else {
                        markChange(current)
                        current -= 1
                    }
                    undo = true
                }
            }
        }

        // append literal 'w'
        var rawEv = UkKeyEvent()
        rawEv.keyCode = ev.keyCode
        rawEv.action = .normal
        rawEv.chType = .nonVn
        rawEv.vnSym = VnCharset.asciiToLexi[Int(rawKey)] ?? VnLexi.vnl_nonVnChar.rawValue
        let ret = processAppend(&rawEv)
        if undo {
            singleMode = false
            return 1
        }
        return ret
    }

    // MARK: - markChange & output

    private func markChange(_ pos: Int) {
        if pos < changePos {
            backs += changePos - pos
            changePos = pos
        }
    }

    private func writeOutput() {
        var s = ""
        if changePos >= 0 && changePos <= current {
            for i in changePos...current {
                let w = buffer[i]
                if w.vnSym != VnLexi.vnl_nonVnChar.rawValue {
                    var idx = w.vnSym
                    if w.tone != 0 { idx += w.tone * 2 }
                    if w.caps == 1 { idx -= 1 }
                    if let cp = VietKeyboardEngine.unicodeOfLexi(index: idx) {
                        s.append(Character(UnicodeScalar(cp) ?? " "))
                    }
                } else if let scalar = UnicodeScalar(w.keyCode) {
                    s.append(Character(scalar))
                }
            }
        }
        outString = s
        outputWritten = true
    }

    private static func unicodeOfLexi(index: Int) -> Int? {
        guard index >= 0 && index < VnTables.lexiUnicode.count else { return nil }
        let cp = VnTables.lexiUnicode[index]
        return cp >= 0 ? cp : nil
    }

    // MARK: - lookups

    private static func lookupVSeq3(_ v1: Int, _ v2: Int, _ v3: Int) -> VnVowelSeq {
        for (i, row) in vSeqList.enumerated() where row[3] == v1 && row[4] == v2 && row[5] == v3 {
            return VnVowelSeq(rawValue: i)!
        }
        return .vs_nil
    }

    static func lookupVSeq1(_ v1: Int) -> VnVowelSeq {
        lookupVSeq3(v1, VnLexi.vnl_nonVnChar.rawValue, VnLexi.vnl_nonVnChar.rawValue)
    }

    static func lookupVSeq2(_ v1: Int, _ v2: Int) -> VnVowelSeq {
        lookupVSeq3(v1, v2, VnLexi.vnl_nonVnChar.rawValue)
    }

    private static func lookupCSeq3(_ c1: Int, _ c2: Int, _ c3: Int) -> VnConSeq {
        for (i, row) in cSeqList.enumerated() where row[1] == c1 && row[2] == c2 && row[3] == c3 {
            return VnConSeq(rawValue: i)!
        }
        return .cs_nil
    }

    static func lookupCSeq1(_ c1: Int) -> VnConSeq {
        lookupCSeq3(c1, VnLexi.vnl_nonVnChar.rawValue, VnLexi.vnl_nonVnChar.rawValue)
    }

    static func lookupCSeq2(_ c1: Int, _ c2: Int) -> VnConSeq {
        lookupCSeq3(c1, c2, VnLexi.vnl_nonVnChar.rawValue)
    }

    static func isValidVSeq(_ vseq: Int) -> Bool {
        vseq >= 0 && vseq < vSeqList.count
    }

    private static func isValidCV(_ c: Int, _ v: Int) -> Bool {
        if c == VnConSeq.cs_nil.rawValue || v == VnVowelSeq.vs_nil.rawValue { return true }
        if c >= cSeqList.count || v >= vSeqList.count { return false }
        let vi = vSeqList[v]
        if c == VnConSeq.cs_gi.rawValue && vi[3] == VnLexi.vnl_i.rawValue { return false }
        if c == VnConSeq.cs_qu.rawValue &&
            (vi[3] == VnLexi.vnl_u.rawValue || vi[3] == VnLexi.vnl_uh.rawValue) { return false }
        if c == VnConSeq.cs_q.rawValue { return false }
        if c == VnConSeq.cs_k.rawValue {
            let kSeq: Set<Int> = [
                VnVowelSeq.vs_e.rawValue, VnVowelSeq.vs_i.rawValue, VnVowelSeq.vs_y.rawValue,
                VnVowelSeq.vs_er.rawValue, VnVowelSeq.vs_eo.rawValue, VnVowelSeq.vs_eu.rawValue,
                VnVowelSeq.vs_eru.rawValue, VnVowelSeq.vs_ia.rawValue, VnVowelSeq.vs_ie.rawValue,
                VnVowelSeq.vs_ier.rawValue, VnVowelSeq.vs_ieu.rawValue, VnVowelSeq.vs_ieru.rawValue,
            ]
            return kSeq.contains(v)
        }
        return true
    }

    private static func isValidVC(_ v: Int, _ c: Int) -> Bool {
        if v == VnVowelSeq.vs_nil.rawValue || c == VnConSeq.cs_nil.rawValue { return true }
        if v >= vSeqList.count || c >= cSeqList.count { return false }
        if vSeqList[v][2] == 0 { return false }
        if cSeqList[c][4] == 0 { return false }
        return vcPairs.contains([v, c])
    }

    private static func isValidCVC(_ c1: Int, _ v: Int, _ c2: Int) -> Bool {
        if v == VnVowelSeq.vs_nil.rawValue {
            return c1 == VnConSeq.cs_nil.rawValue || c2 != VnConSeq.cs_nil.rawValue
        }
        if c1 == VnConSeq.cs_nil.rawValue { return isValidVC(v, c2) }
        if c2 == VnConSeq.cs_nil.rawValue { return isValidCV(c1, v) }

        let okCV = isValidCV(c1, v)
        let okVC = isValidVC(v, c2)
        if okCV && okVC { return true }

        if !okVC {
            if c1 == VnConSeq.cs_qu.rawValue && v == VnVowelSeq.vs_y.rawValue &&
                (c2 == VnConSeq.cs_n.rawValue || c2 == VnConSeq.cs_nh.rawValue) { return true }
            if c1 == VnConSeq.cs_gi.rawValue &&
                (v == VnVowelSeq.vs_e.rawValue || v == VnVowelSeq.vs_er.rawValue) &&
                (c2 == VnConSeq.cs_n.rawValue || c2 == VnConSeq.cs_ng.rawValue) { return true }
        }
        return false
    }

    // MARK: - vị trí dấu thanh

    private func getTonePosition(_ vs: VnVowelSeq, _ terminated: Bool) -> Int {
        let info = VietKeyboardEngine.vSeqList[vs.rawValue]
        if info[0] == 1 { return 0 }
        if info[9] != -1 { return info[9] }  // roofPos
        if info[11] != -1 {                   // hookPos
            if vs == .vs_uhoh || vs == .vs_uhohi || vs == .vs_uhohu { return 1 }
            return info[11]
        }
        if info[0] == 3 { return 1 }
        if options.modernStyle && (vs == .vs_oa || vs == .vs_oe || vs == .vs_uy) { return 1 }
        return terminated ? 0 : 1
    }

    // MARK: - processTone (0..5)

    private func processTone(_ ev: inout UkKeyEvent) -> Int {
        if current < 0 || !options.vietKey { return processAppend(&ev) }

        // gi/gin: dấu áp lên nguyên âm "i" của gi
        if buffer[current].form == .cons &&
            (buffer[current].cseq == VnConSeq.cs_gi.rawValue || buffer[current].cseq == VnConSeq.cs_gin.rawValue) {
            let p = buffer[current].cseq == VnConSeq.cs_gi.rawValue ? current : current - 1
            guard p >= 0 else { return processAppend(&ev) }
            if buffer[p].tone == 0 && ev.tone == 0 { return processAppend(&ev) }
            markChange(p)
            if buffer[p].tone == ev.tone {
                buffer[p].tone = 0
                singleMode = false
                _ = processAppend(&ev)
                return 1
            }
            buffer[p].tone = ev.tone
            return 1
        }

        if buffer[current].vOffset < 0 { return processAppend(&ev) }

        let vEnd = current - buffer[current].vOffset
        if !VietKeyboardEngine.isValidVSeq(buffer[vEnd].vseq) { return processAppend(&ev) }
        let vs = VnVowelSeq(rawValue: buffer[vEnd].vseq)!
        let info = VietKeyboardEngine.vSeqList[vs.rawValue]
        if options.spellCheckEnabled && !options.freeMarking && info[1] == 0 {
            return processAppend(&ev)
        }

        if buffer[current].form == .vc || buffer[current].form == .cvc {
            let cs = buffer[current].cseq
            if (cs == VnConSeq.cs_c.rawValue || cs == VnConSeq.cs_ch.rawValue ||
                cs == VnConSeq.cs_p.rawValue || cs == VnConSeq.cs_t.rawValue) &&
                (ev.tone == 2 || ev.tone == 3 || ev.tone == 4) {
                return processAppend(&ev)   // c, ch, p, t không mang huyền/hỏi/ngã
            }
        }

        let lenRow = info[0] - 1
        let vStart = vEnd - lenRow
        let tonePos = vStart + getTonePosition(vs, vEnd == current)

        if buffer[tonePos].tone == 0 && ev.tone == 0 { return processAppend(&ev) }
        if buffer[tonePos].tone == ev.tone {
            markChange(tonePos)
            buffer[tonePos].tone = 0
            singleMode = false
            _ = processAppend(&ev)
            return 1
        }
        markChange(tonePos)
        buffer[tonePos].tone = ev.tone
        return 1
    }

    // MARK: - processRoof (phím 6)

    private func processRoof(_ ev: inout UkKeyEvent) -> Int {
        if !options.vietKey || current < 0 || buffer[current].vOffset < 0 { return processAppend(&ev) }

        let target: Int
        switch ev.action {
        case .roofA: target = VnLexi.vnl_ar.rawValue
        case .roofE: target = VnLexi.vnl_er.rawValue
        case .roofO: target = VnLexi.vnl_or.rawValue
        default: target = VnLexi.vnl_nonVnChar.rawValue
        }

        let vEnd = current - buffer[current].vOffset
        if !VietKeyboardEngine.isValidVSeq(buffer[vEnd].vseq) { return processAppend(&ev) }
        let vs = VnVowelSeq(rawValue: buffer[vEnd].vseq)!
        let vSeqInfo = VietKeyboardEngine.vSeqList[vs.rawValue]
        let vStart = vEnd - (vSeqInfo[0] - 1)
        let curTonePos = vStart + getTonePosition(vs, vEnd == current)
        let tone = buffer[curTonePos].tone

        var newVs = VnVowelSeq.vs_nil
        var roofRemoved = false
        var doubleChangeUO = false
        if vs == .vs_uho || vs == .vs_uhoh || vs == .vs_uhoi || vs == .vs_uhohi {
            newVs = VietKeyboardEngine.lookupVSeq3(VnLexi.vnl_u.rawValue, VnLexi.vnl_or.rawValue, vSeqInfo[5])
            doubleChangeUO = true
        } else {
            newVs = VnVowelSeq(rawValue: vSeqInfo[10])!
        }

        var pInfo = vSeqInfo
        if newVs == .vs_nil {
            if vSeqInfo[9] == -1 { return processAppend(&ev) }
            let curCh = buffer[vStart + vSeqInfo[9]].vnSym
            if target != VnLexi.vnl_nonVnChar.rawValue && curCh != target { return processAppend(&ev) }
            let newCh = curCh == VnLexi.vnl_ar.rawValue ? VnLexi.vnl_a.rawValue :
                curCh == VnLexi.vnl_er.rawValue ? VnLexi.vnl_e.rawValue : VnLexi.vnl_o.rawValue
            let varPos = vStart + vSeqInfo[9]
            if !options.freeMarking && varPos != current { return processAppend(&ev) }
            markChange(varPos)
            buffer[varPos].vnSym = newCh

            let recomputed = recomputeVSeq(vStart, vSeqInfo[0])
            pInfo = VietKeyboardEngine.vSeqList[recomputed.rawValue]
            roofRemoved = true
        } else {
            pInfo = VietKeyboardEngine.vSeqList[newVs.rawValue]
            if target != VnLexi.vnl_nonVnChar.rawValue && pInfo[3 + pInfo[9]] != target { return processAppend(&ev) }
            var c1 = VnConSeq.cs_nil.rawValue
            var c2 = VnConSeq.cs_nil.rawValue
            if buffer[current].c1Offset != -1 { c1 = buffer[current - buffer[current].c1Offset].cseq }
            if buffer[current].c2Offset != -1 { c2 = buffer[current - buffer[current].c2Offset].cseq }
            if !VietKeyboardEngine.isValidCVC(c1, newVs.rawValue, c2) { return processAppend(&ev) }
            let varPos = doubleChangeUO ? vStart : vStart + pInfo[9]
            if !options.freeMarking && varPos != current { return processAppend(&ev) }
            markChange(varPos)
            if doubleChangeUO {
                buffer[vStart].vnSym = VnLexi.vnl_u.rawValue
                buffer[vStart + 1].vnSym = VnLexi.vnl_or.rawValue
            } else {
                buffer[varPos].vnSym = pInfo[3 + pInfo[9]]
            }
        }

        for i in 0..<pInfo[0] { buffer[vStart + i].vseq = pInfo[6 + i] }

        if newVs != .vs_nil {
            let newTonePos = vStart + getTonePosition(newVs, vEnd == current)
            if curTonePos != newTonePos && tone != 0 {
                markChange(newTonePos)
                buffer[newTonePos].tone = tone
                markChange(curTonePos)
                buffer[curTonePos].tone = 0
            }
        }

        if roofRemoved {
            singleMode = false
            _ = processAppend(&ev)
        }
        return 1
    }

    private func recomputeVSeq(_ vStart: Int, _ len: Int) -> VnVowelSeq {
        switch len {
        case 3: return VietKeyboardEngine.lookupVSeq3(buffer[vStart].vnSym, buffer[vStart + 1].vnSym, buffer[vStart + 2].vnSym)
        case 2: return VietKeyboardEngine.lookupVSeq2(buffer[vStart].vnSym, buffer[vStart + 1].vnSym)
        default: return VietKeyboardEngine.lookupVSeq1(buffer[vStart].vnSym)
        }
    }

    // MARK: - processHook (phím 7, 8)

    private func processHook(_ ev: inout UkKeyEvent) -> Int {
        if !options.vietKey || current < 0 || buffer[current].vOffset < 0 { return processAppend(&ev) }

        let vEnd = current - buffer[current].vOffset
        if !VietKeyboardEngine.isValidVSeq(buffer[vEnd].vseq) { return processAppend(&ev) }
        let vs = VnVowelSeq(rawValue: buffer[vEnd].vseq)!
        let vSeqInfo = VietKeyboardEngine.vSeqList[vs.rawValue]
        let v = Array(vSeqInfo[3...5])

        if vSeqInfo[0] > 1 && ev.action != .bowl &&
            (v[0] == VnLexi.vnl_u.rawValue || v[0] == VnLexi.vnl_uh.rawValue) &&
            (v[1] == VnLexi.vnl_o.rawValue || v[1] == VnLexi.vnl_oh.rawValue || v[1] == VnLexi.vnl_or.rawValue) {
            return processHookWithUO(&ev)
        }

        let vStart = vEnd - (vSeqInfo[0] - 1)
        let curTonePos = vStart + getTonePosition(vs, vEnd == current)
        let tone = buffer[curTonePos].tone

        let newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
        if newVs == .vs_nil {
            if vSeqInfo[11] == -1 { return processAppend(&ev) }
            // móc/trăng đã có → undo
            let curCh = buffer[vStart + vSeqInfo[11]].vnSym
            let newCh = curCh == VnLexi.vnl_ab.rawValue ? VnLexi.vnl_a.rawValue :
                curCh == VnLexi.vnl_uh.rawValue ? VnLexi.vnl_u.rawValue : VnLexi.vnl_o.rawValue
            let varPos = vStart + vSeqInfo[11]
            if !options.freeMarking && varPos != current { return processAppend(&ev) }

            switch ev.action {
            case .hookU:
                if curCh != VnLexi.vnl_uh.rawValue { return processAppend(&ev) }
            case .hookO:
                if curCh != VnLexi.vnl_oh.rawValue { return processAppend(&ev) }
            case .bowl:
                if curCh != VnLexi.vnl_ab.rawValue { return processAppend(&ev) }
            default:
                if ev.action == .hookUO && curCh == VnLexi.vnl_ab.rawValue { return processAppend(&ev) }
            }

            markChange(varPos)
            buffer[varPos].vnSym = newCh
            let recomputed = recomputeVSeq(vStart, vSeqInfo[0])
            let pInfo = VietKeyboardEngine.vSeqList[recomputed.rawValue]
            for i in 0..<pInfo[0] { buffer[vStart + i].vseq = pInfo[6 + i] }

            let newTonePos = vStart + getTonePosition(recomputed, vEnd == current)
            if curTonePos != newTonePos && tone != 0 {
                markChange(newTonePos)
                buffer[newTonePos].tone = tone
                markChange(curTonePos)
                buffer[curTonePos].tone = 0
            }
            singleMode = false
            _ = processAppend(&ev)
            return 1
        } else {
            let pInfo = VietKeyboardEngine.vSeqList[newVs.rawValue]
            switch ev.action {
            case .hookU:
                if pInfo[3 + pInfo[11]] != VnLexi.vnl_uh.rawValue { return processAppend(&ev) }
            case .hookO:
                if pInfo[3 + pInfo[11]] != VnLexi.vnl_oh.rawValue { return processAppend(&ev) }
            case .bowl:
                if pInfo[3 + pInfo[11]] != VnLexi.vnl_ab.rawValue { return processAppend(&ev) }
            default:
                if ev.action == .hookUO && pInfo[3 + pInfo[11]] == VnLexi.vnl_ab.rawValue { return processAppend(&ev) }
            }
            var c1 = VnConSeq.cs_nil.rawValue
            var c2 = VnConSeq.cs_nil.rawValue
            if buffer[current].c1Offset != -1 { c1 = buffer[current - buffer[current].c1Offset].cseq }
            if buffer[current].c2Offset != -1 { c2 = buffer[current - buffer[current].c2Offset].cseq }
            if !VietKeyboardEngine.isValidCVC(c1, newVs.rawValue, c2) { return processAppend(&ev) }

            let varPos = vStart + pInfo[11]
            if !options.freeMarking && varPos != current { return processAppend(&ev) }
            markChange(varPos)
            buffer[varPos].vnSym = pInfo[3 + pInfo[11]]

            for i in 0..<pInfo[0] { buffer[vStart + i].vseq = pInfo[6 + i] }

            let newTonePos = vStart + getTonePosition(newVs, vEnd == current)
            if curTonePos != newTonePos && tone != 0 {
                markChange(newTonePos)
                buffer[newTonePos].tone = tone
                markChange(curTonePos)
                buffer[curTonePos].tone = 0
            }
            return 1
        }
    }

    // MARK: - processHookWithUO

    private func processHookWithUO(_ ev: inout UkKeyEvent) -> Int {
        var newVs: VnVowelSeq = .vs_nil
        var hookRemoved = false

        if !options.freeMarking && buffer[current].vOffset != 0 { return processAppend(&ev) }

        let vEnd = current - buffer[current].vOffset
        if !VietKeyboardEngine.isValidVSeq(buffer[vEnd].vseq) { return processAppend(&ev) }
        let vs = VnVowelSeq(rawValue: buffer[vEnd].vseq)!
        let vSeqInfo = VietKeyboardEngine.vSeqList[vs.rawValue]
        let vStart = vEnd - (vSeqInfo[0] - 1)
        let v = Array(vSeqInfo[3...5])
        let curTonePos = vStart + getTonePosition(vs, vEnd == current)
        let tone = buffer[curTonePos].tone

        switch ev.action {
        case .hookU:
            if v[0] == VnLexi.vnl_u.rawValue {
                newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
                markChange(vStart)
                buffer[vStart].vnSym = VnLexi.vnl_uh.rawValue
            } else {
                newVs = VietKeyboardEngine.lookupVSeq3(VnLexi.vnl_u.rawValue, VnLexi.vnl_o.rawValue, v[2])
                markChange(vStart)
                buffer[vStart].vnSym = VnLexi.vnl_u.rawValue
                buffer[vStart + 1].vnSym = VnLexi.vnl_o.rawValue
                hookRemoved = true
            }
        case .hookO:
            if v[1] == VnLexi.vnl_o.rawValue || v[1] == VnLexi.vnl_or.rawValue {
                if vEnd == current && vSeqInfo[0] == 2 && buffer[current].form == .cv &&
                    buffer[current - 2].cseq == VnConSeq.cs_th.rawValue {
                    newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
                    markChange(vStart + 1)
                    buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                } else {
                    newVs = VietKeyboardEngine.lookupVSeq3(VnLexi.vnl_uh.rawValue, VnLexi.vnl_oh.rawValue, v[2])
                    if v[0] == VnLexi.vnl_u.rawValue {
                        markChange(vStart)
                        buffer[vStart].vnSym = VnLexi.vnl_uh.rawValue
                        buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                    } else {
                        markChange(vStart + 1)
                        buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                    }
                }
            } else {
                newVs = VietKeyboardEngine.lookupVSeq3(VnLexi.vnl_u.rawValue, VnLexi.vnl_o.rawValue, v[2])
                if v[0] == VnLexi.vnl_uh.rawValue {
                    markChange(vStart)
                    buffer[vStart].vnSym = VnLexi.vnl_u.rawValue
                    buffer[vStart + 1].vnSym = VnLexi.vnl_o.rawValue
                } else {
                    markChange(vStart + 1)
                    buffer[vStart + 1].vnSym = VnLexi.vnl_o.rawValue
                }
                hookRemoved = true
            }
        default:
            if v[0] == VnLexi.vnl_u.rawValue {
                if v[1] == VnLexi.vnl_o.rawValue || v[1] == VnLexi.vnl_or.rawValue {
                    if (vs == .vs_uo || vs == .vs_uor) && vEnd == current &&
                        ((buffer[current].form == .cv &&
                          (buffer[current - 2].cseq == VnConSeq.cs_h.rawValue ||
                           buffer[current - 2].cseq == VnConSeq.cs_kh.rawValue ||
                           buffer[current - 2].cseq == VnConSeq.cs_th.rawValue)) ||
                         buffer[current].form == .vowel) {
                        newVs = .vs_uoh
                        markChange(vStart + 1)
                        buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                    } else {
                        newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
                        markChange(vStart)
                        buffer[vStart].vnSym = VnLexi.vnl_uh.rawValue
                        newVs = VnVowelSeq(rawValue: VietKeyboardEngine.vSeqList[newVs.rawValue][12])!
                        buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                    }
                } else {
                    newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
                    markChange(vStart)
                    buffer[vStart].vnSym = VnLexi.vnl_uh.rawValue
                }
            } else {
                if v[1] == VnLexi.vnl_o.rawValue {
                    newVs = VnVowelSeq(rawValue: vSeqInfo[12])!
                    markChange(vStart + 1)
                    buffer[vStart + 1].vnSym = VnLexi.vnl_oh.rawValue
                } else {
                    newVs = VietKeyboardEngine.lookupVSeq3(VnLexi.vnl_u.rawValue, VnLexi.vnl_o.rawValue, v[2])
                    markChange(vStart)
                    buffer[vStart].vnSym = VnLexi.vnl_u.rawValue
                    buffer[vStart + 1].vnSym = VnLexi.vnl_o.rawValue
                    hookRemoved = true
                }
            }
        }

        let pInfo = VietKeyboardEngine.vSeqList[newVs.rawValue]
        for i in 0..<pInfo[0] { buffer[vStart + i].vseq = pInfo[6 + i] }

        if newVs != .vs_nil {
            let newTonePos = vStart + getTonePosition(newVs, vEnd == current)
            if curTonePos != newTonePos && tone != 0 {
                markChange(newTonePos)
                buffer[newTonePos].tone = tone
                markChange(curTonePos)
                buffer[curTonePos].tone = 0
            }
        }
        if hookRemoved {
            singleMode = false
            _ = processAppend(&ev)
        }
        return 1
    }

    // MARK: - processDd (phím 9)

    private func processDd(_ ev: inout UkKeyEvent) -> Int {
        if !options.vietKey || current < 0 { return processAppend(&ev) }

        if buffer[current].form == .nonVn && buffer[current].vnSym == VnLexi.vnl_d.rawValue &&
            (current == 0 || buffer[current - 1].vnSym == VnLexi.vnl_nonVnChar.rawValue ||
                !VnCharset.isVowelLexi(buffer[current - 1].vnSym)) {
            singleMode = true
            markChange(current)
            buffer[current].cseq = VnConSeq.cs_dd.rawValue
            buffer[current].vnSym = VnLexi.vnl_dd.rawValue
            buffer[current].form = .cons
            buffer[current].c1Offset = 0
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            return 1
        }

        if buffer[current].c1Offset < 0 { return processAppend(&ev) }
        let pos = current - buffer[current].c1Offset
        if !options.freeMarking && pos != current { return processAppend(&ev) }

        if buffer[pos].cseq == VnConSeq.cs_d.rawValue {
            markChange(pos)
            buffer[pos].cseq = VnConSeq.cs_dd.rawValue
            buffer[pos].vnSym = VnLexi.vnl_dd.rawValue
            singleMode = true
            return 1
        }
        if buffer[pos].cseq == VnConSeq.cs_dd.rawValue {
            markChange(pos)
            buffer[pos].cseq = VnConSeq.cs_d.rawValue
            buffer[pos].vnSym = VnLexi.vnl_d.rawValue
            singleMode = false
            _ = processAppend(&ev)
            return 1
        }
        return processAppend(&ev)
    }

    // MARK: - processAppend

    private func processAppend(_ ev: inout UkKeyEvent) -> Int {
        switch ev.chType {
        case .reset:
            reset()
            return 0
        case .wordBreak:
            singleMode = false
            return processWordEnd(ev)
        case .nonVn:
            current += 1
            extendBuffer()
            buffer[current].form = .nonVn
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            buffer[current].keyCode = ev.keyCode
            buffer[current].vnSym = VnCharset.vnToLower(ev.vnSym)
            buffer[current].tone = 0
            buffer[current].caps = (buffer[current].vnSym != ev.vnSym) ? 1 : 0
            buffer[current].vseq = -1
            buffer[current].cseq = -1
            return 0
        case .vn:
            if VnCharset.isVowelLexi(ev.vnSym) {
                let lowerSym = VnCharset.vnToLower(ev.vnSym)
                let canSym = VnTables.lexiNoTone[lowerSym]
                // "qu" và "gi": u sau q, i sau g là phụ âm đầu
                if current >= 0 && buffer[current].form == .cons &&
                    ((buffer[current].cseq == VnConSeq.cs_q.rawValue && canSym == VnLexi.vnl_u.rawValue) ||
                     (buffer[current].cseq == VnConSeq.cs_g.rawValue && canSym == VnLexi.vnl_i.rawValue)) {
                    return appendConsonnant(&ev)
                }
                return appendVowel(&ev)
            }
            return appendConsonnant(&ev)
        }
    }

    private func processNoSpellCheck(_ ev: inout UkKeyEvent) -> Int {
        let entry = buffer[current]
        if VnCharset.isVowelLexi(entry.vnSym) {
            buffer[current].form = .vowel
            buffer[current].vOffset = 0
            buffer[current].vseq = VietKeyboardEngine.lookupVSeq1(entry.vnSym).rawValue
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
        } else {
            buffer[current].form = .cons
            buffer[current].c1Offset = 0
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            buffer[current].cseq = VietKeyboardEngine.lookupCSeq1(entry.vnSym).rawValue
        }
        if ev.action == .normal && ((ev.keyCode >= 97 && ev.keyCode <= 122) || (ev.keyCode >= 65 && ev.keyCode <= 90)) {
            return 0
        }
        markChange(current)
        return 1
    }

    private func processWordEnd(_ ev: UkKeyEvent) -> Int {
        current += 1
        extendBuffer()
        buffer[current] = WordInfo()
        buffer[current].form = .empty
        buffer[current].c1Offset = -1
        buffer[current].c2Offset = -1
        buffer[current].vOffset = -1
        buffer[current].keyCode = ev.keyCode
        buffer[current].vnSym = VnCharset.vnToLower(ev.vnSym)
        buffer[current].caps = (ev.vnSym != VnLexi.vnl_nonVnChar.rawValue && buffer[current].vnSym != ev.vnSym) ? 1 : 0
        return 0
    }

    // MARK: - appendVowel

    private func appendVowel(_ ev: inout UkKeyEvent) -> Int {
        var complexEvent = false

        current += 1
        extendBuffer()

        let lowerSym = VnCharset.vnToLower(ev.vnSym)
        let canSym = VnTables.lexiNoTone[lowerSym]

        buffer[current].vnSym = canSym
        buffer[current].caps = (lowerSym != ev.vnSym) ? 1 : 0
        buffer[current].tone = (lowerSym - canSym) / 2
        buffer[current].keyCode = ev.keyCode

        if current == 0 || !options.vietKey {
            buffer[current].form = .vowel
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
            buffer[current].vOffset = 0
            buffer[current].vseq = VietKeyboardEngine.lookupVSeq1(canSym).rawValue
            return 0
        }

        let vs = VnVowelSeq(rawValue: buffer[current - 1].vseq)!
        let prevForm = buffer[current - 1].form
        let prevIndex = current - 1
        var newVs: VnVowelSeq

        switch prevForm {
        case .empty:
            buffer[current].form = .vowel
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
            buffer[current].vOffset = 0
            buffer[current].vseq = VietKeyboardEngine.lookupVSeq1(canSym).rawValue

        case .nonVn, .cvc, .vc:
            buffer[current].form = .nonVn
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1

        case .vowel, .cv:
            guard VietKeyboardEngine.isValidVSeq(vs.rawValue) else {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
                return complexEvent ? 1 : 0
            }
            let vSeqInfoOld = VietKeyboardEngine.vSeqList[vs.rawValue]
            let prevTonePos = prevIndex - (vSeqInfoOld[0] - 1) + getTonePosition(vs, true)
            let tone = buffer[prevTonePos].tone

            var vsNow = vs
            // ưo / ưo+ + u/i → ưo+
            if (vsNow == .vs_uoh || vsNow == .vs_uho) &&
                (lowerSym == VnLexi.vnl_i.rawValue || lowerSym == VnLexi.vnl_u.rawValue) {
                if vsNow == .vs_uho {
                    markChange(prevIndex)
                    buffer[prevIndex].vnSym = VnLexi.vnl_oh.rawValue
                    buffer[prevIndex].vseq = VnVowelSeq.vs_uhoh.rawValue
                } else {
                    markChange(prevIndex - 1)
                    buffer[prevIndex - 1].vnSym = VnLexi.vnl_uh.rawValue
                    buffer[prevIndex - 1].vseq = VnVowelSeq.vs_uh.rawValue
                }
                vsNow = .vs_uhoh
                complexEvent = true
            }
            let vSeqInfo = VietKeyboardEngine.vSeqList[vsNow.rawValue]

            if lowerSym != canSym && tone != 0 {
                newVs = .vs_nil
            } else {
                if vSeqInfo[0] == 3 { newVs = .vs_nil }
                else if vSeqInfo[0] == 2 { newVs = VietKeyboardEngine.lookupVSeq3(vSeqInfo[3], vSeqInfo[4], canSym) }
                else { newVs = VietKeyboardEngine.lookupVSeq2(vSeqInfo[3], canSym) }
            }

            if newVs != .vs_nil && prevForm == .cv {
                let off = buffer[prevIndex].c1Offset
                if off >= 0 && prevIndex - off >= 0 {
                    let cs = buffer[prevIndex - off].cseq
                    if !VietKeyboardEngine.isValidCV(cs, newVs.rawValue) { newVs = .vs_nil }
                } else {
                    newVs = .vs_nil
                }
            }

            if newVs == .vs_nil {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
            } else {
                buffer[current].form = prevForm
                buffer[current].c1Offset = prevForm == .cv ? buffer[prevIndex].c1Offset + 1 : -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = 0
                buffer[current].vseq = newVs.rawValue
                buffer[current].tone = 0

                let newTone = (lowerSym - canSym) / 2
                if tone == 0 {
                    if newTone != 0 {
                        let tonePos = getTonePosition(newVs, true) + (prevIndex - vSeqInfo[0] + 1)
                        markChange(tonePos)
                        buffer[tonePos].tone = newTone
                        return 1
                    }
                } else {
                    let newTonePos = getTonePosition(newVs, true) + (prevIndex - vSeqInfo[0] + 1)
                    if newTonePos != prevTonePos {
                        markChange(prevTonePos)
                        buffer[prevTonePos].tone = 0
                        markChange(newTonePos)
                        buffer[newTonePos].tone = newTone != 0 ? newTone : tone
                        return 1
                    }
                    if newTone != 0 && newTone != tone {
                        markChange(prevTonePos)
                        buffer[prevTonePos].tone = newTone
                        return 1
                    }
                }
            }

        case .cons:
            newVs = VietKeyboardEngine.lookupVSeq1(canSym)
            let cs = buffer[prevIndex].cseq
            if !VietKeyboardEngine.isValidCV(cs, newVs.rawValue) {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
            } else {
                buffer[current].form = .cv
                buffer[current].c1Offset = 1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = 0
                buffer[current].vseq = newVs.rawValue

                if cs == VnConSeq.cs_gi.rawValue && buffer[prevIndex].tone != 0 {
                    if buffer[current].tone == 0 { buffer[current].tone = buffer[prevIndex].tone }
                    markChange(prevIndex)
                    buffer[prevIndex].tone = 0
                    return 1
                }
            }
        }

        return complexEvent ? 1 : 0
    }

    // MARK: - appendConsonnant

    private func appendConsonnant(_ ev: inout UkKeyEvent) -> Int {
        var complexEvent = false
        current += 1
        extendBuffer()

        let lowerSym = VnCharset.vnToLower(ev.vnSym)
        buffer[current].vnSym = lowerSym
        buffer[current].caps = (lowerSym != ev.vnSym) ? 1 : 0
        buffer[current].keyCode = ev.keyCode
        buffer[current].tone = 0

        if current == 0 || !options.vietKey {
            buffer[current].form = .cons
            buffer[current].c1Offset = 0
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            buffer[current].cseq = VietKeyboardEngine.lookupCSeq1(lowerSym).rawValue
            return 0
        }

        let prevForm = buffer[current - 1].form
        let prevIndex = current - 1

        switch prevForm {
        case .nonVn:
            buffer[current].form = .nonVn
            buffer[current].c1Offset = -1
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            return 0

        case .empty:
            buffer[current].form = .cons
            buffer[current].c1Offset = 0
            buffer[current].c2Offset = -1
            buffer[current].vOffset = -1
            buffer[current].cseq = VietKeyboardEngine.lookupCSeq1(lowerSym).rawValue
            return 0

        case .vowel, .cv:
            guard VietKeyboardEngine.isValidVSeq(buffer[prevIndex].vseq) else {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
                return 0
            }
            let vs = VnVowelSeq(rawValue: buffer[prevIndex].vseq)!
            var newVs = vs
            if vs == .vs_uoh || vs == .vs_uho { newVs = .vs_uhoh }

            var c1 = VnConSeq.cs_nil.rawValue
            if buffer[prevIndex].c1Offset != -1 {
                let off = buffer[prevIndex].c1Offset
                if prevIndex - off >= 0 {
                    c1 = buffer[prevIndex - off].cseq
                }
            }
            let newCs = VietKeyboardEngine.lookupCSeq1(lowerSym)
            let isValid = VietKeyboardEngine.isValidCVC(c1, newVs.rawValue, newCs.rawValue)

            if isValid {
                if vs == .vs_uho {
                    markChange(prevIndex)
                    buffer[prevIndex].vnSym = VnLexi.vnl_oh.rawValue
                    buffer[prevIndex].vseq = VnVowelSeq.vs_uhoh.rawValue
                    complexEvent = true
                } else if vs == .vs_uoh {
                    markChange(prevIndex - 1)
                    buffer[prevIndex - 1].vnSym = VnLexi.vnl_uh.rawValue
                    buffer[prevIndex - 1].vseq = VnVowelSeq.vs_uh.rawValue
                    buffer[prevIndex].vseq = VnVowelSeq.vs_uhoh.rawValue
                    complexEvent = true
                }

                if prevForm == .vowel {
                    buffer[current].form = .vc
                    buffer[current].c1Offset = -1
                    buffer[current].c2Offset = 0
                    buffer[current].vOffset = 1
                } else {
                    buffer[current].form = .cvc
                    buffer[current].c1Offset = buffer[prevIndex].c1Offset + 1
                    buffer[current].c2Offset = 0
                    buffer[current].vOffset = 1
                }
                buffer[current].cseq = newCs.rawValue

                let vSeqOld = VietKeyboardEngine.vSeqList[vs.rawValue]
                let oldIdx = prevIndex - (vSeqOld[0] - 1) + getTonePosition(vs, true)
                if buffer[oldIdx].tone != 0 {
                    let vSeqNew = VietKeyboardEngine.vSeqList[newVs.rawValue]
                    let newIdx = prevIndex - (vSeqNew[0] - 1) + getTonePosition(newVs, false)
                    if newIdx != oldIdx {
                        markChange(newIdx)
                        buffer[newIdx].tone = buffer[oldIdx].tone
                        markChange(oldIdx)
                        buffer[oldIdx].tone = 0
                        return 1
                    }
                }
            } else {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
            }
            return complexEvent ? 1 : 0

        case .cons, .vc, .cvc:
            let cs = buffer[prevIndex].cseq
            var newCs: VnConSeq
            if cs < 0 || cs >= VietKeyboardEngine.cSeqList.count {
                newCs = .cs_nil
            } else {
                let cSeqInfo = VietKeyboardEngine.cSeqList[cs]
                if cSeqInfo[0] == 3 { newCs = .cs_nil }
                else if cSeqInfo[0] == 2 {
                    newCs = VietKeyboardEngine.lookupCSeq3(cSeqInfo[1], cSeqInfo[2], lowerSym)
                } else {
                    newCs = VietKeyboardEngine.lookupCSeq2(cSeqInfo[1], lowerSym)
                }
            }

            if newCs != .cs_nil && (prevForm == .vc || prevForm == .cvc) {
                var c1 = VnConSeq.cs_nil.rawValue
                if buffer[prevIndex].c1Offset != -1 {
                    c1 = buffer[prevIndex - buffer[prevIndex].c1Offset].cseq
                }
                let vIdx = prevIndex - buffer[prevIndex].vOffset
                if vIdx >= 0 {
                    let vsRaw = buffer[vIdx].vseq
                    if !VietKeyboardEngine.isValidVSeq(vsRaw) || !VietKeyboardEngine.isValidCVC(c1, vsRaw, newCs.rawValue) {
                        newCs = .cs_nil
                    }
                } else {
                    newCs = .cs_nil
                }
            }

            if newCs == .cs_nil {
                buffer[current].form = .nonVn
                buffer[current].c1Offset = -1
                buffer[current].c2Offset = -1
                buffer[current].vOffset = -1
            } else {
                if prevForm == .cons {
                    buffer[current].form = .cons
                    buffer[current].c1Offset = 0
                    buffer[current].c2Offset = -1
                    buffer[current].vOffset = -1
                } else if prevForm == .vc {
                    buffer[current].form = .vc
                    buffer[current].c1Offset = -1
                    buffer[current].c2Offset = 0
                    buffer[current].vOffset = buffer[prevIndex].vOffset + 1
                } else {
                    buffer[current].form = .cvc
                    buffer[current].c1Offset = buffer[prevIndex].c1Offset + 1
                    buffer[current].c2Offset = 0
                    buffer[current].vOffset = buffer[prevIndex].vOffset + 1
                }
                buffer[current].cseq = newCs.rawValue
            }
            return 0
        }
    }

    // MARK: - buffer management

    /// như prepareBuffer của ukengine: chừa đủ 10 ô
    private func prepareBuffer() {
        if current >= 0 && current + 10 >= bufferCapacity {
            var rid = current / 2
            while rid < current && buffer[rid].form != .empty { rid += 1 }
            if rid == current {
                reset()
            } else {
                rid += 1
                let keep = Array(buffer[rid...current])
                buffer = keep
                current -= rid
            }
        }
    }

    private func extendBuffer() {
        prepareBuffer()
        if current >= buffer.count {
            let needed = current + 1 - buffer.count
            for _ in 0..<max(needed, 10) {
                buffer.append(WordInfo())
            }
        }
    }
}
