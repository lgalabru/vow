import XCTest

@MainActor
final class VowUITests: XCTestCase {
  override func setUpWithError() throws { continueAfterFailure = false }
  private func launch(_ app: XCUIApplication) {
    #if os(iOS)
      XCUIDevice.shared.orientation = .portrait
      if !app.launchArguments.contains(where: { $0.hasPrefix("--ui-test-onboarding=") }) {
        app.launchArguments.append("--ui-test-onboarding=completed")
      }
      if !app.launchArguments.contains(where: { $0.hasPrefix("--ui-test-security-key=") }) {
        app.launchArguments.append("--ui-test-security-key=connected")
      }
      if !app.launchArguments.contains(where: { $0.hasPrefix("--ui-test-network=") }) {
        app.launchArguments.append("--ui-test-network=offline")
      }
    #endif
    app.launch()
  }
  private func capture(_ app: XCUIApplication, _ name: String) {
    #if os(macOS)
      let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    #else
      let attachment = XCTAttachment(screenshot: app.screenshot())
    #endif
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func testPrototypeFlow() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    launch(app)
    #if os(macOS)
      XCTAssertTrue(app.staticTexts["Organization setup"].waitForExistence(timeout: 10))
      capture(app, "Mac — Ceremony overview")
      app.buttons["Set Up…"].firstMatch.click()
      XCTAssertTrue(app.buttons["Complete Sample Enrollment"].waitForExistence(timeout: 5))
      app.buttons["Complete Sample Enrollment"].click()
      let review = app.outlines.buttons["Review ceremony"]
      if review.exists {
        review.click()
      } else {
        app.staticTexts["Review ceremony"].firstMatch.click()
      }
      XCTAssertTrue(app.buttons["Confirm Sample Ceremony"].waitForExistence(timeout: 5))
      app.buttons["Confirm Sample Ceremony"].click()
      XCTAssertTrue(app.staticTexts["Sample ceremony complete"].waitForExistence(timeout: 5))
      capture(app, "Mac — Ceremony confirmed")
    #else
      openSampleProject(app)
      XCTAssertTrue(app.buttons["Load Sample Request"].waitForExistence(timeout: 15))
      app.buttons["Load Sample Request"].tap()
      XCTAssertTrue(app.buttons["Review & Approve"].waitForExistence(timeout: 5))
      assertFooterSeparation(app, action: app.buttons["Review & Approve"])
      let countdown = app.buttons["requestCountdown"]
      XCTAssertTrue(countdown.waitForExistence(timeout: 5))
      let network = app.buttons["networkStatus"]
      XCTAssertEqual(countdown.frame.midY, network.frame.midY, accuracy: 2)
      XCTAssertGreaterThan(countdown.frame.minX, network.frame.maxX)
      capture(app, "iPad — Review request")
      app.buttons["Review & Approve"].tap()
      XCTAssertTrue(app.staticTexts["Review request"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.buttons.matching(identifier: "networkStatus").count, 1)
      XCTAssertEqual(app.buttons.matching(identifier: "requestCountdown").count, 1)
      assertFooterSeparation(app, action: app.buttons["Continue"], inline: true)
      XCTAssertEqual(
        app.buttons["Continue"].frame.maxX,
        app.windows.firstMatch.frame.maxX - 16, accuracy: 3)
      app.buttons["Continue"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["authorizationRequestPanel"].firstMatch.waitForExistence(
          timeout: 5))
      XCTAssertFalse(app.buttons["authorizeApproval"].isEnabled)
      assertFooterSeparation(app, action: app.buttons["authorizeApproval"], inline: true)
      capture(app, "iPad — Handwritten consent")
      let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(canvas.waitForExistence(timeout: 5))
      let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
      let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35))
      start.press(forDuration: 0.1, thenDragTo: end)
      let approve = app.buttons["authorizeApproval"]
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: approve)
      waitForExpectations(timeout: 5)
      XCTAssertTrue(app.staticTexts["Consent checks passed"].exists)
      XCTAssertFalse(app.buttons["Continue"].exists)
      app.buttons["Clear"].tap()
      XCTAssertFalse(approve.isEnabled)
      start.press(forDuration: 0.1, thenDragTo: end)
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: approve)
      waitForExpectations(timeout: 5)
      app.buttons["Back"].tap()
      XCTAssertTrue(app.staticTexts["Review request"].waitForExistence(timeout: 5))
      app.buttons["Continue"].tap()
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: approve)
      waitForExpectations(timeout: 5)
      assertFooterSeparation(app, action: approve, inline: true)
      capture(app, "iPad — Consent checks passed to authorize")
      approve.tap()
      XCTAssertTrue(app.staticTexts["Approval created"].waitForExistence(timeout: 10))
      XCTAssertTrue(app.buttons["Share Approval"].waitForExistence(timeout: 5))
      assertFooterSeparation(app, action: app.buttons["Share Approval"], inline: true)
      capture(app, "iPad — Approval created")
    #endif
  }
  #if os(iOS)
    private func assertFooterSeparation(
      _ app: XCUIApplication, action: XCUIElement, inline: Bool = false,
      file: StaticString = #filePath, line: UInt = #line
    ) {
      let status = app.buttons["networkStatus"]
      XCTAssertEqual(
        app.buttons.matching(identifier: "networkStatus").count, 1, file: file, line: line)
      XCTAssertTrue(action.exists, file: file, line: line)
      if inline {
        XCTAssertEqual(action.frame.midY, status.frame.midY, accuracy: 3, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
          action.frame.minX, status.frame.maxX + 8, file: file, line: line)
      } else {
        XCTAssertLessThanOrEqual(
          action.frame.maxY + 8, status.frame.minY,
          "Action buttons must sit above the connection strip with a visible gap.", file: file,
          line: line)
      }
    }
    private func setConnection(_ app: XCUIApplication, connected: Bool) {
      app.buttons["testConnection"].tap()
      app.buttons[connected ? "Connect" : "Disconnect"].tap()
    }
    func testNetworkGateAndAutomaticUnlock() throws {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-network=online"]
      launch(app)
      XCTAssertTrue(app.staticTexts["Network connection detected"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.buttons["project-project-grants"].exists)
      XCTAssertEqual(app.buttons.matching(identifier: "networkStatus").count, 1)
      capture(app, "iPad — Connection lock")
      setConnection(app, connected: false)
      XCTAssertTrue(app.staticTexts["Signing workspace"].waitForExistence(timeout: 5))
      XCTAssertEqual(app.buttons.matching(identifier: "networkStatus").count, 1)
      openSampleProject(app)
      app.buttons["Load Sample Request"].tap()
      app.buttons["Review & Approve"].tap()
      XCTAssertTrue(app.staticTexts["Review request"].waitForExistence(timeout: 5))
      app.buttons["Continue"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["authorizationRequestPanel"].firstMatch.waitForExistence(
          timeout: 5))
      setConnection(app, connected: true)
      XCTAssertTrue(app.staticTexts["Network connection detected"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.descendants(matching: .any)["authorizationRequestPanel"].firstMatch.exists)
      XCTAssertEqual(app.buttons.matching(identifier: "networkStatus").count, 1)
      setConnection(app, connected: false)
      openSampleProject(app)
      app.buttons["Review & Approve"].tap()
      XCTAssertTrue(app.staticTexts["Review request"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.descendants(matching: .any)["authorizationRequestPanel"].firstMatch.exists)
    }
    func testReconnectionCancelsAnInFlightApproval() throws {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-network=offline", "--ui-test-signing-delay"]
      launch(app)
      openSampleProject(app)
      app.buttons["Load Sample Request"].tap()
      app.buttons["Review & Approve"].tap()
      XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
      app.buttons["Continue"].tap()
      let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(canvas.waitForExistence(timeout: 5))
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
        forDuration: 0.1,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)))
      let authorize = app.buttons["authorizeApproval"]
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: authorize)
      waitForExpectations(timeout: 5)
      authorize.tap()
      XCTAssertTrue(app.buttons["Authorizing…"].waitForExistence(timeout: 3))
      assertFooterSeparation(app, action: app.buttons["Authorizing…"], inline: true)
      capture(app, "iPad — Signing footer")
      setConnection(app, connected: true)
      XCTAssertTrue(app.staticTexts["Network connection detected"].waitForExistence(timeout: 5))
      setConnection(app, connected: false)
      openSampleProject(app)
      XCTAssertTrue(app.buttons["Review & Approve"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts["Approval created"].exists)
      // Retry proves the retained device key still matches the Rust session.
      app.buttons["Review & Approve"].tap()
      XCTAssertTrue(app.staticTexts["Review request"].waitForExistence(timeout: 5))
      app.buttons["Continue"].tap()
      let freshCanvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(freshCanvas.waitForExistence(timeout: 5))
      freshCanvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
        forDuration: 0.1,
        thenDragTo: freshCanvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)))
      expectation(
        for: NSPredicate(format: "enabled == true"), evaluatedWith: app.buttons["authorizeApproval"]
      )
      waitForExpectations(timeout: 5)
      app.buttons["authorizeApproval"].tap()
      XCTAssertTrue(app.staticTexts["Approval created"].waitForExistence(timeout: 15))
    }
    func testYubiKeyPresenceGatesAndRemovalCancelsAuthorization() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=missing", "--ui-test-signing-delay",
      ]
      launch(app)
      openSampleProject(app)
      app.buttons["Load Sample Request"].tap()
      app.buttons["Review & Approve"].tap()
      app.buttons["Continue"].tap()
      let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(canvas.waitForExistence(timeout: 5))
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
        forDuration: 0.1,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)))
      XCTAssertTrue(app.staticTexts["Consent checks passed"].waitForExistence(timeout: 5))
      let authorize = app.buttons["authorizeApproval"]
      XCTAssertFalse(authorize.exists)
      XCTAssertTrue(app.descendants(matching: .any)["yubiKeyInsertionPrompt"].firstMatch.exists)
      capture(app, "iPad — Connect YubiKey animation")
      app.buttons["testConnection"].tap()
      app.buttons["Plug in YubiKey"].tap()
      XCTAssertTrue(authorize.waitForExistence(timeout: 5))
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: authorize)
      waitForExpectations(timeout: 5)
      capture(app, "iPad — YubiKey enables authorization")
      app.buttons["testConnection"].tap()
      app.buttons["Unplug YubiKey"].tap()
      XCTAssertFalse(authorize.exists)
      app.buttons["testConnection"].tap()
      app.buttons["Plug in YubiKey"].tap()
      XCTAssertTrue(authorize.waitForExistence(timeout: 5))
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: authorize)
      waitForExpectations(timeout: 5)
      authorize.tap()
      XCTAssertTrue(app.buttons["Authorizing…"].waitForExistence(timeout: 3))
      app.buttons["testConnection"].tap()
      app.buttons["Unplug YubiKey"].tap()
      XCTAssertTrue(
        app.staticTexts["The YubiKey connection changed. Close this approval and review it again."]
          .waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts["Approval created"].exists)
      XCTAssertTrue(
        app.descendants(matching: .any)["yubiKeyInsertionPrompt"].firstMatch.waitForExistence(
          timeout: 5))
      capture(app, "iPad — YubiKey removal interrupts authorization")
    }
    private func openSampleProject(_ app: XCUIApplication) {
      let project = app.buttons["project-project-grants"]
      let request = app.buttons["Review & Approve"]
      let available = XCTNSPredicateExpectation(
        predicate: NSPredicate { _, _ in
          project.exists || request.exists
        }, object: nil)
      XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 15), .completed)
      if project.exists { project.tap() }
    }
    func testProjectHomeNavigation() throws {
      let app = XCUIApplication()
      launch(app)
      XCTAssertTrue(app.staticTexts["Signing workspace"].waitForExistence(timeout: 10))
      capture(app, "iPad — Project home")
      app.buttons["project-project-operations"].tap()
      XCTAssertTrue(app.buttons["Load Sample Request"].waitForExistence(timeout: 5))
      app.buttons["Load Sample Request"].tap()
      XCTAssertTrue(app.buttons["Review & Approve"].waitForExistence(timeout: 5))
      app.buttons["openProjects"].tap()
      openSampleProject(app)
      XCTAssertTrue(app.buttons["Load Sample Request"].waitForExistence(timeout: 5))
      app.buttons["openProjects"].tap()
      app.buttons["project-project-operations"].tap()
      XCTAssertTrue(app.buttons["Review & Approve"].waitForExistence(timeout: 5))
      let status = app.buttons["networkStatus"].firstMatch
      XCTAssertTrue(status.exists)
      status.tap()
      XCTAssertTrue(
        app.staticTexts["How connection detection works"].waitForExistence(timeout: 5)
          || app.buttons["How connection detection works"].exists)
      capture(app, "iPad — Offline guidance")
    }
  #endif
  #if os(iOS)
    func testOnboardingPersistsDeviceAndRegisteredKeyAcrossRelaunch() throws {
      try completeOnboardingAndSign(usesFIDO: false)
    }
    func testNativeSecurityKeyEnrollmentAndSigningUseNoAppPINField() throws {
      try completeNativeEnrollmentAndSign()
    }
    func testNativeKeyRemovalPreventsApprovalCompletion() throws {
      try completeNativeEnrollmentAndSign(removingKeyDuringApproval: true)
    }
    private func completeNativeEnrollmentAndSign(removingKeyDuringApproval: Bool = false) throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=connected",
        "--ui-test-onboarding=required", "--ui-test-identity=\(UUID().uuidString)",
        "--ui-test-native-security-key", "--ui-test-open-device",
      ]
      launch(app)
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.buttons["restoreNativeKey"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.secureTextFields["onboardingPIN"].exists)
      capture(app, "iPad — Native security-key setup")
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["Confirm this iPad"].waitForExistence(timeout: 5))
      app.buttons["Signing details"].tap()
      let publicKey = app.staticTexts["onboardingDevicePublicKey"].label
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["devicePublicKey"].waitForExistence(timeout: 5))
      app.terminate()
      if removingKeyDuringApproval { app.launchArguments.append("--ui-test-signing-delay") }
      launch(app)
      XCTAssertTrue(app.staticTexts["devicePublicKey"].waitForExistence(timeout: 10))
      XCTAssertEqual(app.staticTexts["devicePublicKey"].label, publicKey)
      app.buttons["openProjects"].tap()
      openSampleProject(app)
      app.buttons["Load Sample Request"].tap()
      app.buttons["Review & Approve"].tap()
      app.buttons["Continue"].tap()
      let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(canvas.waitForExistence(timeout: 5))
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
        forDuration: 0.1,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)))
      let authorize = app.buttons["authorizeApproval"]
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: authorize)
      waitForExpectations(timeout: 5)
      authorize.tap()
      if removingKeyDuringApproval {
        XCTAssertTrue(app.buttons["Authorizing…"].waitForExistence(timeout: 3))
        app.buttons["testConnection"].tap()
        app.buttons["Unplug YubiKey"].tap()
        XCTAssertTrue(
          app.staticTexts[
            "The YubiKey connection changed. Close this approval and review it again."
          ].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Approval created"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["Share Approval"].exists)
        capture(app, "iPad — Native key removal blocks completion")
        return
      }
      XCTAssertTrue(app.staticTexts["Approval created"].waitForExistence(timeout: 10))
      XCTAssertFalse(app.alerts.secureTextFields.firstMatch.exists)
      capture(app, "iPad — Native security-key approval")
    }
    func testCancelledNativeSecurityKeySetupDoesNotEnrollDevice() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=connected",
        "--ui-test-onboarding=required", "--ui-test-identity=\(UUID().uuidString)",
        "--ui-test-native-security-key", "--ui-test-native-cancel",
      ]
      launch(app)
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.buttons["restoreNativeKey"].waitForExistence(timeout: 5))
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.buttons["restoreNativeKey"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts["Confirm this iPad"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingPIN"].exists)
    }
    func testFIDOProbeFailureDoesNotDowngradeSigningMethod() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=connected",
        "--ui-test-onboarding=required", "--ui-test-identity=\(UUID().uuidString)",
        "--ui-test-fido2-probe-error",
      ]
      launch(app)
      app.buttons["onboardingContinue"].tap()
      app.buttons["onboardingContinue"].tap()
      let error = app.descendants(matching: .any)["onboardingError"].firstMatch
      XCTAssertTrue(error.waitForExistence(timeout: 5))
      XCTAssertTrue(error.label.contains("FIDO_RESPONSE"))
      XCTAssertFalse(app.staticTexts["This key needs one-time setup on your Mac"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingPIN"].exists)
    }
    func testUnconfiguredSmartCardExplainsSetupWithoutPINOrManagementFields() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=connected",
        "--ui-test-onboarding=required", "--ui-test-identity=\(UUID().uuidString)",
        "--ui-test-smartcard-unconfigured",
      ]
      launch(app)
      app.buttons["onboardingContinue"].tap()
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(
        app.staticTexts["This key needs one-time setup on your Mac"].waitForExistence(timeout: 5))
      XCTAssertFalse(app.secureTextFields["onboardingPIN"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingNewPIN"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingManagementKey"].exists)
      XCTAssertTrue(app.buttons["onboardingContinue"].isEnabled)
      capture(app, "iPad — Clear legacy key setup")
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["This key needs one-time setup on your Mac"].exists)
    }
    func testFIDOOnboardingRestoresIdentityAndUsesExistingPIN() throws {
      try completeOnboardingAndSign(usesFIDO: true)
    }
    private func completeOnboardingAndSign(usesFIDO: Bool) throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=connected",
        "--ui-test-onboarding=required", "--ui-test-identity=\(UUID().uuidString)",
        "--ui-test-open-device",
      ]
      if usesFIDO { app.launchArguments.append("--ui-test-fido2") }
      launch(app)
      XCTAssertTrue(app.staticTexts["Set up this iPad"].waitForExistence(timeout: 10))
      let progress = app.descendants(matching: .any)["compactSetupProgress"].firstMatch
      XCTAssertTrue(progress.exists)
      XCTAssertLessThanOrEqual(progress.frame.height, 44)
      capture(app, "iPad — Device enrollment")
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["Connect your security key"].waitForExistence(timeout: 5))
      app.buttons["onboardingContinue"].tap()
      let pin = app.secureTextFields["onboardingPIN"]
      XCTAssertTrue(pin.waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["existingPINPreserved"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingNewPIN"].exists)
      XCTAssertFalse(app.secureTextFields["onboardingManagementKey"].exists)
      XCTAssertGreaterThanOrEqual(pin.frame.height, 56)
      pin.tap()
      XCTAssertFalse(app.descendants(matching: .any)["compactSetupProgress"].firstMatch.exists)
      XCTAssertFalse(app.buttons["onboardingContinue"].exists)
      XCTAssertFalse(app.buttons["networkStatus"].exists)
      XCTAssertFalse(app.buttons["Back"].exists)
      XCTAssertTrue(pin.isHittable)
      capture(app, "iPad — Focused PIV PIN")
      pin.typeText("111111")
      app.buttons["Done"].tap()
      XCTAssertTrue(app.buttons["networkStatus"].waitForExistence(timeout: 5))
      XCTAssertLessThan(app.buttons["networkStatus"].frame.width, 220)
      assertFooterSeparation(app, action: app.buttons["Back"])
      capture(app, "iPad — Floating connection pill")
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(
        app.descendants(matching: .any)["onboardingError"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertFalse(app.staticTexts["Confirm this iPad"].exists)
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(pin.waitForExistence(timeout: 5))
      pin.tap()
      pin.typeText("654321")
      app.buttons["Done"].tap()
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["Confirm this iPad"].waitForExistence(timeout: 5))
      app.buttons["Signing details"].tap()
      let publicKey = app.staticTexts["onboardingDevicePublicKey"].label
      XCTAssertEqual(publicKey.count, 66)
      capture(app, "iPad — Verify enrolled keys")
      app.buttons["onboardingContinue"].tap()
      XCTAssertTrue(app.staticTexts["devicePublicKey"].waitForExistence(timeout: 10))
      XCTAssertEqual(app.staticTexts["devicePublicKey"].label, publicKey)
      XCTAssertTrue(app.buttons["shareEnrollment"].exists)
      app.terminate()
      launch(app)
      XCTAssertTrue(app.staticTexts["devicePublicKey"].waitForExistence(timeout: 10))
      XCTAssertEqual(app.staticTexts["devicePublicKey"].label, publicKey)
      XCTAssertTrue(app.buttons["shareEnrollment"].exists)
      XCTAssertFalse(app.staticTexts["Set up this iPad"].exists)
      capture(app, "iPad — Restored signing identity")
      app.buttons["openProjects"].tap()
      openSampleProject(app)
      app.buttons["Load Sample Request"].tap()
      app.buttons["Review & Approve"].tap()
      app.buttons["Continue"].tap()
      let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
      XCTAssertTrue(canvas.waitForExistence(timeout: 5))
      canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
        forDuration: 0.1,
        thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)))
      let authorize = app.buttons["authorizeApproval"]
      expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: authorize)
      waitForExpectations(timeout: 5)
      authorize.tap()
      let approvalPIN = app.alerts.secureTextFields.firstMatch
      XCTAssertTrue(approvalPIN.waitForExistence(timeout: 5))
      approvalPIN.typeText("654321")
      app.alerts.buttons["Verify & Authenticate"].tap()
      XCTAssertTrue(app.staticTexts["Approval created"].waitForExistence(timeout: 10))
      capture(app, "iPad — Registered-key approval")
    }
    func testAuthorizationPanelsFitWithoutScrolling() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "--ui-test-network=offline", "--ui-test-security-key=missing", "--show-sample",
      ]
      launch(app)
      app.buttons["Review & Approve"].tap()
      app.buttons["Continue"].tap()
      for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
        XCUIDevice.shared.orientation = orientation
        let rotated = XCTNSPredicateExpectation(
          predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return orientation == .portrait
              ? frame.height > frame.width : frame.width > frame.height
          }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 5), .completed)
        let left = app.descendants(matching: .any)["authorizationRequestPanel"].firstMatch
        let right = app.descendants(matching: .any)["authorizationSignaturePanel"].firstMatch
        let canvas = app.descendants(matching: .any)["consentCanvas"].firstMatch
        XCTAssertTrue(left.waitForExistence(timeout: 5))
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(right.frame.minX, left.frame.maxX)
        XCTAssertEqual(left.frame.minY, right.frame.minY, accuracy: 3)
        XCTAssertGreaterThanOrEqual(canvas.frame.height, 120)
        let footer = app.descendants(matching: .any)["yubiKeyInsertionPrompt"].firstMatch
        XCTAssertLessThanOrEqual(canvas.frame.maxY, footer.frame.minY - 8)
        let digest = app.staticTexts["authorizationDigest"]
        XCTAssertTrue(digest.isHittable)
        XCTAssertLessThanOrEqual(digest.frame.maxY, footer.frame.minY - 8)
        capture(
          app,
          orientation == .portrait
            ? "iPad — Authorization portrait" : "iPad — Authorization landscape")
      }
      XCUIDevice.shared.orientation = .portrait
    }
    func testCompactLandscape() throws {
      let app = XCUIApplication()
      launch(app)
      openSampleProject(app)
      XCTAssertTrue(app.buttons["Load Sample Request"].waitForExistence(timeout: 15))
      app.buttons["Load Sample Request"].tap()
      XCUIDevice.shared.orientation = .landscapeLeft
      defer { XCUIDevice.shared.orientation = .portrait }
      XCTAssertTrue(app.buttons["Review & Approve"].waitForExistence(timeout: 5))
      expectation(
        for: NSPredicate { _, _ in
          app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, evaluatedWith: app)
      waitForExpectations(timeout: 5)
      assertFooterSeparation(app, action: app.buttons["Review & Approve"])
      capture(app, "iPad — Compact landscape")
    }
  #endif

  func testLocalExplanation() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
    ]
    launch(app)
    #if os(macOS)
      let requests = app.outlines.buttons["Requests"]
      if requests.exists {
        requests.click()
      } else {
        app.staticTexts["Requests"].firstMatch.click()
      }
      XCTAssertTrue(app.buttons["Create Sample Request"].waitForExistence(timeout: 5))
      app.buttons["Create Sample Request"].click()
      app.buttons["Explain Request"].click()
    #else
      openSampleProject(app)
      XCTAssertTrue(app.buttons["Load Sample Request"].waitForExistence(timeout: 15))
      app.buttons["Load Sample Request"].tap()
      app.buttons["explainRequest"].tap()
    #endif
    XCTAssertTrue(app.staticTexts["Decoded facts"].firstMatch.waitForExistence(timeout: 10))
    let generate = app.buttons["generateLocalExplanation"]
    XCTAssertTrue(generate.waitForExistence(timeout: 5))
    #if os(iOS)
      assertFooterSeparation(app, action: generate)
    #endif
    if generate.isEnabled {
      #if os(macOS)
        generate.click()
      #else
        generate.tap()
      #endif
      XCTAssertTrue(app.staticTexts["On-device explanation"].waitForExistence(timeout: 60))
      capture(app, "On-device explanation")
    } else {
      XCTAssertTrue(app.staticTexts["On-device explanation unavailable"].exists)
      capture(app, "Local model availability")
    }
  }

  #if os(iOS)
    func testImportedBundleReplaysOffline() throws {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-network=offline", "--ui-test-import-fixture"]
      launch(app)
      XCTAssertTrue(app.staticTexts["SOL transfer"].firstMatch.waitForExistence(timeout: 15))
      XCTAssertTrue(app.staticTexts["0.25"].firstMatch.exists)
      let replay = app.buttons["replayTransaction"]
      for _ in 0..<5 where !replay.isHittable { app.swipeUp() }
      XCTAssertTrue(replay.waitForExistence(timeout: 5))
      replay.tap()
      XCTAssertTrue(app.staticTexts["Replay matches"].waitForExistence(timeout: 15))
      capture(app, "iPad — Imported Surfpool replay")
    }
    func testPlainChannelDumpInspection() throws {
      let app = XCUIApplication()
      app.launchArguments = ["--ui-test-network=offline", "--ui-test-import-channel"]
      launch(app)
      XCTAssertTrue(
        app.staticTexts["Open payment channel"].firstMatch.waitForExistence(timeout: 15))
      XCTAssertEqual(app.buttons["requestCountdown"].label, "Expiry unavailable")
      XCTAssertFalse(app.buttons["authorizeApproval"].exists)
      XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
      capture(app, "iPad — Plain channel transaction dump")
    }
  #endif

  #if os(macOS)
    func testBrowserTransactionPreparation() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      ]
      launch(app)
      let apps = app.outlines.buttons["Apps"]
      XCTAssertTrue(apps.waitForExistence(timeout: 10))
      apps.click()
      let connect = app.webViews.buttons["Connect Vow"]
      XCTAssertTrue(connect.waitForExistence(timeout: 15))
      connect.click()
      let permission = app.buttons["Connect Preview Account"]
      XCTAssertTrue(permission.waitForExistence(timeout: 5))
      permission.click()
      let sign = app.webViews.buttons["Sign transaction"]
      XCTAssertTrue(sign.waitForExistence(timeout: 5))
      sign.click()
      XCTAssertTrue(app.staticTexts["Transaction review"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["0.25 SOL"].exists)
      capture(app, "Mac — Captured transaction")
      let refresh = app.buttons["refreshBlockhash"]
      XCTAssertTrue(refresh.isHittable)
      refresh.click()
      XCTAssertTrue(app.buttons["requestCountdown"].waitForExistence(timeout: 35))
      capture(app, "Mac — Blockhash observation and countdown")
      app.buttons["Continue"].click()
      let profile = app.buttons["profileInSurfpool"]
      XCTAssertTrue(profile.waitForExistence(timeout: 5))
      profile.click()
      XCTAssertTrue(app.staticTexts["Independent replay matches"].waitForExistence(timeout: 45))
      capture(app, "Mac — Surfpool reproduction")
      app.buttons["Continue"].click()
      XCTAssertTrue(app.staticTexts["Execution requirements"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Enforce quorum and attestation policy"].exists)
      app.buttons["Continue"].click()
      XCTAssertTrue(
        app.descendants(matching: .any)["transactionFileTile"].waitForExistence(timeout: 5))
      XCTAssertTrue(app.buttons["Save File…"].exists)
      capture(app, "Mac — Draggable Vow file")
      app.buttons["Done"].click()
      XCTAssertTrue(
        app.webViews.staticTexts["Prepared in Vow. No transaction was signed or submitted."]
          .waitForExistence(timeout: 5))
    }
    func testOrganizationAndReusableProjectQuorums() throws {
      let app = XCUIApplication()
      app.launchArguments = [
        "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO",
      ]
      launch(app)
      XCTAssertTrue(app.staticTexts["Organization setup"].waitForExistence(timeout: 10))
      app.buttons["New Project…"].click()
      let name = app.textFields["workspaceName"]
      XCTAssertTrue(name.waitForExistence(timeout: 5))
      name.click()
      name.typeText("Research")
      if app.radioButtons["Create new"].exists {
        app.radioButtons["Create new"].click()
      } else {
        app.buttons["Create new"].click()
      }
      let quorumName = app.textFields["quorumName"]
      XCTAssertTrue(quorumName.waitForExistence(timeout: 5))
      quorumName.click()
      quorumName.typeText("Research quorum")
      XCTAssertFalse(app.checkBoxes["quorum-member-3"].isEnabled)
      app.checkBoxes["quorum-member-1"].click()
      app.checkBoxes["quorum-member-2"].click()
      capture(app, "Mac — Compose a project quorum")
      app.buttons["Create"].click()
      XCTAssertTrue(app.staticTexts["Research · Devnet"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Research quorum · 2 of 2 approvals"].exists)
      app.buttons["New Project…"].click()
      XCTAssertTrue(name.waitForExistence(timeout: 5))
      name.click()
      name.typeText("Research grants")
      app.popUpButtons["existingQuorum"].click()
      app.menuItems["Research quorum · 2 of 2 approvals"].click()
      app.buttons["Create"].click()
      XCTAssertTrue(
        app.staticTexts["Research grants · Devnet"].firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.staticTexts["Research quorum · 2 of 2 approvals"].exists)
      capture(app, "Mac — Reused project quorum")
      app.descendants(matching: .any)["organizationSwitcher"].firstMatch.click()
      app.menuItems["New Organization…"].click()
      XCTAssertTrue(name.waitForExistence(timeout: 5))
      name.click()
      name.typeText("Research lab")
      app.buttons["Create"].click()
      XCTAssertTrue(app.staticTexts["Research lab"].firstMatch.waitForExistence(timeout: 5))
      capture(app, "Mac — New organization")
    }
  #endif

}
