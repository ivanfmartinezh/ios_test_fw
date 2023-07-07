//
//  PinTests.swift
//  ProtonMailUITests
//
//  Created by mirage chung on 2020/12/17.
//  Copyright © 2020 Proton Mail. All rights reserved.
//

import XCTest
import ProtonCore_TestingToolkit

class PinTests: CleanAuthenticatedTestCase {

    private let correctPin = "0000"
    private let pinRobot: PinRobot = PinRobot()

    override func setUp() {
        super.setUp()

      InboxRobot()
            .menuDrawer()
            .settings()
            .pin()
            .enablePin()
            .setPin(correctPin)
    }
    
    func testTurnOnAndOffPin() {
        pinRobot
            .disablePin()
            .verify.isPinEnabled(false)
    }
    
    func testEnterCorrectPinCanUnlock() {
        pinRobot
            .backgroundApp()
            .foregroundApp()
            .confirmWithEmptyPin()
            .verify.emptyPinErrorMessageShows()
            .clickOK()
            .inputCorrectPin()
            .verify.inboxShown()
    }
    
    func testEnterIncorrectPinCantUnlock() {
        pinRobot
            .backgroundApp()
            .foregroundApp()
            .inputIncorrectPin()
            .verify.pinErrorMessageShows(1)
            .inputIncorrectPin()
            .verify.pinErrorMessageShows(2)
            .logout()
            .verify.loginScreenIsShown()
    }
    
    func testEnterEmptyPin() {
        pinRobot
            .backgroundApp()
            .foregroundApp()
            .confirmWithEmptyPin()
            .verify.emptyPinErrorMessageShows()
    }
    
    func testEnterIncorrectPinTenTimesLogOut() {
        pinRobot
            .backgroundApp()
            .foregroundApp()
            .inputIncorrectPinNTimes(count: 10)
            .verify.loginScreenIsShown()
    }
    
    func testIncorrectPinBeforeThirtySec() {
        pinRobot
            .pinTimer()
            .selectAutolockEveryTime()
            .navigateUpToSettings()
            .close()
            .backgroundApp()
            .activateAppWithPin()
            .inputCorrectPin()
            .backgroundApp()
            .activateAppWithPin()
            .inputIncorrectPin()
            .verify.pinErrorMessageShows(1)
    }

    func testErrorMessageOnThreeRmainingPinTries() {
        pinRobot
            .pinTimer()
            .selectAutolockEveryTime()
            .navigateUpToSettings()
            .close()
            .backgroundApp()
            .activateAppWithPin()
            .inputCorrectPin()
            .backgroundApp()
            .activateAppWithPin()
            .inputIncorrectPin()
            .verify.pinErrorMessageShows(1)
            .inputIncorrectPinNTimesStayLoggedIn(count: 6)
            .verify.pinErrorMessageShowsThreeRemainingTries(3)
    }

    func testLogoutBeforeUnlockingDoesNotCrash() {
        pinRobot
            .enableAppKey()
            .pinTimer()
            .selectAutolockEveryTime()
            .foregroundApp()
            .logout()
            .verify
            .loginScreenIsShown()
    }
}
