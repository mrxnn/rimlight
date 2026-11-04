import Foundation
import RimlightCore
import Synchronization

/// The job markers this process keeps while it renders (`.rimlight/.jobs/`), so the app shows
/// the render and keeps alive the agent process it runs under. Each one goes when its
/// image lands, and every one left goes on any exit: `defer` on a return or a throw, and the
/// SIGTERM, SIGINT and SIGHUP handlers before the signal's default action.
enum Jobs {
    private static let active = Mutex<[String: ProjectStore]>([:])
    private static let signalQueue = DispatchQueue(label: "rimlight signals")
    /// Walked once, on first use: the first marker, or a build's `run.json`.
    static let host = ProcessTree.host()
    static var hostPID: Int32? { host?.pid }

    /// Writes a marker per image; returns their ids in the same order, nil where one could not
    /// be written (the render goes ahead without it).
    static func begin(
        _ store: ProjectStore, images: [(set: String, slug: String, title: String)], mode: JobMarker.Mode
    ) -> [String?] {
        _ = signalSources
        let host = hostPID
        return images.map { image in
            let marker = JobMarker(hostPID: host, set: image.set, slug: image.slug, title: image.title, mode: mode)
            // One a signal catches between the write and this is left for `pruneDeadJobs`.
            guard (try? store.writeJob(marker)) != nil else { return nil }
            active.withLock { $0[marker.id] = store }
            return marker.id
        }
    }

    /// The image landed or failed: its marker goes.
    static func end(_ id: String?) {
        guard let id, let store = active.withLock({ $0.removeValue(forKey: id) }) else { return }
        store.removeJob(id)
    }

    static func endAll() {
        let all = active.withLock { jobs in
            defer { jobs.removeAll() }
            return jobs
        }
        for (id, store) in all { store.removeJob(id) }
    }

    /// Installed once. A no-op C handler rather than SIG_IGN, which codex would inherit across
    /// exec; the dispatch source runs the cleanup on its own queue (the render's threads may
    /// all be blocked), then the signal's default action.
    private static let signalSources: [any DispatchSourceSignal] = [SIGTERM, SIGINT, SIGHUP].map { sig in
        signal(sig, { _ in })
        let source = DispatchSource.makeSignalSource(signal: sig, queue: signalQueue)
        source.setEventHandler {
            endAll()
            signal(sig, SIG_DFL)
            raise(sig)
        }
        source.resume()
        return source
    }
}
