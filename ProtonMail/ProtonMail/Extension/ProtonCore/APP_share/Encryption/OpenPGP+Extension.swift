//
//  OpenPGPExtension.swift
//  Proton Mail
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
import GoLibs
import OpenPGP
import ProtonCore_Crypto
import ProtonCore_DataModel

extension Crypto {

    static func updateKeysPassword(_ old_keys: [Key], old_pass: Passphrase, new_pass: Passphrase) throws -> [Key] {
        var outKeys: [Key] = [Key]()
        for okey in old_keys {
            do {
                let new_private_key = try self.updatePassphrase(
                    privateKey: ArmoredKey(value: okey.privateKey),
                    oldPassphrase: old_pass,
                    newPassphrase: new_pass
                )
                let newK = Key(keyID: okey.keyID, privateKey: new_private_key.value, isUpdated: true)
                outKeys.append(newK)
            } catch {
                let newK = Key(keyID: okey.keyID, privateKey: okey.privateKey)
                outKeys.append(newK)
            }
        }

        guard outKeys.count == old_keys.count else {
            throw UpdatePasswordError.keyUpdateFailed.error
        }

        guard outKeys.count > 0 && outKeys[0].isUpdated == true else {
            throw UpdatePasswordError.keyUpdateFailed.error
        }

        for u_k in outKeys {
            if u_k.isUpdated == false {
                continue
            }
            let result = u_k.privateKey.check(passphrase: new_pass)
            guard result == true else {
                throw UpdatePasswordError.keyUpdateFailed.error
            }
        }
        return outKeys
    }

    static func updateAddrKeysPassword(_ old_addresses: [Address], old_pass: Passphrase, new_pass: Passphrase) throws -> [Address] {
        var out_addresses = [Address]()
        for addr in old_addresses {
            var outKeys = [Key]()
            for okey in addr.keys {
                do {
                    let new_private_key = try Crypto.updatePassphrase(privateKey: ArmoredKey(value: okey.privateKey),
                                                                      oldPassphrase: old_pass,
                                                                      newPassphrase: new_pass)
                    let newK = Key(keyID: okey.keyID,
                                   privateKey: new_private_key.value,
                                   keyFlags: okey.keyFlags,
                                   token: nil,
                                   signature: nil,
                                   activation: nil,
                                   active: okey.active,
                                   version: okey.version,
                                   primary: okey.primary,
                                   isUpdated: true)
                    outKeys.append(newK)
                } catch {
                    let newK = Key(keyID: okey.keyID,
                                   privateKey: okey.privateKey,
                                   keyFlags: okey.keyFlags,
                                   token: nil,
                                   signature: nil,
                                   activation: nil,
                                   active: okey.active,
                                   version: okey.version,
                                   primary: okey.primary,
                                   isUpdated: false)
                    outKeys.append(newK)
                }
            }

            guard outKeys.count == addr.keys.count else {
                throw UpdatePasswordError.keyUpdateFailed.error
            }

            guard outKeys.count > 0 && outKeys[0].isUpdated == true else {
                throw UpdatePasswordError.keyUpdateFailed.error
            }

            for u_k in outKeys {
                if u_k.isUpdated == false {
                    continue
                }
                let result = u_k.privateKey.check(passphrase: new_pass)
                guard result == true else {
                    throw UpdatePasswordError.keyUpdateFailed.error
                }
            }
            let new_addr = Address(addressID: addr.addressID,
                                   domainID: addr.domainID,
                                   email: addr.email,
                                   send: addr.send,
                                   receive: addr.receive,
                                   status: addr.status,
                                   type: addr.type,
                                   order: addr.order,
                                   displayName: addr.displayName,
                                   signature: addr.signature,
                                   hasKeys: outKeys.isEmpty ? 0 : 1,
                                   keys: outKeys)
            out_addresses.append(new_addr)
        }

        guard out_addresses.count == old_addresses.count else {
            throw UpdatePasswordError.keyUpdateFailed.error
        }

        return out_addresses
    }

}

protocol AttachmentDecryptor {
    func decryptAttachmentNonOptional(keyPacket: Data,
                                      dataPacket: Data,
                                      privateKey: String,
                                      passphrase: String) throws -> Data
}

extension Crypto: AttachmentDecryptor {}

extension Data {
    func decryptAttachment(keyPackage: Data,
                           userKeys: [ArmoredKey],
                           passphrase: Passphrase,
                           keys: [Key],
                           attachmentDecryptor: AttachmentDecryptor = Crypto()) throws -> Data? {
        var firstError: Error?
        for key in keys {
            do {
                let addressKeyPassphrase = try key.passphrase(userPrivateKeys: userKeys, mailboxPassphrase: passphrase)
                let decryptedAttachment = try attachmentDecryptor.decryptAttachmentNonOptional(
                    keyPacket: keyPackage,
                    dataPacket: self,
                    privateKey: key.privateKey,
                    passphrase: addressKeyPassphrase.value
                )
                return decryptedAttachment
            } catch let error {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let error = firstError {
            throw error
        }
        return nil
    }

    // key packet part
    func getSessionFromPubKeyPackage(userKeys: [ArmoredKey], passphrase: Passphrase, keys: [Key]) throws -> SessionKey? {
        var firstError: Error?
        for key in keys {
            do {
                let addressKeyPassphrase = try key.passphrase(userPrivateKeys: userKeys, mailboxPassphrase: passphrase)
                let decryptionKey = DecryptionKey(
                    privateKey: ArmoredKey(value: key.privateKey),
                    passphrase: addressKeyPassphrase
                )
                let sessionKey = try Decryptor.decryptSessionKey(decryptionKeys: [decryptionKey], keyPacket: self)
                return sessionKey
            } catch let error {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let error = firstError {
            throw error
        }
        return nil
    }
}
