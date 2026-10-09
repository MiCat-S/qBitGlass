import XCTest

/// 對本機模擬伺服器（scripts/mock_qb.py）跑完整操作流程並截圖到 build/shots。
final class QBManagerUITests: XCTestCase {
    let app = XCUIApplication()

    private var shotDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/shots")
    }

    private func shot(_ name: String) {
        try? FileManager.default.createDirectory(at: shotDir, withIntermediateDirectories: true)
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: shotDir.appendingPathComponent("\(name).png"))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    private func cell(_ name: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// List 只會載入畫面上的 cell，找不到就上下捲動
    @discardableResult
    private func findCell(_ name: String) -> XCUIElement {
        let c = cell(name)
        let list = app.collectionViews.firstMatch
        for _ in 0..<6 where !c.exists { list.swipeUp() }
        for _ in 0..<10 where !c.exists { list.swipeDown() }
        return c
    }

    /// 只截圖：詳情、伺服器清單、編輯伺服器（可搭配 simctl 切換深色模式）
    func testScreens() throws {
        let prefix = ProcessInfo.processInfo.environment["SHOT_PREFIX"] ?? "s"
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10))
        sleep(1)
        shot("\(prefix)_list")
        app.cells.firstMatch.tap()
        XCTAssertTrue(app.segmentedControls.buttons["檔案"].waitForExistence(timeout: 5))
        sleep(2)
        shot("\(prefix)_detail")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons["BackButton"].tap()
        sleep(1)
        shot("\(prefix)_servers")
        app.buttons["新增伺服器"].tap()
        sleep(1)
        shot("\(prefix)_server_edit")
    }

    func testFullFlow() throws {
        // 1. 清單載入
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10), "清單未載入")
        XCTAssertTrue(findCell("ubuntu-24.04.1-desktop-amd64.iso").exists)
        shot("01_list")

        // 2. 狀態篩選：下載中
        app.buttons["chip.downloading"].tap()
        sleep(1)
        XCTAssertFalse(cell("Big.Buck.Bunny.2008.1080p.BluRay.x264.mkv").exists, "做種中的種子不應出現在下載中")
        shot("02_filter_downloading")
        app.buttons["chip.all"].tap()

        // 3. 進入選取模式 → 全選
        app.buttons["更多"].tap()
        app.buttons["選取"].firstMatch.tap()
        XCTAssertTrue(app.buttons["全選"].waitForExistence(timeout: 3))
        app.buttons["全選"].tap()
        XCTAssertTrue(app.staticTexts["已選 10 項"].waitForExistence(timeout: 3))
        shot("03_select_all")

        // 4. 批次強制啟動
        app.buttons["強制"].tap()
        sleep(3)
        XCTAssertTrue(app.buttons["取消強制"].waitForExistence(timeout: 5), "全部強制後按鈕應變成取消強制")
        shot("04_force_started")

        // 5. 反選（全部 → 0）然後全不選、完成
        app.buttons["全不選"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["已選 0 項"].waitForExistence(timeout: 3))
        app.buttons["完成"].tap()

        // 6. 左滑刪除單一種子
        let victim = findCell("Fedora-Workstation-Live-41.iso")
        XCTAssertTrue(victim.exists)
        // 避免目標剛好在底部浮動列下方：不可點擊時再往上捲一點，左滑最多重試 3 次
        if !victim.isHittable { app.collectionViews.firstMatch.swipeUp(velocity: .slow) }
        var revealed = false
        for _ in 0..<3 where !revealed {
            victim.swipeLeft()
            revealed = app.buttons["刪除"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(revealed, "左滑後應出現刪除按鈕")
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.buttons["刪除種子（保留檔案）"].waitForExistence(timeout: 3))
        shot("05_delete_confirm")
        app.buttons["刪除種子（保留檔案）"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: victim)
        waitForExpectations(timeout: 6)

        // 7. 篩選面板：分類 Linux
        app.buttons["篩選"].tap()
        let linux = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Linux'")).firstMatch
        XCTAssertTrue(linux.waitForExistence(timeout: 3))
        shot("06_filter_sheet")
        linux.tap()
        app.buttons["完成"].firstMatch.tap()
        sleep(1)
        XCTAssertFalse(cell("Big.Buck.Bunny.2008.1080p.BluRay.x264.mkv").exists)
        shot("07_filtered_linux")

        // 8. 詳情頁
        findCell("archlinux-2026.10.01-x86_64.iso").tap()
        XCTAssertTrue(app.segmentedControls.buttons["檔案"].waitForExistence(timeout: 5))
        sleep(1)
        shot("08_detail_info")
        app.segmentedControls.buttons["檔案"].tap()
        sleep(2)
        shot("09_detail_files")
        app.segmentedControls.buttons["Tracker"].tap()
        sleep(2)
        shot("10_detail_trackers")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // 9. 清除篩選後新增磁力連結
        app.buttons["篩選"].tap()
        app.buttons["重設"].tap()
        app.buttons["完成"].firstMatch.tap()
        app.buttons["新增"].tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Agent.327.Operation.Barbershop")
        shot("11_add_torrent")
        app.navigationBars["新增種子"].buttons["新增"].tap()
        sleep(3)
        XCTAssertTrue(findCell("Agent.327.Operation.Barbershop").exists)
        shot("12_added")
    }

    /// 從表單新增伺服器並測試連線：密碼錯誤要提示帳密錯誤，正確則連線成功
    func testServerFormLogin() throws {
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["BackButton"].tap()
        app.buttons["新增伺服器"].tap()

        let url = app.textFields["http://192.168.1.10:8080"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap()
        url.typeText("http://127.0.0.1:8080")
        let password = app.secureTextFields["密碼"]
        password.tap()
        password.typeText("wrong")

        let test = app.buttons["測試連線"]
        test.tap()
        XCTAssertTrue(app.staticTexts["登入失敗：帳號或密碼錯誤"].waitForExistence(timeout: 10))
        shot("13_login_wrong")

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "adminadmin")
        test.tap()
        let ok = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '連線成功'")).firstMatch
        XCTAssertTrue(ok.waitForExistence(timeout: 10), "正確帳密應連線成功")
        shot("14_login_ok")
        app.buttons["取消"].tap()
    }
}
