#!/usr/bin/env python3
"""Exercise the real paste lifecycle with an in-memory OS; no desktop input or API calls."""
from pathlib import Path
import subprocess
root=Path(__file__).resolve().parent.parent
out=root/'.build/paste-flow'; out.mkdir(parents=True,exist_ok=True)
source=(root/'Sources/EdgelessType/Paster.swift').read_text().replace('import AppKit','import Foundation\nimport CoreFoundation').replace('import EdgelessTypeCore','')
# Compile the real lifecycle and event scheduling against an in-memory OS.
# No event is posted to macOS; no application or real clipboard is accessed.
source=source.replace('edgelesstype-paste-diagnostic.json','edgelesstype-test-paste-diagnostic.json')
source=source[:source.index('    private static func attribute(')]+'''
    private static func accessibilityRecoveryKind(for pid: pid_t) -> AccessibilityRecoveryKind? {
        Env.chrome ? .chrome : (Env.electron ? .electron : nil)
    }
    private static func requestAccessibilityExposure(in pid: pid_t, kind: AccessibilityRecoveryKind) {
        if kind == .electron { Env.electronRequests += 1 } else { Env.chromeRequests += 1 }
        if Env.chromeRecoveryWorks {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { Env.readable = true }
        }
    }
    private static func pasteTarget(in pid: pid_t) -> AXUIElement? { Env.readable ? Env.editor : nil }
    static func snapshot(_ element: AXUIElement) -> PasteSnapshot { PasteSnapshot(value: Env.readable ? element.value : nil, selection: nil) }
}
'''
shim=r'''
import Foundation
import CoreFoundation
final class AXUIElement: NSObject { var value = "" }
final class NSPasteboard {
 static let general = NSPasteboard()
 var changeCount = 0
 var text = "previous clipboard"
}
final class ClipboardLease {
 var backup = ""
 func publish(_ text: String) -> Bool { backup = NSPasteboard.general.text; NSPasteboard.general.text = text; NSPasteboard.general.changeCount += 1; return true }
 @discardableResult func finish(confirmed: Bool) -> Bool { guard confirmed else { return false }; NSPasteboard.general.text = backup; NSPasteboard.general.changeCount += 1; Env.restores += 1; return true }
 func discard() {}
}
enum CorrectionRejection: String { case fixture; var explanation: String { "fixture" } }
// Mirror every case OutputPolicy names directly; keep in sync with CloudProvider.swift.
enum CloudError: String { case fixture, offline, network, timeout, quota; var errorDescription: String? { "fixture" } }
struct SpeechContent { static func hasWords(_ text: String) -> Bool { !text.isEmpty } }
func AXIsProcessTrusted() -> Bool { true }
final class NSRunningApplication {
 enum Activation { case activateIgnoringOtherApps }
 var bundleIdentifier: String? { Env.codex ? "com.openai.codex" : (Env.grokBot ? "com.anysphere.sand" : (Env.chrome ? "com.google.Chrome" : "fixture")) }
 let processIdentifier: pid_t
 init?(processIdentifier: pid_t) { self.processIdentifier = processIdentifier }
 func activate(options: [Activation]) {}
}
final class NSWorkspace {
 static let shared = NSWorkspace()
 var frontmostApplication = NSRunningApplication(processIdentifier: 123)
}
final class CGEventSource {
 enum State { case privateState }
 init?(stateID: State) {}
}
struct CGEventFlags: OptionSet { let rawValue: Int; static let maskCommand = CGEventFlags(rawValue: 1) }
final class CGEvent {
 enum Field { case eventSourceUserData }
 let key: Int; let down: Bool
 var flags: CGEventFlags = []
 init?(keyboardEventSource: CGEventSource, virtualKey: Int, keyDown: Bool) { key = virtualKey; down = keyDown }
 func setIntegerValueField(_ field: Field, value: Int) {}
 func postToPid(_ pid: pid_t) {
  if key == 9 && down { Env.posts += 1; if Env.insert { Env.editor.value += NSPasteboard.general.text } }
 }
}
enum Env {
 static var editor = AXUIElement()
 static var chrome = false
 static var chromeRequests = 0
 static var chromeRecoveryWorks = false
 static var electron = false
 static var electronRequests = 0
 static var codex = false
 static var grokBot = false
 static var readable = true
 static var insert = true
 static var posts = 0
 static var restores = 0
 static func reset() { chrome = false; chromeRequests = 0; electron = false; electronRequests = 0; chromeRecoveryWorks = false; codex = false; grokBot = false; editor = AXUIElement(); readable = true; insert = true; posts = 0; restores = 0; NSPasteboard.general.text = "previous clipboard"; NSPasteboard.general.changeCount += 1 }
}
func tick(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
// Delayed AX recovery depends on timer drift; slow CI runners need the full production window.
func tick(upTo seconds: Double, until done: () -> Bool) {
 let end = Date().addingTimeInterval(seconds)
 while !done() && Date() < end { RunLoop.current.run(until: min(end, Date().addingTimeInterval(0.05))) }
}
func check(_ value: @autoclosure () -> Bool, _ name: String) { precondition(value(), name); print("PASS \(name)") }
'''
tests=r'''
@main struct Tests {
 static func main() {
  Env.reset()
  do { let p=Paster(); var hidden=false; p.onDismiss={hidden=true}; p.offer("fixture",into:123); tick(0.35)
   check(Env.posts==1 && Env.editor.value=="fixture" && hidden && !p.isOffering && Env.restores==1,"automatic insertion once and verified dismissal") }
  Env.reset(); Env.readable=false
  do { let p=Paster(); var hidden=false; p.onDismiss={hidden=true}; p.offer("fixture",into:nil)
   check(p.notePasteKey(controlOnly:true,fromUs:false),"manual Ctrl+V accepted")
   check(p.notePasteKey(controlOnly:true,fromUs:false),"queued repeat consumed")
   tick(0.2)
   check(Env.posts==1 && hidden && !p.isOffering && Env.restores==0 && NSPasteboard.general.text=="fixture","opaque manual paste dismisses once and retains text") }
  Env.reset()
  do { let p=Paster(); var hidden=false; p.onDismiss={hidden=true}; p.offer("fixture",into:123); tick(0.12)
   check(p.notePasteKey(controlOnly:false,fromUs:false),"manual recovery before readback timer accepted")
   tick(0.2); check(Env.posts==1 && hidden && Env.editor.value=="fixture","already inserted automatic text is not pasted twice") }
  Env.reset(); Env.insert=false
  do { let p=Paster(); p.offer("fixture",into:123)
   check(p.notePasteKey(controlOnly:false,fromUs:false),"manual chord during delivery consumed")
   tick(0.25); check(Env.posts==1 && p.isOffering && Env.restores==0,"unchanged editor never confirms automatic insertion"); p.cancelOffer() }
  Env.reset()
  do { let p=Paster(); p.offer("fixture",into:nil); NSPasteboard.general.text="new user clipboard"; NSPasteboard.general.changeCount += 1
   check(!p.notePasteKey(controlOnly:false,fromUs:false) && Env.posts==0,"new clipboard is not intercepted"); p.cancelOffer() }
  Env.reset()
  do { let p=Paster(); var hides=0; p.onDismiss={hides += 1}; p.offer("old",into:123); p.cancelOffer(); p.offer("new",into:nil); tick(0.25)
   check(hides==0 && p.isOffering && NSPasteboard.general.text=="new","cancelled delivery cannot dismiss next offer"); p.cancelOffer() }
  Env.reset(); Env.readable=false; Env.codex=true
  do { let p=Paster(); var hidden=false; p.onDismiss={hidden=true}; p.offer("fixture",into:123); tick(0.25)
   check(Env.posts==1 && Env.editor.value=="fixture" && hidden && !p.isOffering && Env.restores==0 && NSPasteboard.general.text=="fixture","Codex without AX focus auto-pastes once, closes preview, retains clipboard") }
  Env.reset(); Env.readable=false; Env.grokBot=true
  do { let p=Paster(); var hidden=false; p.onDismiss={hidden=true}; p.offer("fixture",into:123); tick(0.25)
   check(Env.posts==1 && Env.editor.value=="fixture" && hidden && !p.isOffering && !p.lastInsertionConfirmed && Env.restores==0 && NSPasteboard.general.text=="fixture","Grok Bot without AX focus pastes once, dismisses, and retains unconfirmed clipboard") }
  Env.reset(); Env.readable=false; Env.grokBot=true
  do { let p=Paster(); p.offer("fixture",into:456); tick(0.15)
   check(Env.posts==0,"Grok Bot fallback never targets a background process"); p.cancelOffer() }
  Env.reset(); Env.readable=false
  do { let p=Paster(); p.offer("fixture",into:123); tick(0.15)
   check(Env.posts==0 && p.isOffering,"unknown opaque apps do not auto-paste"); p.cancelOffer() }
  Env.reset(); Env.readable=false; Env.codex=true
  do { let p=Paster(); p.offer("fixture",into:456); tick(0.15)
   check(Env.posts==0,"opaque fallback never posts to a background target"); p.cancelOffer() }
  Env.reset()
  do { let p=Paster(); p.offer("简体测试",into:123); tick(0.3)
   check(Env.editor.value=="簡體測試" && Env.posts==1,"final paste gate converts Simplified output before publishing") }
  Env.reset()
  do { let p=Paster(); p.offer("。",into:123,acceptModelText:true); tick(0.3)
   check(Env.editor.value=="" && Env.posts==0,"period-only final output is not pasted") }
  Env.reset()
  do { let p=Paster(); p.offer("Hello. 中文。",into:123,acceptModelText:true); tick(0.3)
   check(Env.editor.value=="Hello. 中文" && Env.posts==1,"paste removes final period without changing internal punctuation") }
  Env.reset(); Env.chrome=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(0.35)
   check(Env.chromeRequests==0 && Env.posts==1 && !p.isOffering,"Ready Chrome editor pastes without accessibility recovery") }
  Env.reset(); Env.chrome=true; Env.readable=false; Env.chromeRecoveryWorks=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(upTo:3.4) { Env.posts==1 && p.lastInsertionConfirmed && !p.isOffering }
   check(Env.chromeRequests==1 && Env.posts==1 && p.lastInsertionConfirmed && !p.isOffering,"Chrome delayed accessibility resolves before one verified paste") }
  Env.reset(); Env.chrome=true; Env.readable=false
  do { let p=Paster(); p.offer("fixture",into:123); tick(3.4)
   check(Env.chromeRequests==1 && Env.posts==0 && p.isOffering,"Chrome inaccessible field never receives a blind paste"); p.cancelOffer() }
  Env.reset(); Env.chrome=true; Env.readable=false; Env.chromeRecoveryWorks=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(0.1); p.cancelOffer(); tick(2.4)
   check(Env.posts==0,"Cancelled Chrome recovery never pastes late") }
  Env.reset(); Env.chrome=true; Env.readable=false; Env.chromeRecoveryWorks=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(0.1)
   _=p.notePasteKey(controlOnly:false,fromUs:false); tick(2.5)
   check(Env.posts==1 && !p.isOffering,"Manual paste during Chrome recovery prevents later duplicate paste") }
  Env.reset(); Env.chrome=true; Env.readable=false
  do { let p=Paster(); p.offer("fixture",into:456); tick(0.2)
   check(Env.chromeRequests==0 && Env.posts==0,"Background Chrome is never prepared or pasted"); p.cancelOffer() }
  Env.reset(); Env.electron=true; Env.readable=false; Env.chromeRecoveryWorks=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(upTo:3.4) { Env.posts==1 && p.lastInsertionConfirmed && !p.isOffering }
   check(Env.electronRequests==1 && Env.chromeRequests==0 && Env.posts==1 && p.lastInsertionConfirmed && !p.isOffering,"Electron delayed accessibility resolves before one verified paste") }
  Env.reset(); Env.electron=true; Env.readable=false
  do { let p=Paster(); p.offer("fixture",into:123); tick(3.4)
   check(Env.electronRequests==1 && Env.posts==0 && p.isOffering,"Electron inaccessible field never receives a blind paste"); p.cancelOffer() }
  Env.reset(); Env.electron=true
  do { let p=Paster(); p.offer("fixture",into:123); tick(0.35)
   check(Env.electronRequests==0 && Env.posts==1 && !p.isOffering,"Ready Electron editor pastes without accessibility recovery") }
  Env.reset(); Env.electron=true; Env.readable=false; Env.chromeRecoveryWorks=true
  do { let p=Paster(); p.offer("fixture",into:456); tick(0.2)
   check(Env.electronRequests==0 && Env.posts==0,"Background Electron app is never prepared or pasted"); p.cancelOffer() }
  print("PASS all paste lifecycle scenarios (in-memory OS, not a live Codex test)")
 }
}
'''
files=[out/'Shim.swift',out/'Paster.swift',out/'Tests.swift']
for p,s in zip(files,[shim,source,tests]):p.write_text(s)
subprocess.run(['swiftc','-module-cache-path',str(root/'.build/core-tests/modules'),str(root/'Sources/EdgelessTypeCore/PasteConfirmation.swift'),str(root/'Sources/EdgelessTypeCore/OutputPolicy.swift'),*map(str,files),'-o',str(out/'tests')],check=True)
subprocess.run([str(out/'tests')],check=True)
