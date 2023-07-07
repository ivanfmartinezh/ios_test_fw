// Copyright (c) 2021 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import ProtonCore_DataModel
import ProtonCore_Services
import ProtonCore_TestingToolkit
@testable import ProtonMail
import XCTest

class UsersManagerHelperTest: XCTestCase {
    private var apiMock: APIService!
    private var doh: DohMock!

    override func setUpWithError() throws {
        self.apiMock = APIServiceMock()
        self.doh = DohMock()
    }

    override func tearDown() {
        self.apiMock = nil
        self.doh = nil
    }

    func testNumberOfFreeAccounts_allFreeUsers() throws {
        let user1 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let user2 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let users = UsersManager(doh: doh)
        users.add(newUser: user1)
        users.add(newUser: user2)
        XCTAssertEqual(users.numberOfFreeAccounts, 2)
    }

    func testNumberOfFreeAccounts_hasPaidUser() throws {
        let user1 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let user2 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.owner)
        let user3 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.member)
        let users = UsersManager(doh: doh)
        users.add(newUser: user1)
        users.add(newUser: user2)
        users.add(newUser: user3)
        XCTAssertEqual(users.numberOfFreeAccounts, 1)
    }

    func testIsAllowedNewUser_allowed() {
        let user1 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let user2 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.owner)
        let users = UsersManager(doh: doh)
        let userInfo = user1.userInfo
        XCTAssertTrue(users.isAllowedNewUser(userInfo: userInfo))

        let users2 = UsersManager(doh: doh)
        users2.add(newUser: user2)
        XCTAssertTrue(users2.isAllowedNewUser(userInfo: userInfo))
    }

    func testIsAllowedNewUser_notAllowed() {
        let user1 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let user2 = UserManager(api: apiMock, role: UserInfo.OrganizationRole.none)
        let users = UsersManager(doh: doh)
        users.add(newUser: user1)
        let userInfo = user2.userInfo
        XCTAssertFalse(users.isAllowedNewUser(userInfo: userInfo))
    }
}
