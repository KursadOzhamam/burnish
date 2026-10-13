import Foundation
import Dispatch

/// Reports when macOS says memory is tight (CLAUDE.md §6.5). Uses the kernel's own pressure
/// signal rather than a threshold of our own, so it agrees with what Activity Monitor shows.
public final class MemoryPressureWatcher: @unchecked Sendable {
    public enum Level: Sendable, Equatable { case warning, critical }

    private let source: DispatchSourceMemoryPressure
    private let handler: @Sendable (Level) -> Void

    public init(onChange handler: @escaping @Sendable (Level) -> Void) {
        self.handler = handler
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = self.source.data
            self.handler(data.contains(.critical) ? .critical : .warning)
        }
    }

    public func start() { source.resume() }
    public func stop() { source.cancel() }
}
