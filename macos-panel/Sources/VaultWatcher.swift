import Foundation
import Darwin

/// 目录事件合并 0.3 秒；另有 2.5 秒兜底轮询。
/// 原子替换/目录删除会重挂监视，读取逻辑每次重新列举目录。
final class VaultWatcher {
    var onNeedsScan: (() -> Void)?

    private let queue = DispatchQueue(label: "meeting-vault-panel.watcher")
    private var sources: [DispatchSourceFileSystemObject] = []
    private var timer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var vault: URL?

    func start(vaultURL: URL) {
        queue.sync {
            stopSources()
            vault = vaultURL
            arm()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 2.5, repeating: 2.5, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in
                self?.arm()
                self?.onNeedsScan?()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.sync { stopSources() }
    }

    private func stopSources() {
        pending?.cancel()
        pending = nil
        timer?.cancel()
        timer = nil
        for source in sources { source.cancel() }
        sources.removeAll()
        vault = nil
    }

    // The final release may occur from an event handler on this queue.
    deinit { stopSources() }

    private func scheduleDebouncedScan() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.arm()
            self.onNeedsScan?()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func arm() {
        for source in sources { source.cancel() }
        sources.removeAll()
        guard let vault else { return }
        let directories = [
            vault.appendingPathComponent("inbox", isDirectory: true),
            vault.appendingPathComponent(".meeting-review", isDirectory: true)
        ]
        for directory in directories {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            let fd = open(directory.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in self?.scheduleDebouncedScan() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }
}
