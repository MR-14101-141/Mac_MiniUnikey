//
//  ParityTests.swift
//  MiniUnikeyTests
//
//  Kiểm chứng Swift engine khớp 100% với engine UniKey gốc (C++) trên
//  corpus vi sai sinh từ /tmp/ref_engine (nguồn fcitx5-unikey).
//
import XCTest
import MiniUnikeyEngine

final class ParityTests: XCTestCase {
    private struct Case {
        let input: String
        let expected: String
        let spellCheck: Bool
        let freeMarking: Bool
        let modern: Bool
        let method: VnInputMethod
    }

    private func loadCorpus(_ resource: String) -> [Case] {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "jsonl"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Không đọc được \(resource).jsonl")
            return []
        }
        var cases: [Case] = []
        for line in text.split(separator: "\n") {
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let input = obj["in"] as? String,
                  let out = obj["out"] as? String else { continue }
            let methodName = obj["method"] as? String ?? "vni"
            cases.append(Case(
                input: input,
                expected: out,
                spellCheck: obj["spell"] as? Bool ?? true,
                freeMarking: obj["free"] as? Bool ?? true,
                modern: obj["modern"] as? Bool ?? false,
                method: methodName == "telex" ? .telex :
                                      methodName == "simple" ? .simpleTelex : .vni))
        }
        return cases
    }

    /// Chạy chuỗi phím giống đúng cách ref_engine tính hiển thị.
    private func simulate(_ input: String, spell: Bool = true, free: Bool = true, modern: Bool = false, method: VnInputMethod = .vni) -> String {
        let trace = ProcessInfo.processInfo.environment["MINI_TRACE"] == "1"
        if trace {
            FileHandle.standardError.write(Data("[simulate] in=\(input) method=\(method)\n".utf8))
        }
        let engine = VietKeyboardEngine()
        engine.options.vietKey = true
        engine.options.spellCheckEnabled = spell
        engine.options.freeMarking = free
        engine.options.modernStyle = modern
        engine.method = method
        engine.reset()

        var display: String = ""

        func apply(_ r: (backs: Int, output: String, changed: Bool), original: Character? = nil) {
            guard r.changed else { return }
            if r.backs > 0 {
                if display.count >= r.backs {
                    display.removeLast(r.backs)
                } else {
                    display.removeAll()
                }
            }
            if !r.output.isEmpty {
                display.append(r.output)
            } else if let original = original {
                display.append(original)
            }
        }

        for scalar in input.unicodeScalars {
            let perKeyTrace = ProcessInfo.processInfo.environment["MINI_PER_KEY"] == "1"
            if perKeyTrace {
                FileHandle.standardError.write(Data(String(format: "[key %02X] display=\"%@\"\n", scalar.value, display).utf8))
            }
            if scalar.value == 8 {
                apply(engine.processBackspace())
            } else if scalar.value == 32 {
                let r = engine.process(0)   // word break vô hình như fcitx
                apply(r, original: " ")
                if !r.changed { display.append(" ") }
            } else {
                let ch = Character(scalar)
                let r = engine.process(scalar.value)
                if r.changed {
                    apply(r, original: ch)
                } else {
                    display.append(ch)
                }
            }
        }
        return display
    }

    func testParityWithUniKeyEngine() {
        let cases = loadCorpus("corpus")
        XCTAssertFalse(cases.isEmpty, "corpus rỗng")
        let stopFast = ProcessInfo.processInfo.environment["MINI_STOP_FAST"] == "1"
        var failures: [String] = []
        for (idx, c) in cases.enumerated() {
            let got = simulate(c.input, spell: c.spellCheck, free: c.freeMarking, modern: c.modern, method: c.method)
            if got != c.expected {
                let msg = "idx=\(idx) in=\(c.input.debugDescription) expect=\(c.expected.debugDescription) got=\(got.debugDescription)"
                failures.append(msg)
                if stopFast { break }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Sai khác engine gốc (\(failures.count)/\(cases.count) || mẫu: \(failures.prefix(10).joined(separator: " | ")))")
    }

    func testParityTelexWithUniKeyEngine() {
        let cases = loadCorpus("corpus_telex")
        XCTAssertFalse(cases.isEmpty, "corpus_telex rỗng")
        var failures: [String] = []
        for (idx, c) in cases.enumerated() {
            let got = simulate(c.input, spell: c.spellCheck, free: c.freeMarking, modern: c.modern, method: c.method)
            if got != c.expected {
                let msg = "idx=\(idx) in=\(c.input.debugDescription) expect=\(c.expected.debugDescription) got=\(got.debugDescription)"
                failures.append(msg)
                if ProcessInfo.processInfo.environment["MINI_STOP_FAST"] == "1" { break }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Telex sai khác engine gốc (\(failures.count)/\(cases.count) || mẫu: \(failures.prefix(10).joined(separator: " | ")))")
    }

    func testCommonVniCases() {
        XCTAssertEqual(simulate("nguoi7"), "ngươi")     // 7 = móc ư/ơ (không có dấu thanh)
        XCTAssertEqual(simulate("tuan2"), "tuàn")       // C engine: dấu (plain à), sẽ thành "tuần" nhờ số 6
        XCTAssertEqual(simulate("tuan62"), "tuần")
        XCTAssertEqual(simulate("khoan2"), "khoàn")
        XCTAssertEqual(simulate("ngay mai"), "ngay mai")      // không bấm số → giữ nguyên
        XCTAssertEqual(simulate("ngay2 mai"), "ngày mai")     // 2 = huyền
    }

    func testCommonTelexCases() {
        XCTAssertEqual(simulate("w", method: .telex), "ư")             // w = ư (UniKey telex chuẩn)
        XCTAssertEqual(simulate("cw", method: .telex), "cư")
        XCTAssertEqual(simulate("cww", method: .telex), "cw")          // w chữ 2 = undo → literal w
        XCTAssertEqual(simulate("aa", method: .telex), "â")
        XCTAssertEqual(simulate("dd", method: .telex), "đ")
        XCTAssertEqual(simulate("saas", method: .telex), "sấ")
        XCTAssertEqual(simulate("uyel", method: .telex), "uyel")       // từ vô nghĩa → literal (spell check)
    }
}
