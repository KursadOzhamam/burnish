import Foundation
import Applications
import Cleanup
import Dashboard
import Files
import History
import Performance
import Protection

/// Every long-lived model of the app, built exactly once.
@MainActor
final class AppModels {
    static let shared = AppModels()

    let scanCoordinator: ScanCoordinator
    /// Same log as Cleanup writes to, so what was just removed is what the sheet lists.
    let historyModel: HistoryModel
    let filesModels: FilesModels
    let applicationsModel: ApplicationsModel
    let performanceModel: PerformanceModel
    let dashboardModel: DashboardModel
    let privacyModel: CleanupModel
    let protectionModel: ProtectionModel

    private init() {
        let history = RootView.history
        scanCoordinator = ScanCoordinator(history: history)
        historyModel = HistoryModel(store: history)
        filesModels = FilesModels(history: history)
        applicationsModel = ApplicationsModel(history: history)
        performanceModel = PerformanceModel(history: history)
        dashboardModel = DashboardModel()
        privacyModel = CleanupModel.privacy(history: history)
        protectionModel = ProtectionModel(supportDirectory: RootView.supportDirectory)
    }
}
