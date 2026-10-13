import Foundation
import AppKit
import Observation
import UserNotifications
import HelperProtocol

/// State behind the Performance section (CLAUDE.md §6.5).
@Observable
@MainActor
public final class PerformanceModel {
    public enum TaskState: Sendable, Equatable {
        case idle
        case running
        case succeeded(String)
        case failed(String)
    }

    // MARK: Helper

    public private(set) var helperStatus: HelperStatus = .notRegistered
    private let helper: any HelperManaging

    // MARK: Maintenance

    public private(set) var taskStates: [MaintenanceTask: TaskState] = [:]
    private let runner: any CommandRunning

    // MARK: Startup items

    public private(set) var launchItems: [LaunchItem] = []
    public private(set) var disabledLabels: Set<String> = []
    public private(set) var launchError: String?
    private let catalogue: LaunchItemCatalogue
    private let control: LaunchControl

    // MARK: Processes

    public private(set) var topCPU: [ProcessLoad] = []
    public private(set) var topMemory: [ProcessSample] = []
    private let sampler = ProcessSampler()

    // MARK: Memory pressure

    public private(set) var notifiesOnMemoryPressure: Bool
    private var watcher: MemoryPressureWatcher?
    private let defaults: UserDefaults?
    private let notify: @Sendable (MemoryPressureWatcher.Level) -> Void
    private let requestPermission: @Sendable () -> Void

    public init(
        helper: any HelperManaging = HelperClient(),
        runner: any CommandRunning = ProcessCommandRunner(),
        catalogue: LaunchItemCatalogue = LaunchItemCatalogue(),
        control: LaunchControl = LaunchControl(),
        defaults: UserDefaults? = .standard,
        notify: @escaping @Sendable (MemoryPressureWatcher.Level) -> Void = PerformanceModel.postNotification,
        requestPermission: @escaping @Sendable () -> Void = PerformanceModel.askForNotificationPermission
    ) {
        self.requestPermission = requestPermission
        self.helper = helper
        self.runner = runner
        self.catalogue = catalogue
        self.control = control
        self.defaults = defaults
        self.notify = notify
        self.notifiesOnMemoryPressure = defaults?.bool(forKey: "performance.memoryPressureNotify") ?? false
    }

    // MARK: Helper

    public func refreshHelper() async { helperStatus = await helper.status() }

    public func installHelper() async { helperStatus = await helper.install() }

    public func openLoginItemsSettings() { helper.openSettings() }

    // MARK: Maintenance

    public func state(of task: MaintenanceTask) -> TaskState { taskStates[task] ?? .idle }

    /// Whether the task can run now: the ones that need root need the helper to be enabled.
    public func canRun(_ task: MaintenanceTask) -> Bool {
        !task.requiresHelper || helperStatus == .enabled
    }

    public func run(_ task: MaintenanceTask) async {
        guard canRun(task), state(of: task) != .running else { return }
        taskStates[task] = .running
        do {
            let result: CommandResult
            if let command = task.helperCommand {
                result = try await helper.run(command)
            } else {
                let fixed = task.command
                result = try await runner.run(fixed.executable, arguments: fixed.arguments)
            }
            let text = String(result.output.suffix(600)).trimmingCharacters(in: .whitespacesAndNewlines)
            taskStates[task] = result.succeeded ? .succeeded(text) : .failed(text)
        } catch {
            taskStates[task] = .failed(error.localizedDescription)
        }
    }

    // MARK: Startup items

    public func loadLaunchItems() async {
        launchItems = catalogue.items()
        launchError = nil
        do { disabledLabels = try await control.disabledLabels() } catch { disabledLabels = [] }
    }

    public func isEnabled(_ item: LaunchItem) -> Bool { !disabledLabels.contains(item.label) }

    /// Switches a per-user job on or off, reversibly. Refused ones surface as `launchError`.
    public func setEnabled(_ item: LaunchItem, to isOn: Bool) async {
        launchError = nil
        do {
            if isOn { try await control.enable(item) } else { try await control.disable(item) }
            if isOn { disabledLabels.remove(item.label) } else { disabledLabels.insert(item.label) }
        } catch {
            launchError = "\(error)"
        }
    }

    // MARK: Processes

    public func refreshProcesses() async {
        let sampler = sampler
        let loads = await sampler.load(over: 1)
        topCPU = ProcessSampler.topByCPU(loads, count: 12)
        topMemory = ProcessSampler.topByMemory(loads.map(\.sample), count: 12)
    }

    /// Whether the process can be asked to quit: a regular application that is not the system's.
    public func canQuit(_ sample: ProcessSample) -> Bool {
        guard !sample.isSystem, sample.pid != getpid() else { return false }
        return NSRunningApplication(processIdentifier: sample.pid)?.activationPolicy == .regular
    }

    /// Asks the application to quit, the way its own Quit menu would. Never a forced kill.
    public func requestQuit(_ sample: ProcessSample) {
        guard canQuit(sample) else { return }
        NSRunningApplication(processIdentifier: sample.pid)?.terminate()
    }

    // MARK: Memory pressure

    /// Turns the notification on or off. The first time on, the system asks for permission.
    public func setNotifiesOnMemoryPressure(_ isOn: Bool) {
        notifiesOnMemoryPressure = isOn
        defaults?.set(isOn, forKey: "performance.memoryPressureNotify")
        watcher?.stop()
        watcher = nil
        guard isOn else { return }
        requestPermission()
        let notify = notify
        let next = MemoryPressureWatcher { level in notify(level) }
        next.start()
        watcher = next
    }

    /// Asked for the first time the user turns the notification on, not at launch (CLAUDE.md §7).
    public nonisolated static func askForNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    public nonisolated static func postNotification(for level: MemoryPressureWatcher.Level) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: LocalizedStringResource("performance.pressure.title", bundle: .atURL(Bundle.module.bundleURL)))
        content.body = String(localized: LocalizedStringResource(
            level == .critical ? "performance.pressure.critical" : "performance.pressure.warning",
            bundle: .atURL(Bundle.module.bundleURL)
        ))
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "burnish.memory", content: content, trigger: nil))
    }
}
