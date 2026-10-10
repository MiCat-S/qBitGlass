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

    /// 確認框（iOS 26 起是 popover）要緊貼著觸發它的元件，而不是從畫面其他地方彈出
    private func assertAnchored(to source: CGRect, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let popover = app.sheets.firstMatch
        guard popover.waitForExistence(timeout: 3) else {
            shot("fail_\(message)")
            return XCTFail("確認框未出現：\(message)", file: file, line: line)
        }
        // popover 可能在來源的上下或左右，量兩個矩形之間的距離
        let f = popover.frame
        let dx = max(0, source.minX - f.maxX, f.minX - source.maxX)
        let dy = max(0, source.minY - f.maxY, f.minY - source.maxY)
        XCTAssertLessThan(hypot(dx, dy), 40, message, file: file, line: line)
    }

    /// 點確認框外面關掉它（popover 沒有取消按鈕）
    private func dismissPopover() {
        let f = app.sheets.firstMatch.frame
        let y = f.maxY + 60 < app.frame.maxY - 60 ? f.maxY + 60 : f.minY - 60
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: y)).tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.sheets.firstMatch)
        waitForExpectations(timeout: 3)
    }

    /// 底部有浮動的速度列與搜尋列，操作前先把目標拖到畫面上半部，避免手勢落在浮動列上。
    /// 用按住拖曳再停住的方式捲動，距離精確也沒有慣性
    @discardableResult
    private func lift(_ element: XCUIElement) -> XCUIElement {
        let h = app.frame.height
        for _ in 0..<3 where element.frame.maxY > h * 0.6 {
            let distance = min(element.frame.midY - h * 0.35, h * 0.4)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: h * 0.55))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -distance)),
                        withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        return element
    }

    /// 打開選單後等項目出現再點；選單展開動畫中的點擊會被系統忽略
    private func tapMenuItem(_ label: String) {
        let item = app.buttons[label]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "選單中找不到「\(label)」")
        usleep(400_000)
        item.tap()
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
        // 從列的上緣拖曳，避開底部浮動列
        lift(victim)
        var revealed = false
        for _ in 0..<3 where !revealed {
            let start = victim.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.25))
            start.press(forDuration: 0.05, thenDragTo: victim.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)))
            revealed = app.buttons["刪除"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(revealed, "左滑後應出現刪除按鈕")
        let victimFrame = victim.frame
        app.buttons["刪除"].firstMatch.tap()
        XCTAssertTrue(app.buttons["刪除種子（保留檔案）"].waitForExistence(timeout: 3))
        assertAnchored(to: victimFrame, "左滑刪除的確認框應從該列彈出")
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

    /// 確認框與 sheet 從觸發的位置彈出；sheet 內的錯誤在 sheet 內顯示
    /// 需以 MOCK_FAIL=torrents/addTags 啟動模擬伺服器
    func testPromptsAnchoredToSource() throws {
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10))

        // 1. 長按某一列 → 重新校驗：確認框從該列彈出
        let row = findCell("Spring.2019.Blender.Open.Movie.mkv")
        XCTAssertTrue(row.exists)
        lift(row)
        let rowFrame = row.frame
        row.press(forDuration: 1.0)
        tapMenuItem("重新校驗…")
        XCTAssertTrue(app.buttons["重新校驗"].waitForExistence(timeout: 3))
        assertAnchored(to: rowFrame, "長按選單的確認框應從該列彈出")
        shot("15_recheck_row")
        app.buttons["重新校驗"].tap()

        // 2. 管理標籤 sheet 內新增標籤失敗：錯誤要在 sheet 內顯示，關掉 sheet 後不應再跳一次
        row.press(forDuration: 1.0)
        tapMenuItem("管理標籤…")
        let field = app.textFields["標籤名稱（可用逗號分隔多個）"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("測試")
        app.buttons["新增並套用"].tap()
        XCTAssertTrue(app.alerts["操作失敗"].waitForExistence(timeout: 5), "sheet 內的操作失敗應在 sheet 內提示")
        shot("16_sheet_error")
        app.alerts["操作失敗"].buttons["好"].tap()
        app.buttons["完成"].firstMatch.tap()
        sleep(2)
        XCTAssertFalse(app.alerts["操作失敗"].exists, "關閉 sheet 後不應再次跳出錯誤")

        // 3. 選取模式批次刪除：確認框從底部的刪除鈕彈出，刪除後離開選取模式
        app.buttons["更多"].tap()
        tapMenuItem("選取")
        XCTAssertTrue(app.buttons["全選"].waitForExistence(timeout: 3))
        lift(findCell("Spring.2019.Blender.Open.Movie.mkv")).tap()
        XCTAssertTrue(app.staticTexts["已選 1 項"].waitForExistence(timeout: 3))
        let barDelete = app.buttons["刪除"].firstMatch
        let barFrame = barDelete.frame
        barDelete.tap()
        XCTAssertTrue(app.buttons["刪除種子（保留檔案）"].waitForExistence(timeout: 3))
        assertAnchored(to: barFrame, "批次刪除的確認框應從底部刪除鈕彈出")
        shot("17_batch_delete")
        app.buttons["刪除種子（保留檔案）"].tap()
        XCTAssertTrue(app.buttons["更多"].waitForExistence(timeout: 5), "批次刪除後應離開選取模式")

        // 4. 詳情頁：刪除膠囊與右上「更多 → 刪除…」各自從按鈕彈出
        lift(findCell("archlinux-2026.10.01-x86_64.iso")).tap()
        let pill = app.buttons["刪除"].firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        let pillFrame = pill.frame
        pill.tap()
        assertAnchored(to: pillFrame, "詳情頁刪除膠囊的確認框應從膠囊彈出")
        shot("18_detail_delete_pill")
        dismissPopover()
        let more = app.navigationBars.buttons["更多"]
        let moreFrame = more.frame
        more.tap()
        tapMenuItem("刪除…")
        assertAnchored(to: moreFrame, "詳情頁選單刪除的確認框應從「更多」彈出")
        shot("19_detail_delete_menu")
        dismissPopover()

        // 5. 檔案分頁：點一下檔案就跳出優先順序選單
        app.segmentedControls.buttons["檔案"].tap()
        let file = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'README.txt'")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 5))
        file.tap()
        XCTAssertTrue(app.buttons["最高"].waitForExistence(timeout: 3), "點選檔案應出現優先順序選單")
        shot("20_file_priority")
        app.buttons["最高"].tap()
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'README.txt' AND label ENDSWITH '最高'"))
        XCTAssertTrue(updated.firstMatch.waitForExistence(timeout: 6), "選擇後檔案應顯示新的優先順序")
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

        // 有輸入內容時，取消要先確認是否捨棄；點外面繼續編輯
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["捨棄"].waitForExistence(timeout: 3), "有輸入內容時取消應先確認")
        dismissPopover()

        // 儲存新伺服器後直接進入
        app.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10), "新增伺服器後應直接進入")
        XCTAssertTrue(app.navigationBars["127.0.0.1"].exists)
    }

    /// 從「更多」或連線失敗畫面編輯伺服器，儲存後直接以新設定重新連線
    func testServerEditReconnect() throws {
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["更多"].tap()
        tapMenuItem("編輯伺服器…")
        replaceURL("http://127.0.0.1:9")
        app.buttons["儲存"].tap()
        XCTAssertTrue(app.staticTexts["無法連線"].waitForExistence(timeout: 15), "改成錯誤網址後應顯示連線失敗")
        shot("21_failed_edit")

        app.buttons["編輯伺服器"].tap()
        replaceURL("http://127.0.0.1:8080")
        app.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10), "改回正確網址後應重新載入清單")
    }

    private func replaceURL(_ url: String) {
        replaceText(app.textFields["http://192.168.1.10:8080"], with: url)
    }

    private func replaceText(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        // 點在欄位最右側讓游標落在結尾，再整段刪掉重打
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let old = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2) + text)
    }

    /// 經由代理連線：代理連不上時要失敗（證明沒有改走直連），指向測試代理後 HTTP 與 SOCKS5 都能連上，
    /// 儲存後清單也經過代理載入。需同時執行 scripts/test_proxy.py（127.0.0.1:18888）
    func testServerViaProxy() throws {
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["更多"].tap()
        tapMenuItem("編輯伺服器…")
        let toggle = app.switches["經由代理連線"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        toggle.switches.firstMatch.tap()
        // 開啟時可能帶入系統代理（例如 Surge），先換成測試用的位址，確認後才送出任何請求。
        // 先點連接埠讓表單捲到鍵盤上方，再改位址
        let port = app.textFields["連接埠"]
        replaceText(port, with: "1")
        replaceText(app.textFields["代理位址"], with: "127.0.0.1")
        XCTAssertEqual(port.value as? String, "1")
        XCTAssertEqual(app.textFields["代理位址"].value as? String, "127.0.0.1")

        let test = app.buttons["測試連線"]
        let ok = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '連線成功'")).firstMatch
        test.tap()
        sleep(3)
        XCTAssertFalse(ok.exists, "代理連不上時不應改走直連而成功")
        shot("22_proxy_unreachable")

        replaceText(port, with: "18888")
        test.tap()
        XCTAssertTrue(ok.waitForExistence(timeout: 10), "經由 HTTP 代理應連線成功")

        app.buttons["SOCKS5"].tap()
        test.tap()
        XCTAssertTrue(ok.waitForExistence(timeout: 10), "經由 SOCKS5 代理應連線成功")
        shot("23_proxy_socks5")

        app.buttons["儲存"].tap()
        XCTAssertTrue(app.buttons["chip.all"].waitForExistence(timeout: 10), "儲存後應經由代理重新載入清單")
        shot("24_proxy_list")
    }
}
