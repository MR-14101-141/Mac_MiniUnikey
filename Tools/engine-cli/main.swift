import MiniUnikeyEngine
// engine-cli: All test debug of the engine (analyze each key)
// Usage: engine-cli [--vni|--telex|--simple] keystring
//        engine-cli --batch [--vni|--telex|--simple] [--free] [--nospell] [--modern] < lines
import Foundation

var method: VnInputMethod = .vni
var text = ""
var batch = false
var freeMarking = true
var spellCheck = true
var modern = false
for a in CommandLine.arguments.dropFirst() {
    switch a {
    case "--vni": method = .vni
    case "--telex": method = .telex
    case "--simple": method = .simpleTelex
    case "--batch": batch = true
    case "--free": freeMarking = true
    case "--nofree": freeMarking = false
    case "--nospell": spellCheck = false
    case "--modern": modern = true
    default: text = a.replacingOccurrences(of: "\\b", with: "\u{0008}")
    }
}

let engine = VietKeyboardEngine()
engine.options.vietKey = true
engine.options.spellCheckEnabled = spellCheck
engine.options.freeMarking = freeMarking
engine.options.modernStyle = modern
engine.method = method
engine.reset()

var display = ""
func apply(_ r: (backs: Int, output: String, changed: Bool), original ch: Character? = nil) {
    guard r.changed else { return }
    if r.backs > 0 {
        for _ in 0..<r.backs { _ = display.popLast() }
    }
    if !r.output.isEmpty {
        display.append(r.output)
    } else if let ch = ch {
        display.append(ch)
    }
}

func runKeys(_ keys: String) {
    engine.reset()
    display = ""
    for sc in keys.unicodeScalars {
        let ch = Character(sc)
        if sc.value == 8 {
            apply(engine.processBackspace())
        } else if sc.value == 32 {
            let r = engine.process(0)   // word break vô hình như fcitx
            if r.changed {
                apply(r, original: " ")
            } else {
                display.append(" ")
            }
        } else {
            let r = engine.process(sc.value)
            if r.changed {
                apply(r, original: ch)
            } else {
                display.append(ch)
            }
        }
    }
}

if batch {
    while let line = readLine(strippingNewline: true) {
        runKeys(line)
        print(display)
    }
} else {
    display = ""
    for sc in text.unicodeScalars {
        let ch = Character(sc)
        let r = (sc.value == 8) ? engine.processBackspace() : engine.process(sc.value)
        print("key=\(ch) backs=\(r.backs) out=\"\(r.output)\" changed=\(r.changed)")
        if sc.value == 8 {
            apply(r)
        } else if r.changed {
            apply(r, original: ch)
        } else {
            display.append(ch)
        }
    }
    print("DISPLAY = \(display)")
}
