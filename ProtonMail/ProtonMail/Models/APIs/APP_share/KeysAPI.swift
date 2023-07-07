//
//  KeysAPI.swift
//  Proton Mail - Created on 11/11/16.
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
import PromiseKit
import GoLibs
import ProtonCore_Crypto
import ProtonCore_DataModel
import ProtonCore_Networking
import ProtonCore_Services

// Keys API
struct KeysAPI {
    static let path: String = "/keys"
}

/// KeysResponse
final class UserEmailPubKeys: Request {
    let email: String

    init(email: String, authCredential: AuthCredential? = nil) {
        self.email = email
        self.auth = authCredential
    }

    var parameters: [String: Any]? {
        let out: [String: Any] = ["Email": self.email]
        return out
    }

    var path: String {
        return KeysAPI.path
    }

    // custom auth credentical
    let auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }
}

extension Array where Element: UserEmailPubKeys {
    func getPromises(api: APIService) -> [Promise<KeysResponse>] {
        var out: [Promise<KeysResponse>] = [Promise<KeysResponse>]()
        for it in self {
            out.append(api.run(route: it))
        }
        return out
    }
}

final class KeyResponse {
    let flags: Key.Flags
    let publicKey: String?

    init(flags: Key.Flags, publicKey: String?) {
        self.flags = flags
        self.publicKey = publicKey
    }
}

final class KeysResponse: Response {
    enum RecipientType: Int {
        case `internal` = 1
        case external = 2
    }
    var recipientType: RecipientType = .internal
    var mimeType: String?
    var keys: [KeyResponse] = [KeyResponse]()

    override func ParseResponse(_ response: [String: Any]!) -> Bool {
        let rawRecipientType = response["RecipientType"] as? Int ?? 0
        self.recipientType = RecipientType(rawValue: rawRecipientType) ?? .external
        self.mimeType = response["MIMEType"] as? String

        if let keyRes = response["Keys"] as? [[String: Any]] {
            for keyDict in keyRes {
                let rawFlags = keyDict["Flags"] as? Int ?? 0
                let flags = Key.Flags(rawValue: rawFlags)
                let publicKey = keyDict["PublicKey"] as? String
                self.keys.append(KeyResponse(flags: flags, publicKey: publicKey))
            }
        }
        return true
    }

    var allPublicKeys: [ArmoredKey] {
        keys
            .filter { $0.flags.contains(.encryptionEnabled) }
            .compactMap { $0.publicKey }
            .map { ArmoredKey(value: $0)}
    }
}

/// message packages
final class PasswordAuth: Package {

    let AuthVersion: Int = 4
    let ModulusID: String // encrypted id
    let salt: String // base64 encoded
    let verifer: String // base64 encoded

    init(modulus_id: String, salt: String, verifer: String) {
        self.ModulusID = modulus_id
        self.salt = salt
        self.verifer = verifer
    }

    var parameters: [String: Any]? {
        let out: [String: Any] = [
            "Version": self.AuthVersion,
            "ModulusID": self.ModulusID,
            "Salt": self.salt,
            "Verifier": self.verifer
        ]
        return out
    }
}

// MARK: update user's private keys -- Response
final class UpdatePrivateKeyRequest: Request {

    let clientEphemeral: String // base64 encoded
    let clientProof: String // base64 encoded
    let SRPSession: String // hex encoded session id
    let tfaCode: String? // optional
    let keySalt: String // base64 encoded need random value
    var userLevelKeys: [Key]
    var userAddressKeys: [Key]
    let orgKey: String?
    let userKeys: [Key]?
    let auth: PasswordAuth?

    init(clientEphemeral: String,
         clientProof: String,
         SRPSession: String,
         keySalt: String,
         userlevelKeys: [Key] = [],
         addressKeys: [Key] = [],
         tfaCode: String? = nil,
         orgKey: String? = nil,
         userKeys: [Key]?,
         auth: PasswordAuth?,
         authCredential: AuthCredential?
         ) {
        self.clientEphemeral = clientEphemeral
        self.clientProof = clientProof
        self.SRPSession = SRPSession
        self.keySalt = keySalt
        self.userLevelKeys = userlevelKeys
        self.userAddressKeys = addressKeys

        self.userKeys = userKeys

        // optional values
        self.orgKey = orgKey
        self.tfaCode = tfaCode
        self.auth = auth

        self.credential = authCredential
    }

    // custom auth credentical
    let credential: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.credential
        }
    }

    var parameters: [String: Any]? {
        var keysDict: [Any] = [Any]()
        for userLevelKey in userLevelKeys where userLevelKey.isUpdated {
            keysDict.append( ["ID": userLevelKey.keyID, "PrivateKey": userLevelKey.privateKey] )
        }
        for userAddressKey in userAddressKeys where userAddressKey.isUpdated {
            keysDict.append( ["ID": userAddressKey.keyID, "PrivateKey": userAddressKey.privateKey] )
        }

        var out: [String: Any] = [
            "ClientEphemeral": self.clientEphemeral,
            "ClientProof": self.clientProof,
            "SRPSession": self.SRPSession,
            "KeySalt": self.keySalt
        ]

        if !keysDict.isEmpty {
            out["Keys"] = keysDict
        }

        if let userKeys = self.userKeys {
            var userKeysDict: [Any] = []
            for userKey in userKeys where userKey.isUpdated {
                userKeysDict.append( ["ID": userKey.keyID, "PrivateKey": userKey.privateKey] )
            }
            if !userKeysDict.isEmpty {
                out["UserKeys"] = userKeysDict
            }
        }

        if let code = tfaCode {
            out["TwoFactorCode"] = code
        }
        if let org_key = orgKey {
             out["OrganizationKey"] = org_key
        }
        if let auth_obj = self.auth {
            out["Auth"] = auth_obj.parameters
        }

        return out
    }

    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return KeysAPI.path + "/private"
    }
}

// MARK: active a key when Activation is not null --- Response
final class ActivateKey: Request {
    let addressID: String
    let privateKey: String
    let signedKeyList: [String: Any]

    init(addrID: String, privKey: String, signedKL: [String: Any]) {
        self.addressID = addrID
        self.privateKey = privKey
        self.signedKeyList = signedKL
    }

    var parameters: [String: Any]? {
        let out: [String: Any] = [
            "PrivateKey": self.privateKey,
            "SignedKeyList": self.signedKeyList
        ]
        return out
    }

    var method: HTTPMethod {
        return .put
    }

    var path: String {
        return KeysAPI.path + "/" + addressID + "/activate"
    }

    // custom auth credentical
    var auth: AuthCredential?
    var authCredential: AuthCredential? {
        get {
            return self.auth
        }
    }
}
