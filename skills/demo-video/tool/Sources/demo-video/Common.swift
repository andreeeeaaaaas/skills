import CoreMedia
import CoreImage
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("demo-video: \(message)\n".utf8))
    exit(1)
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("demo-video: \(message)\n".utf8))
}

/// Seconds on the host clock, the same clock ScreenCaptureKit stamps frames with.
func hostSeconds() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

func sleep(seconds: Double) async {
    guard seconds > 0 else { return }
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

/// Sleeps until `hostSeconds()` reaches `deadline`.
func sleep(until deadline: Double) async {
    await sleep(seconds: deadline - hostSeconds())
}

func parseColor(_ value: String) -> CIColor? {
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard hex.count == 6, let rgb = UInt32(hex, radix: 16) else { return nil }
    return CIColor(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255)
}

/// Runs a tool and returns its exit status and standard output.
@discardableResult
func run(_ path: String, _ arguments: [String], quiet: Bool = true) -> (status: Int32, output: String) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: path)
    task.arguments = arguments
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = quiet ? FileHandle.nullDevice : FileHandle.standardError
    do { try task.run() } catch { return (-1, "") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return (task.terminationStatus, String(decoding: data, as: UTF8.self))
}

func ffmpegPath() -> String? {
    ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// Simple `--flag value` parsing shared by the subcommands.
struct Arguments {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []
    private(set) var positional: [String] = []
    /// Everything after `--`.
    private(set) var command: [String] = []

    init(_ arguments: [String], flags known: Set<String>) {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                command = Array(arguments[(index + 1)...])
                break
            }
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if known.contains(name) {
                    flags.insert(name)
                } else {
                    index += 1
                    guard index < arguments.count else { fail("\(argument) needs a value") }
                    values[name] = arguments[index]
                }
            } else {
                positional.append(argument)
            }
            index += 1
        }
    }

    subscript(_ name: String) -> String? { values[name] }
    func has(_ flag: String) -> Bool { flags.contains(flag) }
    func double(_ name: String) -> Double? { values[name].flatMap(Double.init) }
    func int(_ name: String) -> Int? { values[name].flatMap(Int.init) }
    var names: Set<String> { Set(values.keys).union(flags) }
}
