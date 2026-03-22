import Darwin
import Foundation

final class SessionLogWatcher {
    private let rootURL: URL
    private let callback: @Sendable () -> Void
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "codex.quota.widget.fs", qos: .utility)

    private var sources: [URL: DispatchSourceFileSystemObject] = [:]
    private var descriptors: [URL: CInt] = [:]
    private var debounceWorkItem: DispatchWorkItem?

    init(
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions", isDirectory: true),
        fileManager: FileManager = .default,
        callback: @escaping @Sendable () -> Void
    ) {
        self.rootURL = rootURL
        self.fileManager = fileManager
        self.callback = callback
    }

    deinit {
        stop()
    }

    func start() {
        queue.async { [weak self] in
            self?.installSources()
        }
    }

    func stop() {
        queue.sync {
            debounceWorkItem?.cancel()
            debounceWorkItem = nil

            for source in sources.values {
                source.cancel()
            }

            for descriptor in descriptors.values {
                close(descriptor)
            }

            sources.removeAll()
            descriptors.removeAll()
        }
    }

    private func installSources() {
        let directories = discoverDirectories()
        let currentURLs = Set(directories)

        for url in Set(sources.keys).subtracting(currentURLs) {
            sources[url]?.cancel()
            sources[url] = nil
            if let descriptor = descriptors.removeValue(forKey: url) {
                close(descriptor)
            }
        }

        for url in directories where sources[url] == nil {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                continue
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .attrib, .delete, .rename],
                queue: queue
            )

            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.scheduleRefresh()
            }

            source.setCancelHandler {}
            source.resume()

            descriptors[url] = descriptor
            sources[url] = source
        }
    }

    private func discoverDirectories() -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return [rootURL.deletingLastPathComponent()]
        }

        var directories = [rootURL]
        let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }

            directories.append(url)
        }

        return directories
    }

    private func scheduleRefresh() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.installSources()
            self.callback()
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
}
