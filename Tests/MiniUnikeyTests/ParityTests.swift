//
//  ParityTests.swift
//  MiniUnikeyTests
//
//  Kiểm chứng Swift engine khớp 100% với engine UniKey gốc (C++) trên
//  corpus vi sai sinh từ /tmp/ref_engine (nguồn fcitx5-unikey).
//
import XCTest
@testable import MiniUnikey

final class ParityTests: XCTestCase {
    private struct Case {
        let input: String
        let expected: String
        let spellCheck: Bool
        let freeMarking: Bool
        let modern: Bool
    }

    private func loadCorpus() -> [Case] {
        guard let url = Bundle.module.url(forResource: "corpus", withExtension: "jsonl"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            XCTFail("Không đọc được corpus.jsonl")
            return []
        }
        var cases: [Case] = []
        for line in text.split(separator: "\n") {
            guard !line.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let input = obj["in"] as? String,
                  let out = obj["out"] as? String else { continue }
            cases.append(Case(
                input: input,
                expected: out,
                spellCheck: obj["spell"] as? Bool ?? true,
                freeMarking: obj["free"] as? Bool ?? true,
                modern: obj["modern"] as? Bool ?? false))
        }
        return cases
    }

    /// Chạy chuỗi phím giống đúng cách ref_engine tính hiển thị.
    private func simulate(_ input: String, spell: Bool, free: Bool, modern: Bool) -> String {
        let trace = ProcessInfo.processInfo.environment["MINI_TRACE"] == "1"
        if trace {
            FileHandle.standardError.write(Data("[simulate] in=\(input)\n".utf8))
        }
        let engine = VietKeyboardEngine()
        engine.options.vietKey = true
        engine.options.spellCheckEnabled = spell
        engine.options.freeMarking = free
        engine.options.modernStyle = modern
        engine.reset()

        var display: String = ""

        func apply(_ r: (backs: Int, output: String, changed: Bool)) {
            if r.changed && r.backs > 0 {
                if display.count >= r.backs {
                    display.removeLast(r.backs)
                } else {
                    display.removeAll()
                }
                if !r.output.isEmpty { display.append(r.output) }
            }
        }

        for scalar in input.unicodeScalars {
            if scalar.value == 8 {
                apply(engine.processBackspace())
            } else if scalar.value == 32 {
                let r = engine.process(0)   // word break vô hình như fcitx
                apply(r)
                display.append(" ")
            } else {
                let r = engine.process(scalar.value)
                if r.changed && r.backs > 0 {
                    apply(r)
                    if r.output.isEmpty {
                        display.append(String(Character(scalar)))
                    }
                } else {
                    display.append(String(Character(scalar)))
                }
            }
        }
        return display
    }

    func testParityWithUniKeyEngine() {
        let cases = loadCorpus()
        XCTAssertFalse(cases.isEmpty, "corpus rỗng")
        let trace = ProcessInfo.processInfo.environment["MINI_TRACE"] == "1"
        let stopFast = ProcessInfo.processInfo.environment["MINI_STOP_FAST"] == "1"
        var failures: [String] = []
        for (idx, c) in cases.enumerated() {
            if trace && idx % 100 == 0 {
                FileHandle.standardError.write(Data("[trace] idx=\(idx) in=\(c.input)\n".utf8))
            }
            let got = simulate(c.input, spell: c.spellCheck, free: c.freeMarking, modern: c.modern)
            if got != c.expected {
                let msg = "idx=\(idx) in=\(c.input.debugDescription) expect=\(c.expected.debugDescription) got=\(got.debugDescription)"
                failures.append(msg)
                if stopFast { break }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Sai khác engine gốc (\(failures.count)/\(cases.count)|| mẫu: \(failures.prefix(12).joined(separator: " | ")))")
    }

    func testCommonVniCases() {
        let engine = VietKeyboardEngine()
        engine.options.vietKey = true
        engine.options.spellCheckEnabled = true
        engine.options.freeMarking = true
        engine.options.modernStyle = false

        func type(_ s: String) -> String {
            engine.reset()
            var display = ""
            for scalar in s.unicodeScalars {
                if scalar.value == 8 {
                    let r = engine.processBackspace()
                    if r.changed && r.backs > 0 { display.removeLast(min(r.backs, display.count)); if !r.output.isEmpty { display += r.output } }
                } else if scalar.value == 32 {
                    _ = engine.process(0)
                    display += " "
                } else {
                    let r = engine.process(scalar.value)
                    if r.changed && r.backs > 0 {
                        display.removeLast(min(r.backs, display.count))
                        if !r.output.isEmpty { display += r.output } else { display += String(Character(scalar)) }
                    } else {
                        display += String(Character(scalar))
                    }
                }
            }
            return display
        }

        XCTAssertEqual(type("nguoi7"), "ngươi")     // 7 = móc ư/ơ (không có dấu thanh)
        XCTAssertEqual(type("tuan2"), "tuàn")       // C engine: dấu (plain à), sẽ thành "tuần" nhờ số 6
        XCTAssertEqual(type("tuan62"), "tuần")
        XCTAssertEqual(type("khoan2"), "khoàn")
        XCTAssertEqual(type("ngay mai"), "ngay mai")      // không bấm số → giữ nguyên
        XCTAssertEqual(type("ngay2 mai"), "ngày mai")     // 2 = huyền
    }
}
