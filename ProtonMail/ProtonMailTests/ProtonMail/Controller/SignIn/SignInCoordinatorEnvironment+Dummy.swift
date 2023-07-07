//
//  SignInCoordinatorEnvironment+Dummy.swift
//  ProtonMailTests
//
//  Created by Krzysztof Siejkowski on 27/05/2021.
//  Copyright © 2021 Proton Mail. All rights reserved.
//

import Foundation
import PromiseKit
import ProtonCore_Crypto
import ProtonCore_DataModel
import ProtonCore_Doh
import ProtonCore_Login
import ProtonCore_Networking
import ProtonCore_Services
import ProtonCore_TestingToolkit

@testable import ProtonMail

extension SignInCoordinatorEnvironment {
    static var dummyMailboxPassword: (Passphrase, AuthCredential) -> Passphrase {{ pass, _ in pass }}

    static var dummyCurrentAuth: () -> AuthCredential? {{ nil }}

    static var dummyTryRestoringPersistedUser: () -> Void {{ }}

    static var dummyFinalizeSignIn: (LoginData, @escaping (NSError) -> Void, () -> Void, @escaping () -> Void) -> Void {{ _, _, _, _ in }}

    static var dummyUnlockIfRememberedCredentials: (String?, () -> Void, (() -> Void)?, (() -> Void)?) -> Void {{ _, _, _, _ in }}

    static var dummySaveLoginData: (LoginData) -> SignInManager.LoginDataSavingResult {{ _ in return .success }}

    static func test(
        login: @escaping LoginCreationClosure,
        mailboxPassword: @escaping (Passphrase, AuthCredential) -> Passphrase = dummyMailboxPassword,
        currentAuth: @escaping () -> AuthCredential? = dummyCurrentAuth,
        tryRestoringPersistedUser: @escaping () -> Void = dummyTryRestoringPersistedUser,
        finalizeSignIn: @escaping (LoginData, @escaping (NSError) -> Void, () -> Void, @escaping () -> Void) -> Void = dummyFinalizeSignIn,
        unlockIfRememberedCredentials: @escaping (String?, () -> Void, (() -> Void)?, (() -> Void)?) -> Void = dummyUnlockIfRememberedCredentials,
        saveLoginData: @escaping (LoginData) -> SignInManager.LoginDataSavingResult = dummySaveLoginData
    ) -> SignInCoordinatorEnvironment {
        let apiMock = APIServiceMock()
        let dohMock = DohMock()
        apiMock.dohStub.fixture = dohMock
        apiMock.dohInterfaceStub.fixture = dohMock
        return .init(services: ServiceFactory(),
                     apiService: apiMock,
                     mailboxPassword: mailboxPassword,
                     currentAuth: currentAuth,
                     tryRestoringPersistedUser: tryRestoringPersistedUser,
                     finalizeSignIn: finalizeSignIn,
                     unlockIfRememberedCredentials: unlockIfRememberedCredentials,
                     loginCreationClosure: login,
                     shouldShowAlertOnError: false,
                     saveLoginData: saveLoginData
        )
    }
}
