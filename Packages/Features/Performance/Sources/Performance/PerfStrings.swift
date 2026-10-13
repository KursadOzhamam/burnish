import Foundation

/// Localized text for this feature (CLAUDE.md §15).
enum PerfStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(value), bundle: .atURL(bundleURL))
    }

    static let title = key("performance.title")
    static let subtitle = key("performance.subtitle")
    static let tabMaintenance = key("performance.tab.maintenance")
    static let tabStartup = key("performance.tab.startup")
    static let tabProcesses = key("performance.tab.processes")
    static let helperTitle = key("performance.helper.title")
    static let helperNotRegistered = key("performance.helper.notRegistered")
    static let helperRequiresApproval = key("performance.helper.requiresApproval")
    static let helperEnabled = key("performance.helper.enabled")
    static let helperNotFound = key("performance.helper.notFound")
    static let helperVersionMismatch = key("performance.helper.versionMismatch")
    static let helperFailed = key("performance.helper.failed")
    static let helperInstall = key("performance.helper.install")
    static let helperOpenSettings = key("performance.helper.openSettings")
    static let taskFlushDNS = key("performance.task.flushDNS")
    static let taskFlushDNSDetail = key("performance.task.flushDNS.detail")
    static let taskRebuildLaunchServices = key("performance.task.rebuildLaunchServices")
    static let taskRebuildLaunchServicesDetail = key("performance.task.rebuildLaunchServices.detail")
    static let taskReindexSpotlight = key("performance.task.reindexSpotlight")
    static let taskReindexSpotlightDetail = key("performance.task.reindexSpotlight.detail")
    static let taskVerifyDisk = key("performance.task.verifyDisk")
    static let taskVerifyDiskDetail = key("performance.task.verifyDisk.detail")
    static let taskPurgeMemory = key("performance.task.purgeMemory")
    static let taskPurgeMemoryDetail = key("performance.task.purgeMemory.detail")
    static let taskRunPeriodicScripts = key("performance.task.runPeriodicScripts")
    static let taskRunPeriodicScriptsDetail = key("performance.task.runPeriodicScripts.detail")
    static let taskRun = key("performance.task.run")
    static let taskRunning = key("performance.task.running")
    static let taskNeedsHelper = key("performance.task.needsHelper")
    static let startupNote = key("performance.startup.note")
    static let startupMissing = key("performance.startup.missing")
    static let startupApple = key("performance.startup.apple")
    static let startupDaemon = key("performance.startup.daemon")
    static let startupUserAgent = key("performance.startup.userAgent")
    static let startupGlobalAgent = key("performance.startup.globalAgent")
    static let processesCpu = key("performance.processes.cpu")
    static let processesMemory = key("performance.processes.memory")
    static let processesQuit = key("performance.processes.quit")
    static let processesNote = key("performance.processes.note")
    static let pressureToggle = key("performance.pressure.toggle")

    static func task(_ task: MaintenanceTask) -> LocalizedStringResource { key("performance.task.\(task.rawValue)") }
    static func taskDetail(_ task: MaintenanceTask) -> LocalizedStringResource { key("performance.task.\(task.rawValue).detail") }
}
