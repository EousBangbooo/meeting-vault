import AppKit
import Darwin

func argumentValue(_ name: String, in arguments: [String]) -> String? {
    if let index = arguments.firstIndex(of: name), index + 1 < arguments.count {
        return arguments[index + 1]
    }
    let prefix = name + "="
    if let match = arguments.first(where: { $0.hasPrefix(prefix) }) {
        return String(match.dropFirst(prefix.count))
    }
    return nil
}

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    Meeting Vault 常驻看板（隔离原型）

    用法:
      MeetingVaultPanel [--vault <会议库路径>]
      MeetingVaultPanel --self-test [--vault <fixture路径>]

    只读 <会议库>/inbox/*.txt 与 .meeting-review/<sha256>.{started,json}。
    不写会议库，不启动浏览器，不激活应用。
    """)
    exit(0)
}

if arguments.contains("--self-test") {
    exit(runSelfTest(vaultPath: argumentValue("--vault", in: arguments)))
}

// Use the same lock for every copy of the app, including the build directory.
// Keep the file in place so all launches compete for the same inode.
let lockURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("com.local.meeting-vault-panel.lock")
let lockDescriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
guard lockDescriptor >= 0 else {
    perror("Meeting Vault: open instance lock")
    exit(EXIT_FAILURE)
}
guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
    let lockError = errno
    if lockError == EWOULDBLOCK { exit(EXIT_SUCCESS) }
    errno = lockError
    perror("Meeting Vault: acquire instance lock")
    exit(EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()
delegate.initialVaultPath = argumentValue("--vault", in: arguments)
if let reportPath = argumentValue("--ui-test-report", in: arguments) {
    delegate.testReportURL = URL(fileURLWithPath: reportPath)
}
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
close(lockDescriptor)
