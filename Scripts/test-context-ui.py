#!/usr/bin/env python3
"""Exercise real settings controls with disposable data; no AX reads or network."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parent.parent
out = root / '.build/context-ui-tests'
out.mkdir(parents=True, exist_ok=True)
(out/'Preferences.swift').write_text((root/'Sources/EdgelessTypeCore/Transcription.swift').read_text().split('public enum TranscriptionRouter')[0])
(out/'Settings.swift').write_text((root/'Sources/EdgelessType/TranscriptionSettingsWindow.swift').read_text().replace('import EdgelessTypeCore', ''))
(out/'Run.swift').write_text(r'''import AppKit
@main struct Run {
 static func main() throws {
  _ = NSApplication.shared
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = TranscriptionPreferencesStore(url: root.appendingPathComponent("settings.json"))
  let editor = TranscriptionSettingsWindow(store: store)
  func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
  let controls = all(editor.window!.contentView!)
  let switches = controls.compactMap { $0 as? NSSwitch }
  precondition(switches.count == 2)
  let main = switches[0], cloud = switches[1]
  let save = controls.compactMap { $0 as? NSButton }.first { $0.title == "儲存設定" }!
  func set(_ control: NSSwitch, _ state: NSControl.StateValue) {
   control.state = state
   _ = control.sendAction(control.action, to: control.target)
  }
  precondition(main.state == .off && cloud.state == .off && cloud.superview!.isHidden)
  set(main, .on)
  precondition(!cloud.superview!.isHidden && cloud.state == .off)
  set(cloud, .on); save.performClick(nil)
  let enabled = try store.load()
  precondition(enabled.recordingContextEnabled && enabled.cloudContextConsent)
  set(main, .off); save.performClick(nil)
  let off = try store.load()
  precondition(!off.recordingContextEnabled && !off.cloudContextConsent)
  editor.refresh()
  precondition(main.state == .off && cloud.state == .off)
  print("PASS native context controls: defaults, reveal, save, revoke and reload")
 }
}
''')
subprocess.run(['swiftc', '-module-cache-path', str(root/'.build/core-tests/modules'), *map(str, sorted(out.glob('*.swift'))), '-o', str(out/'run')], check=True)
subprocess.run([str(out/'run')], check=True)
