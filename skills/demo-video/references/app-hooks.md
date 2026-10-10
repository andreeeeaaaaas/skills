# App hooks

A demo hook lets a plan's `state:` steps change what the app shows: fake data appearing, a background event, a setting flipping. Add it once per project; after that, new demos are only plans.

Rules for every platform:

- **Opt-in.** Only active when launched for a demo (`--demo` argument, or `DEMO=1` in the environment, which the runner always sets).
- **Fake data, separate storage.** Use a separate `UserDefaults` suite, database file or in-memory store, and clear it at start and quit. Never touch the user's real data or settings.
- **Real UI.** The hook replaces data sources (network, process table, sensors), not views. What's recorded is the app's real interface.
- **Line commands.** One command per line or URL: a verb and arguments (`add vite`, `exit backoffice`, `style LED Amber`, `message from Sam`). Log unknown commands to stderr and carry on.
- **Swappable sources.** Put the data source behind a small protocol so the demo can swap in a scripted one. See Terminal Terminal's `ProcessSource` and `ScriptedProcesses` for a worked example.

## macOS (SwiftUI or AppKit): commands on stdin

The runner writes each `state:` command to the app's stdin and closes stdin when the take ends: quit then.

```swift
// In main / App init: enable when launched with --demo.
let demo = CommandLine.arguments.contains("--demo") ? Demo() : nil

@MainActor
final class Demo {
    let store = DemoStore()   // the fake data source the app reads from

    func run() async {
        let lines = AsyncStream<String> { continuation in
            Thread.detachNewThread {
                while let line = readLine() { continuation.yield(line) }
                continuation.finish()
            }
        }
        for await line in lines {
            let words = line.split(separator: " ").map(String.init)
            switch words.first {
            case "add": store.add(words.dropFirst().joined(separator: " "))
            case "quit": NSApp.terminate(nil)
            default: FileHandle.standardError.write(Data("demo: unknown \(line)\n".utf8))
            }
        }
        NSApp.terminate(nil)   // stdin closed: the take is over
    }
}
```

Start `demo.run()` from `applicationDidFinishLaunching` (AppKit) or a `.task` on the root view (SwiftUI). Use a separate defaults suite: `UserDefaults(suiteName: "<bundle id>.demo")`, cleared with `removePersistentDomain(forName:)`.

Launch it in a plan as `launch: [path/to/binary, --demo]`. For an `.app` bundle, launch the binary inside it (`MyApp.app/Contents/MacOS/MyApp`), not `open`, so stdin reaches it.

## Electron or Node desktop apps: stdin

```js
if (process.argv.includes('--demo')) {
  const rl = require('readline').createInterface({ input: process.stdin })
  rl.on('line', line => {
    const [verb, ...rest] = line.split(' ')
    mainWindow.webContents.send('demo', { verb, arg: rest.join(' ') })
  })
  rl.on('close', () => app.quit())
}
```

## iOS (SwiftUI): deep links

The runner opens `<scheme>://demo?cmd=<command>` with `simctl openurl`. Register the scheme (Info.plist `CFBundleURLTypes`, or the target's URL Types in Xcode), and set `app.urlScheme` in the plan.

```swift
@main
struct MyApp: App {
    @StateObject private var model = AppModel(demo: ProcessInfo.processInfo.environment["DEMO"] == "1"
                                                   || CommandLine.arguments.contains("-demo"))
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .onOpenURL { url in
                    guard model.isDemo, url.host == "demo",
                          let command = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                              .queryItems?.first(where: { $0.name == "cmd" })?.value else { return }
                    model.performDemoCommand(command)
                }
        }
    }
}
```

The runner sets `DEMO=1` (through `SIMCTL_CHILD_DEMO`) and passes `app.args`. UIKit apps handle the same URL in `scene(_:openURLContexts:)`.

For demo data on iOS, prefer an in-memory store (SwiftData `ModelConfiguration(isStoredInMemoryOnly: true)`, or a fake repository) chosen at launch when `DEMO=1`.

## Accessibility labels make good targets

Plans target controls by accessibility label or identifier. While adding the hook, give important controls stable ones:

```swift
Button { … } label: { Image(systemName: "xmark") }
    .accessibilityLabel("Stop \(name)")          // what VoiceOver reads, and a plan target
    .accessibilityIdentifier("row-stop-button")  // stable even if the text changes
```

Check with `demo-video ax --app "<App>" --find "Stop"`.
