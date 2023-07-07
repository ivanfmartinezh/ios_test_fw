//
//  MessageDataService+MessageActions.swift
//  Proton Mail
//
//
//  Copyright (c) 2021 Proton AG
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
import CoreData

// sourcery: mock
protocol MessageDataActionProtocol {
    func mark(messageObjectIDs: [NSManagedObjectID], labelID: LabelID, unRead: Bool) -> Bool
}

extension MessageDataService: MessageDataActionProtocol {

    static func findMessagesWithSourceIds(messages: [MessageEntity], customFolderIds: [LabelID], to tLabel: LabelID) -> [(MessageEntity, LabelID)] {
        let defaultFoldersLocations: [Message.Location] = [.inbox, .archive, .spam, .trash, .sent, .draft, .scheduled]
        let defaultFoldersLabelIds = defaultFoldersLocations.map(\.labelID)
        let sourceIdCandidates = customFolderIds + defaultFoldersLabelIds

        return messages.compactMap { message -> (MessageEntity, LabelID)? in
            let labelIds: [LabelID] = message.getLabelIDs()
            let source = labelIds.first { labelId in
                sourceIdCandidates.contains(labelId)
            }

            // We didn't find original folder (should not happens)
            guard let sourceId = source else { return nil }
            // Avoid to move a message to his current location
            guard sourceId != tLabel else { return nil }
            // Avoid stupid move
            if [Message.Location.sent.labelID, Message.Location.draft.labelID].contains(sourceId) &&
                [Message.Location.spam.labelID, Message.Location.inbox.labelID].contains(tLabel) { return nil }

            return (message, sourceId)
        }
    }

    @discardableResult
    func move(messages: [MessageEntity], to tLabel: LabelID, isSwipeAction: Bool = false, queue: Bool = true) -> Bool {
        let customFolderIDs = contextProvider.read { context in
            labelDataService.getAllLabels(of: .folder, context: context).map { LabelID($0.labelID) }
        }
        let messagesWithSourceIds = MessageDataService
            .findMessagesWithSourceIds(messages: messages,
                                       customFolderIds: customFolderIDs,
                                       to: tLabel)
        messagesWithSourceIds.forEach { (msg, sourceId) in
            _ = self.cacheService.move(message: msg, from: sourceId, to: tLabel)
        }

        if queue {
            let msgIds = messagesWithSourceIds.map { $0.0.messageID }
            self.queue(.folder(nextLabelID: tLabel.rawValue, shouldFetch: true, isSwipeAction: isSwipeAction, itemIDs: msgIds.map(\.rawValue), objectIDs: []))
        }
        return true
    }

    @discardableResult
    func move(messages: [MessageEntity], from fLabels: [LabelID], to tLabel: LabelID, isSwipeAction: Bool = false, queue: Bool = true) -> Bool {
        guard !messages.isEmpty,
              messages.count == fLabels.count else {
            return false
        }

        for (index, message) in messages.enumerated() {
            if message.contains(location: .scheduled) && tLabel == LabelLocation.trash.labelID {
                // Trash schedule message, should move to draft
                let target = LabelLocation.draft.labelID
                let scheduled = LabelLocation.scheduled.labelID
                let sent = LabelLocation.sent.labelID
                _ = self.cacheService.move(message: message, from: fLabels[index], to: target)
                _ = self.cacheService.move(message: message, from: scheduled, to: target)
                _ = self.cacheService.move(message: message, from: sent, to: target)
            } else {
                _ = self.cacheService.move(message: message, from: fLabels[index], to: tLabel)
            }
        }

        if queue {
            let ids = messages.map{ $0.messageID.rawValue }
            self.queue(.folder(nextLabelID: tLabel.rawValue, shouldFetch: true, isSwipeAction: isSwipeAction, itemIDs: ids, objectIDs: []))
        }
        return true
    }

    @discardableResult

    func delete(messages: [MessageEntity], label: LabelID) -> Bool {
        guard !messages.isEmpty else { return false }
        for message in messages {
            _ = self.cacheService.delete(message: message, label: label)
        }

        // If the messageID is UUID, that means the message hasn't gotten response from BE
        let messagesIds = messages
            .map(\.messageID.rawValue)
            .filter { UUID(uuidString: $0) == nil }
        self.queue(.delete(currentLabelID: nil, itemIDs: messagesIds))
        return true
    }

    /// mark message to unread
    ///
    /// - Parameter message: message
    /// - Returns: true if change to unread and push to the queue
    @discardableResult
    func mark(messageObjectIDs: [NSManagedObjectID], labelID: LabelID, unRead: Bool) -> Bool {
        mark(messageObjectIDs: messageObjectIDs, labelID: labelID, unRead: unRead, context: nil)
    }

    @discardableResult
    func mark(messageObjectIDs: [NSManagedObjectID], labelID: LabelID, unRead: Bool, context: NSManagedObjectContext?) -> Bool {
        guard !messageObjectIDs.isEmpty else {
            return false
        }
        let ids = messageObjectIDs.map { $0.uriRepresentation().absoluteString }
        self.queue(unRead ? .unread(currentLabelID: labelID.rawValue, itemIDs: [], objectIDs: ids) : .read(itemIDs: [], objectIDs: ids))
        for messageObjectID in messageObjectIDs {
            if let context = context {
                _ = self.cacheService.mark(messageObjectID: messageObjectID, labelID: labelID, unRead: unRead, context: context)
            } else {
                _ = self.cacheService.mark(messageObjectID: messageObjectID, labelID: labelID, unRead: unRead)
            }
        }
        return true
    }

    @discardableResult
    func label(messages: [MessageEntity], label: LabelID, apply: Bool, isSwipeAction: Bool = false, shouldFetchEvent: Bool = true) -> Bool {
        guard !messages.isEmpty else {
            return false
        }

        _ = self.cacheService.label(messages: messages, label: label, apply: apply)

        let messagesIds = messages.map(\.messageID.rawValue)
        self.queue(apply ? .label(currentLabelID: label.rawValue,
                                  shouldFetch: shouldFetchEvent,
                                  isSwipeAction: false,
                                  itemIDs: messagesIds, objectIDs: []) :
                        .unlabel(currentLabelID: label.rawValue,
                                 shouldFetch: shouldFetchEvent,
                                 isSwipeAction: isSwipeAction,
                                 itemIDs: messagesIds,
                                 objectIDs: []))
        return true
    }

    func deleteExpiredMessage(completion: (() -> Void)?) {
        self.cacheService.deleteExpiredMessage(completion: completion)
    }

    /// fetch messages with set of message id
    ///
    /// - Parameter selected: MessageIDs
    /// - Returns: fetched message obj
    func fetchMessages(withIDs selected: NSMutableSet, in context: NSManagedObjectContext) -> [Message] {
        let fetchRequest = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K in %@", Message.Attributes.messageID, selected)
        do {
            return try context.fetch(fetchRequest)
        } catch {
        }
        return [Message]()
    }

    func isMessageBeingSent(id messageID: MessageID) -> Bool {
        isMessageBeingSent(id: messageID.rawValue)
    }

    func isMessageBeingSent(id messageID: String) -> Bool {
        idsOfMessagesBeingSent().contains(messageID)
    }

    func idsOfMessagesBeingSent() -> [String] {
        guard let queueManager = queueManager else {
            fatalError("queueManager is not supposed to be deallocated")
        }

        return queueManager.messageIDsOfTasks { action in
            switch action {
            case .send:
                return true
            default:
                return false
            }
        }
    }
}
