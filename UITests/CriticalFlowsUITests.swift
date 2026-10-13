import XCTest

/// Critical-flow checks driven through the real app (CLAUDE.md §9, roadmap 10.10).
///
/// They look only; none presses a button that removes anything. Their job is the class of bug
/// unit tests cannot see: a screen that builds but cannot be reached, a primary button that
/// cannot be pressed, a layout that collapses.
final class CriticalFlowsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // Skip the first-run welcome so the sidebar is reachable.
        app.launchArguments += ["-onboarding.done", "YES"]
        app.launch()
    }

    private func openSection(_ name: String) {
        let row = app.outlines.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar row \(name) exists")
        row.click()
    }

    func testEverySidebarSectionOpens() {
        for name in ["Genel Bakış", "Akıllı Tarama", "Temizlik", "Koruma", "Hız", "Uygulamalar", "Dosyalar", "Gizlilik"] {
            openSection(name)
            XCTAssertTrue(app.windows.firstMatch.exists, "window survives opening \(name)")
        }
    }

    func testSmartScanHasAPressableStartButton() {
        openSection("Akıllı Tarama")
        let button = app.buttons["Taramayı Başlat"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, "the whole control must be reachable by a real click")
    }

    func testCleanupShowsItsScanButtonAndNothingIsPreselectedBeforeScanning() {
        openSection("Temizlik")
        XCTAssertTrue(app.buttons["Taramayı Başlat"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Çöp'e Taşı"].exists, "no removal action before a scan")
    }

    func testFilesSectionOffersItsToolsAndTheScopeSheet() {
        openSection("Dosyalar")
        for tab in ["Büyük dosyalar", "Alan haritası", "Kopyalar", "Benzer görseller", "Parçalayıcı"] {
            XCTAssertTrue(app.radioButtons[tab].waitForExistence(timeout: 5), "tab \(tab)")
        }
        app.buttons["Kapsam"].click()
        XCTAssertTrue(app.buttons["Bitti"].waitForExistence(timeout: 5))
        app.buttons["Bitti"].click()
    }

    func testShredderCannotBeArmedWithoutFiles() {
        openSection("Dosyalar")
        app.radioButtons["Parçalayıcı"].click()
        let delete = app.buttons["Kalıcı olarak sil..."]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        XCTAssertFalse(delete.isEnabled, "permanent deletion stays disabled with nothing chosen")
    }

    func testApplicationsListAndRemovalPreviewOpensAndCancels() {
        openSection("Uygulamalar")
        let first = app.buttons["Kaldır..."].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        first.click()
        let cancel = app.buttons["Vazgeç"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "the preview opens")
        cancel.click()
        XCTAssertFalse(cancel.exists, "and closes without removing anything")
    }
}
