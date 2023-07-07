// Copyright (c) 2022 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import ProtonCore_Crypto

struct PushNavigationResolver {
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func mapNotificationToDeepLink(_ payload: PushNotificationPayload, completion: @escaping (DeepLink?) -> Void) {
        if payload.isLocalNotification {
            handleLocalNotification(category: payload.category, uid: payload.uid, completion: completion)
        } else {
            let content = decryptContent(encryptedMessage: payload.encryptedMessage, uid: payload.uid)
            switch content?.remoteNotificationType {
            case .email:
                handleEmailRemoteNotification(payload: payload, content: content?.data, completion: completion)
            case .openUrl:
                handleOpenUrlRemoteNotification(url: content?.data.url, completion: completion)
            case .none:
                let type = content?.type ?? "nil"
                logPushNotificationError(message: "Unrecognized remote notification type.", redactedInfo: type)
                completion(nil)
            }
        }
    }
}

private extension PushNavigationResolver {

    private func decryptContent(encryptedMessage: String?, uid: String?) -> PushContent? {
        guard let message = encryptedMessage, let receiverId = uid else {
            logPushNotificationError(message: "No encrypted message or uid found.")
            return nil
        }
        guard let encryptionKit = dependencies.subscriptionsPack.encryptionKit(forUID: receiverId) else {
            logPushNotificationError(message: "No encryption kit found.", redactedInfo: "uid: \(receiverId)")
            return nil
        }
        let decryptionKey = DecryptionKey(
            privateKey: ArmoredKey(value: encryptionKit.privateKey),
            passphrase: Passphrase(value: encryptionKit.passphrase)
        )
        do {
            let plaintext: String = try Decryptor.decrypt(
                decryptionKeys: [decryptionKey],
                encrypted: ArmoredMessage(value: message)
            )
            return try PushContent(json: plaintext)
        } catch {
            logPushNotificationError(message: "Fail decrypting message.", redactedInfo: String(describing: error))
            return nil
        }
    }

    private func handleEmailRemoteNotification(
        payload: PushNotificationPayload,
        content: PushData?,
        completion: @escaping (DeepLink?) -> Void
    ) {
        guard
            let uid = payload.uid,
            let messageId = content?.messageId
        else {
            completion(nil)
            return
        }
        let link = DeepLink(MenuCoordinator.Setup.switchUserFromNotification.rawValue, sender: uid)
        link.append(.init(name: String(describing: MailboxViewController.self), value: Message.Location.inbox))
        link.append(.init(name: MailboxCoordinator.Destination.details.rawValue, value: messageId))

        completion(link)
    }

    private func handleOpenUrlRemoteNotification(url: URL?, completion: @escaping (DeepLink?) -> Void) {
        guard let url = url else {
            logPushNotificationError(message: "No url found for openUrl notification.")
            completion(nil)
            return
        }
        let link = DeepLink(.toWebBrowser, sender: url.absoluteString)
        completion(link)
    }

    private func handleLocalNotification(category: String?, uid: String?, completion: (DeepLink?) -> Void) {
        guard let category = category else { return }

        switch LocalNotificationService.Categories(rawValue: category) {
        case .sessionRevoked:
            let link = DeepLink("toAccountManager", sender: nil)
            completion(link)
        case .failedToSend:
            let link = DeepLink(MenuCoordinator.Setup.switchUserFromNotification.rawValue, sender: uid)
            link.append(.init(name: String(describing: MailboxViewController.self), value: Message.Location.draft.rawValue))
            completion(link)
        case .none:
            logPushNotificationError(message: "Unrecognized local notification")
            completion(nil)
        }
    }

    private func logPushNotificationError(message: String, redactedInfo: String? = nil) {
        SystemLogger.log(message: message, redactedInfo: redactedInfo, category: .pushNotification, isError: true)
    }
}

extension PushNavigationResolver {

    struct Dependencies {
        let subscriptionsPack: SubscriptionsPackProtocol

        init(subscriptionsPack: SubscriptionsPackProtocol) {
            self.subscriptionsPack = subscriptionsPack
        }
    }
}
