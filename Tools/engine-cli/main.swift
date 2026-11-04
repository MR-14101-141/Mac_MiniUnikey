import MiniUnikeyEngine
// engine-cli: All test debug of the engine (analyze each key)
// Usage: engine-cli [--vni|--telex|--simple] keystring
import Foundation

var method: VnInputMethod = .vni
var text = ""
for a in CommandLine.arguments.dropFirst() {
    switch a {
    case "--vni": method = .vni
    case "--telex": method = .telex
    case "--simple": method = .simpleTelex
    default: text = a.replacingOccurrences(of: "\\b", with: "\u{0008}")
    }
}

let engine = VietKeyboardEngine()
engine.options.vietKey = true
engine.options.spellCheckEnabled = true
engine.options.freeMarking = true
engine.method = method
engine.reset()

var display = ""
func apply(_ r: (backs: Int, output: String, changed: Bool), original ch: Character) {
    guard r.changed else { display.append(ch); return }
    if r.backs > 0 {
        for _ in 0..<r.backs { _ = display.popLast() }
    }
    if !r.output.isEmpty {
        display.append(r.output)
    } else if r.backs > 0 {
        display.append(ch)
    }
}
for sc in text.unicodeScalars {
    let ch = Character(sc)
    let r = (sc.value == 8) ? engine.processBackspace() : engine.process(sc.value)
    print("key=\(ch) backs=\(r.backs) out=\"\(r.output)\" changed=\(r.changed)")
    apply(r, original: ch)
}
print("DISPLAY = \(display)")
