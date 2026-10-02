import Foundation

let args = CommandLine.arguments
if args.contains("--dump") {
    TouchDevice.skipWakeUp = args.contains("--no-wake")
    let seconds = args.firstIndex(of: "--seconds").flatMap { Double(args[safe: $0 + 1] ?? "") }
    DumpMode.run(exclusive: !args.contains("--shared"), seconds: seconds)
} else {
    TouchRemapApp.main()
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
