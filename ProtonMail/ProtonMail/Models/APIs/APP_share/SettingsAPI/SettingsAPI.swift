//
//  SettingAPI.swift
//  Proton Mail - Created on 7/13/15.
//
//
//  Copyright (c) 2019 Proton AG
//
//  This file is part of Proton Mail.
//
//  Proton Mail is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Proton Mail is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Proton Mail.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import ProtonCore_DataModel
import ProtonCore_Networking

/**
 [Settings API Part 1]:
 https://github.com/ProtonMail/Slim-API/blob/develop/api-spec/pm_api_mail_settings.md
 [Settings API Part 2]:
 https://github.com/ProtonMail/Slim-API/blob/develop/api-spec/pm_api_settings.md
 
 Settings API
 - Doc: [Settings API Part 1], [Settings API Part 2]
 */
struct SettingsAPI {
    /// base settings api path
    static let path: String = "/\(Constants.App.API_PREFIXED)/settings"

    static let settingsPath: String = "/settings"

    static let versionPrefix: String = "/mail/v4"
}

// Mark : get settings -- SettingsResponse
final class GetUserSettings: Request {
    var path: String {
        return SettingsAPI.settingsPath
    }

    // custom auth credentical
    var auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }
}

final class SettingsResponse: Response {
    var userSettings: [String: Any]?
    override func ParseResponse(_ response: [String: Any]!) -> Bool {
        if let settings = response["UserSettings"] as? [String: Any] {
            self.userSettings = settings
        }
        return true
    }
}

// Mark : get mail settings -- MailSettingsResponse
final class GetMailSettings: Request {
    var path: String {
        return SettingsAPI.path
    }

    // custom auth credentical
    var auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }
}

final class MailSettingsResponse: Response {
    var mailSettings: [String: Any]?
    override func ParseResponse(_ response: [String: Any]!) -> Bool {
        if let settings = response["MailSettings"] as? [String: Any] {
            self.mailSettings = settings
        }
        return true
    }
}

// MARK: update email notifiy - Response
final class UpdateNotify: Request {
    let notify: Int
    init(notify: Int, authCredential: AuthCredential?) {
        self.notify = notify
        self.auth = authCredential
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }
    var parameters: [String: Any]? {
        let out: [String: Any] = ["Notify": self.notify]
        return out
    }

    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return SettingsAPI.settingsPath + "/email/notify"
    }
}

// MARK: update email signature - Response
final class UpdateSignature: Request {
    let signature: String
    init(signature: String, authCredential: AuthCredential?) {
        self.signature = signature
        self.auth = authCredential
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }

    var parameters: [String: Any]? {
        let out: [String: Any] = ["Signature": self.signature]
        return out
    }

    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return SettingsAPI.path + "/signature"
    }
}

// MARK: update notification email -- Response
final class UpdateNotificationEmail: Request {

    let email: String

    let clientEphemeral: String // base64 encoded
    let clientProof: String // base64 encoded
    let SRPSession: String // hex encoded session id
    let tfaCode: String? // optional

    init(clientEphemeral: String!, clientProof: String, sRPSession: String, notificationEmail: String,
         tfaCode: String?, authCredential: AuthCredential?) {
        self.clientEphemeral = clientEphemeral
        self.clientProof = clientProof
        self.SRPSession = sRPSession
        self.email = notificationEmail
        self.tfaCode = tfaCode

        self.auth = authCredential
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }

    var parameters: [String: Any]? {

        var out: [String: Any] = [
            "ClientEphemeral": self.clientEphemeral,
            "ClientProof": self.clientProof,
            "SRPSession": self.SRPSession,
            "Email": email
        ]

        if let code = tfaCode {
            out["TwoFactorCode"] = code
        }
        return out
    }

    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return SettingsAPI.settingsPath + "/email"
    }
}

/// Response
final class UpdateLinkConfirmation: Request {
    private let status: LinkOpeningMode

    init(status: LinkOpeningMode, authCredential: AuthCredential?) {
        self.status = status
        self.auth = authCredential
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }

    var parameters: [String: Any]? {
        return ["ConfirmLink": NSNumber(value: self.status == .confirmationAlert).intValue]
    }
    var method: HTTPMethod {
        return .put
    }
    var path: String {
        return SettingsAPI.path + "/confirmlink"
    }
}

// update login password this is only in two password mode - Response
final class UpdateLoginPassword: Request {
    let clientEphemeral: String // base64_encoded_ephemeral
    let clientProof: String // base64_encoded_proof
    let SRPSession: String // hex_encoded_session_id
    let tfaCode: String?

    let modulusID: String // encrypted_id
    let salt: String // base64_encoded_salt
    let verifer: String // base64_encoded_verifier

    init(clientEphemeral: String,
         clientProof: String,
         SRPSession: String,
         modulusID: String,
         salt: String,
         verifer: String,
         tfaCode: String?,
         authCredential: AuthCredential?) {

        self.clientEphemeral = clientEphemeral
        self.clientProof = clientProof
        self.SRPSession = SRPSession
        self.tfaCode = tfaCode
        self.modulusID = modulusID
        self.salt = salt
        self.verifer = verifer

        self.auth = authCredential
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }

    var parameters: [String: Any]? {

        let auth: [String: Any] = [
            "Version": 4,
            "ModulusID": self.modulusID,
            "Salt": self.salt,
            "Verifier": self.verifer
        ]

        var out: [String: Any] = [
            "ClientEphemeral": self.clientEphemeral,
            "ClientProof": self.clientProof,
            "SRPSession": self.SRPSession,
            "Auth": auth
        ]

        if let code = tfaCode {
            out["TwoFactorCode"] = code
        }
        return out
    }
    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return SettingsAPI.settingsPath + "/password"
    }
}

final class EnableFolderColorRequest: Request {
    private let isEnable: Bool

    init(isEnable: Bool) {
        self.isEnable = isEnable
    }

    var parameters: [String: Any]? {
        let value = self.isEnable ? 1: 0
        return ["EnableFolderColor": value]
    }

    var path: String {
        return SettingsAPI.versionPrefix + SettingsAPI.settingsPath + "/enablefoldercolor"
    }

    var method: HTTPMethod {
        return .put
    }
}

final class InheritParentFolderColorRequest: Request {
    private let isEnable: Bool

    init(isEnable: Bool) {
        self.isEnable = isEnable
    }

    var parameters: [String: Any]? {
        let value = self.isEnable ? 1: 0
        return ["InheritParentFolderColor": value]
    }

    var path: String {
        return SettingsAPI.versionPrefix + SettingsAPI.settingsPath + "/inheritparentfoldercolor"
    }

    var method: HTTPMethod {
        return .put
    }
}
