import Foundation

/// Localized text for this feature (CLAUDE.md §15).
enum ProtStrings {
    private static let bundleURL = Bundle.module.bundleURL

    static func key(_ value: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(value), bundle: .atURL(bundleURL))
    }

    static let title = key("protection.title")
    static let subtitle = key("protection.subtitle")
    static let tabScan = key("protection.tab.scan")
    static let tabQuarantine = key("protection.tab.quarantine")
    static let tabSystem = key("protection.tab.system")
    static let scanStart = key("protection.scan.start")
    static let scanCancel = key("protection.scan.cancel")
    static let scanRescan = key("protection.scan.rescan")
    static let scanWhat = key("protection.scan.what")
    static let scanClean = key("protection.scan.clean")
    static let scanCleanDetail = key("protection.scan.cleanDetail")
    static let findingThreat = key("protection.finding.threat")
    static let findingSuspicious = key("protection.finding.suspicious")
    static let findingInfo = key("protection.finding.info")
    static let findingWhy = key("protection.finding.why")
    static let reasonKnownBadHash = key("protection.reason.knownBadHash")
    static let reasonUnsignedFromInternet = key("protection.reason.unsignedFromInternet")
    static let reasonInvalidSignature = key("protection.reason.invalidSignature")
    static let reasonDanglingLaunchItem = key("protection.reason.danglingLaunchItem")
    static let reasonHiddenLaunchItem = key("protection.reason.hiddenLaunchItem")
    static let actionQuarantine = key("protection.action.quarantine")
    static let actionSafe = key("protection.action.safe")
    static let actionReveal = key("protection.action.reveal")
    static let actionRestore = key("protection.action.restore")
    static let quarantineEmpty = key("protection.quarantine.empty")
    static let quarantineNote = key("protection.quarantine.note")
    static let systemGatekeeper = key("protection.system.gatekeeper")
    static let systemSip = key("protection.system.sip")
    static let systemXprotect = key("protection.system.xprotect")
    static let systemBlocklist = key("protection.system.blocklist")
    static let systemBlocklistNone = key("protection.system.blocklistNone")
    static let systemOn = key("protection.system.on")
    static let systemOff = key("protection.system.off")
    static let systemUnknown = key("protection.system.unknown")
    static let permissionsTitle = key("protection.permissions.title")
    static let permissionsNote = key("protection.permissions.note")
    static let permissionsNeedFDA = key("protection.permissions.needFDA")
    static let permissionsOpenSettings = key("protection.permissions.openSettings")
    static let permissionsNone = key("protection.permissions.none")
    static let serviceCamera = key("protection.service.camera")
    static let serviceMicrophone = key("protection.service.microphone")
    static let serviceScreenRecording = key("protection.service.screenRecording")
    static let serviceFullDiskAccess = key("protection.service.fullDiskAccess")
    static let serviceAccessibility = key("protection.service.accessibility")
    static let serviceInputMonitoring = key("protection.service.inputMonitoring")
    static let serviceContacts = key("protection.service.contacts")
    static let servicePhotos = key("protection.service.photos")
    static let serviceLocation = key("protection.service.location")
    static let messageQuarantined = key("protection.message.quarantined")
    static let messageRestored = key("protection.message.restored")
    static let messageRefused = key("protection.message.refused")
    static let messageFailed = key("protection.message.failed")

    static func progress(_ n: Int) -> LocalizedStringResource { LocalizedStringResource("protection.scan.progress \(n)", bundle: .atURL(bundleURL)) }
    static func found(_ n: Int) -> LocalizedStringResource { LocalizedStringResource("protection.scan.found \(n)", bundle: .atURL(bundleURL)) }
}
