//
//  CacheService.swift
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
import GoLibs
import CoreData
import Groot
import ProtonCore_DataModel

// sourcery: mock
protocol CacheServiceProtocol: Service {
    func addNewLabel(serverResponse: [String: Any], objectID: String?, completion: (() -> Void)?)
    func updateLabel(serverReponse: [String: Any], completion: (() -> Void)?)
    func deleteLabels(objectIDs: [NSManagedObjectID], completion: (() -> Void)?)
    func updateContactDetail(serverResponse: [String: Any], completion: ((Contact?, NSError?) -> Void)?)
    func parseMessagesResponse(
        labelID: LabelID,
        isUnread: Bool,
        response: [String: Any],
        idsOfMessagesBeingSent: [String]
    ) throws
    func updateCounterSync(markUnRead: Bool, on labelIDs: [LabelID])
    func updateExpirationOffset(of messageObjectID: NSManagedObjectID,
                                expirationTime: TimeInterval,
                                pwd: String,
                                pwdHint: String,
                                completion: (() -> Void)?)
}

class CacheService: CacheServiceProtocol {
    let userID: UserID
    let lastUpdatedStore: LastUpdatedStoreProtocol
    let coreDataService: CoreDataContextProviderProtocol

    init(userID: UserID, dependencies: Dependencies = Dependencies()) {
        self.userID = userID
        self.lastUpdatedStore = dependencies.lastUpdatedStore
        self.coreDataService = dependencies.coreDataService
    }

    // MARK: - Generic functions

    func selectByIds<T: CoreDataIdentifiable>(
        context: NSManagedObjectContext,
        ids: [String],
        sortByAttr: String? = nil,
        sortAsc: Bool = false
    ) -> [T] {
        let request = NSFetchRequest<T>(entityName: T.entityName)
        let predicate = NSPredicate(format: "%K in %@", T.attributeIdName, ids)
        request.predicate = predicate
        if let sortAttribute = sortByAttr {
            request.sortDescriptors = [NSSortDescriptor(key: sortAttribute, ascending: sortAsc)]
        }
        var results = [T]()
        context.performAndWait {
            results = (try? context.fetch(request)) ?? []
        }
        return results
    }

    // MARK: - Message related functions
    func move(message: MessageEntity, from fLabel: LabelID, to tLabel: LabelID) -> Bool {
        var hasError = false
        coreDataService.performAndWaitOnRootSavingContext { context in
            guard let msgToUpdate = try? context.existingObject(with: message.objectID.rawValue) as? Message else {
                hasError = true
                return
            }

            if let lid = msgToUpdate.remove(labelID: fLabel.rawValue), msgToUpdate.unRead {
                self.updateCounterInsideContext(plus: false, with: LabelID(lid))
                if let id = msgToUpdate.selfSent(labelID: lid) {
                    self.updateCounterInsideContext(plus: false, with: LabelID(id))
                }
            }
            if let lid = msgToUpdate.add(labelID: tLabel.rawValue) {
                // if move to trash. clean labels.
                var labelsFound = msgToUpdate.getNormalLabelIDs()
                labelsFound.append(Message.Location.starred.rawValue)
                // prevent the unread being substracted once more
                if fLabel != Message.Location.allmail.labelID {
                    labelsFound.append(Message.Location.allmail.rawValue)
                }
                if lid == Message.Location.trash.rawValue {
                    self.removeLabel(on: msgToUpdate, labels: labelsFound, cleanUnread: true)
                    msgToUpdate.unRead = false
                    PushUpdater().remove(notificationIdentifiers: [msgToUpdate.notificationId])
                }
                if lid == Message.Location.spam.rawValue {
                    self.removeLabel(on: msgToUpdate, labels: labelsFound, cleanUnread: false)
                }

                if msgToUpdate.unRead {
                    self.updateCounterInsideContext(plus: true, with: LabelID(lid))
                    if let id = msgToUpdate.selfSent(labelID: lid) {
                        self.updateCounterInsideContext(plus: true, with: LabelID(id))
                    }
                }
            }

            let error = context.saveUpstreamIfNeeded()
            if error != nil {
                hasError = true
            }
        }
        return !hasError
    }

    func delete(message: MessageEntity, label: LabelID) -> Bool {
        var hasError = false
        coreDataService.performAndWaitOnRootSavingContext { contextToUse in
            guard let msgToUpdate = try? contextToUse.existingObject(with: message.objectID.rawValue) as? Message else {
                hasError = true
                return
            }

            if let lid = msgToUpdate.remove(labelID: label.rawValue), msgToUpdate.unRead {
                self.updateCounterSync(plus: false, with: LabelID(lid))
                if let id = msgToUpdate.selfSent(labelID: lid) {
                    self.updateCounterSync(plus: false, with: LabelID(id))
                }
            }
            var labelsFound = msgToUpdate.getNormalLabelIDs()
            labelsFound.append(Message.Location.starred.rawValue)
            labelsFound.append(Message.Location.allmail.rawValue)
            self.removeLabel(on: msgToUpdate, labels: labelsFound, cleanUnread: true)
            let labelObjs = msgToUpdate.mutableSetValue(forKey: "labels")
            labelObjs.removeAllObjects()
            msgToUpdate.setValue(labelObjs, forKey: "labels")
            contextToUse.delete(msgToUpdate)

            let error = contextToUse.saveUpstreamIfNeeded()
            if error != nil {
                hasError = true
            }
        }

        if hasError {
            return false
        }

        return true
    }

    func mark(messageObjectID: NSManagedObjectID, labelID: LabelID, unRead: Bool) -> Bool {
        var isSuccess: Bool!

        coreDataService.performAndWaitOnRootSavingContext { context in
            isSuccess = self.mark(messageObjectID: messageObjectID, labelID: labelID, unRead: unRead, context: context)
        }

        return isSuccess
    }

    func mark(messageObjectID: NSManagedObjectID, labelID: LabelID, unRead: Bool, context: NSManagedObjectContext) -> Bool {
            guard let msgToUpdate = try? context.existingObject(with: messageObjectID) as? Message else {
                return false
            }

            guard msgToUpdate.unRead != unRead else {
                return true
            }

            msgToUpdate.unRead = unRead

            if unRead == false {
                PushUpdater().remove(notificationIdentifiers: [msgToUpdate.notificationId])
            }
            if let conversation = Conversation.conversationForConversationID(msgToUpdate.conversationID, inManagedObjectContext: context) {
                conversation.applySingleMarkAsChanges(unRead: unRead, labelID: labelID.rawValue)
            }
            self.updateCounterSync(markUnRead: unRead, on: msgToUpdate.getLabelIDs().map { LabelID($0) })

        if let error = context.saveUpstreamIfNeeded(){
            assertionFailure("\(error)")
            return false
        } else {
            return true
        }
    }

    func label(messages: [MessageEntity], label: LabelID, apply: Bool) -> Bool {
        var result = false
        var hasError = false
        coreDataService.performAndWaitOnRootSavingContext { context in
            for message in messages {
                guard let msgToUpdate = try? context.existingObject(with: message.objectID.rawValue) as? Message else {
                    hasError = true
                    continue
                }

                if apply {
                    if msgToUpdate.add(labelID: label.rawValue) != nil && msgToUpdate.unRead {
                        self.updateCounterSync(plus: true, with: label)
                    }
                } else {
                    if msgToUpdate.remove(labelID: label.rawValue) != nil && msgToUpdate.unRead {
                        self.updateCounterSync(plus: false, with: label)
                    }
                }

                if let conversation = Conversation.conversationForConversationID(msgToUpdate.conversationID, inManagedObjectContext: context) {
                    conversation.applyLabelChangesOnOneMessage(labelID: label.rawValue, apply: apply)
                }
            }

            let error = context.saveUpstreamIfNeeded()
            if error != nil {
                hasError = true
            }
        }

        if hasError {
            result = false
        }
        result = true
        return result
    }

    func removeLabel(on message: Message, labels: [String], cleanUnread: Bool) {
        let unread = cleanUnread ? message.unRead : cleanUnread
        for label in labels {
            if let labelId = message.remove(labelID: label), unread {
                self.updateCounterInsideContext(plus: false, with: LabelID(labelId))
                if let id = message.selfSent(labelID: labelId) {
                    self.updateCounterInsideContext(plus: false, with: LabelID(id))
                }
            }
        }
    }

    func markMessageAndConversationDeleted(labelID: LabelID) {
        let messageFetch = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        messageFetch.predicate = NSPredicate(format: "(ANY labels.labelID = %@) AND (%K == %@)", "\(labelID)", Message.Attributes.userID, self.userID.rawValue)

        let contextLabelFetch = NSFetchRequest<ContextLabel>(entityName: ContextLabel.Attributes.entityName)
        contextLabelFetch.predicate = NSPredicate(
            format: "(%K == %@) AND (%K == %@)",
            ContextLabel.Attributes.labelID,
            labelID.rawValue,
            Conversation.Attributes.userID.rawValue,
            self.userID.rawValue
        )

        coreDataService.performAndWaitOnRootSavingContext { context in
            if let messages = try? context.fetch(messageFetch) {
                messages.forEach { $0.isSoftDeleted = true }
            }
            if let contextLabels = try? context.fetch(contextLabelFetch) {
                contextLabels.forEach { label in
                    if let conversation = label.conversation {
                        conversation.isSoftDeleted = true
                        let num = max(0, conversation.numMessages.intValue - label.messageCount.intValue)
                        conversation.numMessages = NSNumber(value: num)
                    }
                    label.isSoftDeleted = true
                }
            }
            _ = context.saveUpstreamIfNeeded()
        }
    }

    func cleanSoftDeletedMessagesAndConversation() {
        let messageFetch = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        messageFetch.predicate = NSPredicate(format: "%K = %@", Message.Attributes.isSoftDeleted, NSNumber(true))

        let contextLabelFetch = NSFetchRequest<ContextLabel>(entityName: ContextLabel.Attributes.entityName)
        contextLabelFetch.predicate = NSPredicate(
            format: "%K = %@",
            "conversation.\(Conversation.Attributes.isSoftDeleted)",
            NSNumber(true)
        )

        coreDataService.performAndWaitOnRootSavingContext { context in
            if let messages = try? context.fetch(messageFetch) {
                messages.forEach(context.delete)
            }
            if let contextLabels = try? context.fetch(contextLabelFetch) {
                contextLabels.forEach { label in
                    if let conversation = label.conversation {
                        context.delete(conversation)
                    }
                    context.delete(label)
                }
            }
            _ = context.saveUpstreamIfNeeded()
        }
    }

    func cleanReviewItems(completion: (() -> Void)? = nil) {
        coreDataService.performOnRootSavingContext { context in
            let fetchRequest = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
            fetchRequest.predicate = NSPredicate(format: "(%K == 1) AND (%K == %@)", Message.Attributes.messageType, Message.Attributes.userID, self.userID.rawValue)
            do {
                let messages = try context.fetch(fetchRequest)
                for msg in messages {
                    context.delete(msg)
                }
                _ = context.saveUpstreamIfNeeded()
            } catch {
            }
            completion?()
        }
    }

    func updateExpirationOffset(of messageObjectID: NSManagedObjectID,
                                expirationTime: TimeInterval,
                                pwd: String,
                                pwdHint: String,
                                completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { contextToUse in
            if let msg = try? contextToUse.existingObject(with: messageObjectID) as? Message {
                msg.time = Date()
                msg.password = pwd
                msg.passwordHint = pwdHint
                msg.expirationOffset = Int32(expirationTime)
                _ = contextToUse.saveUpstreamIfNeeded()
            }
            completion?()
        }
    }

    func deleteExpiredMessage(completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            #if !APP_EXTENSION
            let processInfo = userCachedStatus
            #else
            let processInfo = userCachedStatus as? SystemUpTimeProtocol
            #endif
            let date = Date.getReferenceDate(processInfo: processInfo)
            let fetch = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
            fetch.predicate = NSPredicate(format: "%K != NULL AND %K < %@",
                                          Message.Attributes.expirationTime,
                                          Message.Attributes.expirationTime,
                                          date as CVarArg)

            if let messages = try? context.fetch(fetch) {
                messages.forEach { (msg) in
                    if msg.unRead {
                        let labels = msg.getLabelIDs().map{ LabelID($0) }
                        labels.forEach { label in
                            self.updateCounterSync(plus: false, with: label)
                        }
                    }
                    self.updateConversation(by: msg, in: context)
                    context.delete(msg)
                }
                _ = context.saveUpstreamIfNeeded()
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    private func updateConversation(by expiredMessage: Message, in context: NSManagedObjectContext) {
        let conversationID = expiredMessage.conversationID
        guard !conversationID.isEmpty,
              let conversation = Conversation.conversationForConversationID(conversationID, inManagedObjectContext: context) else {
            return
        }
        let fetch = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        fetch.predicate = NSPredicate(
            format: "%K == %@ AND %K.length != 0",
            Message.Attributes.conversationID,
            conversation.conversationID,
            Message.Attributes.messageID
        )
        guard let messages = try? context.fetch(fetch) else {
            conversation.expirationTime = nil
            return
        }
        #if !APP_EXTENSION
        let processInfo = userCachedStatus
        #else
        let processInfo = userCachedStatus as? SystemUpTimeProtocol
        #endif
        let sorted = messages
            .filter({ $0 != expiredMessage && ($0.expirationTime ?? .distantPast) > Date.getReferenceDate(processInfo: processInfo) })
            .sorted(by: { ($0.expirationTime ?? .distantPast) > ($1.expirationTime ?? .distantPast) })
        conversation.expirationTime = sorted.first?.expirationTime
        let numMessages = max(0, conversation.numMessages.intValue - 1)
        conversation.numMessages = NSNumber(value: numMessages)
    }
}

// MARK: - Attachment related functions
extension CacheService {
    func delete(attachment: AttachmentEntity, completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            if let att = try? context.existingObject(with: attachment.objectID.rawValue) as? Attachment {
                att.isSoftDeleted = true
                _ = context.saveUpstreamIfNeeded()
            }
            completion?()
        }
    }

    func cleanOldAttachment() {
        coreDataService.performOnRootSavingContext { context in
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Attachment.Attributes.entityName)
            fetchRequest.predicate = NSPredicate(format: "(%K == 1) AND %K == NULL", Attachment.Attributes.isSoftDelete, Attachment.Attributes.message)
            let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            do {
                try context.executeAndMergeChanges(using: request)
            } catch {
                assertionFailure("Old attachment deletion failed: \(error.localizedDescription)")
            }
        }
    }
}

extension CacheService {
    func parseMessagesResponse(
        labelID: LabelID,
        isUnread: Bool,
        response: [String: Any],
        idsOfMessagesBeingSent: [String]) throws {
        guard var messagesArray = response["Messages"] as? [[String: Any]] else {
            throw NSError.unableToParseResponse(response)
        }

        for (index, _) in messagesArray.enumerated() {
            messagesArray[index]["UserID"] = self.userID.rawValue
        }
        let messagesCount = response["Total"] as? Int ?? 0

        if labelID == Message.Location.draft.labelID {
            //Prevent drafts from being overriden while sending
            messagesArray.removeAll { messageDict in
                guard let msgID = messageDict["ID"] as? String else {
                    return true
                }

                return idsOfMessagesBeingSent.contains(msgID)
            }
        }

        var result: Result<(Date, Date)?, Error>!

        coreDataService.performAndWaitOnRootSavingContext { context in
            do {
                if let messages = try GRTJSONSerialization.objects(withEntityName: Message.Attributes.entityName, fromJSONArray: messagesArray, in: context) as? [Message] {
                    for msg in messages {
                        // mark the status of metadata being set
                        msg.messageStatus = 1
                    }
                    _ = context.saveUpstreamIfNeeded()

                    if let lastMsg = messages.last, let firstMsg = messages.first {
                        result = .success((firstMsg.time ?? Date(), lastMsg.time ?? Date()))
                    } else {
                        result = .success(nil)
                    }
                } else {
                    result = .success(nil)
                }
            } catch {
                result = .failure(error)
            }
        }

            switch result {
            case let .success(.some((startTime, endTime))):
                self.lastUpdatedStore.updateLastUpdatedTime(
                    labelID: labelID,
                    isUnread: isUnread,
                    startTime: startTime,
                    endTime: endTime,
                    msgCount: messagesCount,
                    userID: self.userID,
                    type: .singleMessage
                )
            case .success(.none):
                break
            case .failure(let error):
                throw error
            case .none:
                fatalError("result should have been set by now!")
            }
    }
}

// MARK: - Counter related functions
extension CacheService {
    func updateCounterSync(markUnRead: Bool, on message: Message) {
        self.updateCounterSync(markUnRead: markUnRead,
                               on: message.getLabelIDs().map(LabelID.init(rawValue:)))
    }

    func updateCounterSync(markUnRead: Bool, on labelIDs: [LabelID]) {
        let offset = markUnRead ? 1 : -1
        for lID in labelIDs {
            let unreadCount: Int = lastUpdatedStore.unreadCount(by: lID, userID: self.userID, type: .singleMessage)
            var count = unreadCount + offset
            if count < 0 {
                count = 0
            }
            lastUpdatedStore.updateUnreadCount(by: lID, userID: self.userID, unread: count, total: nil, type: .singleMessage, shouldSave: false)

            // Conversation Count
            let conversationUnreadCount: Int = lastUpdatedStore.unreadCount(by: lID, userID: self.userID, type: .conversation)
            var conversationCount = conversationUnreadCount + offset
            if conversationCount < 0 {
                conversationCount = 0
            }
            lastUpdatedStore.updateUnreadCount(by: lID, userID: self.userID, unread: conversationCount, total: nil, type: .conversation, shouldSave: false)
        }
    }

    func updateCounterSync(plus: Bool, with labelID: LabelID) {
        let offset = plus ? 1 : -1
        // Message Count
        let unreadCount: Int = lastUpdatedStore.unreadCount(by: labelID, userID: self.userID, type: .singleMessage)
        var count = unreadCount + offset
        if count < 0 {
            count = 0
        }
        lastUpdatedStore.updateUnreadCount(by: labelID, userID: self.userID, unread: count, total: nil, type: .singleMessage, shouldSave: true)

        // Conversation Count
        let conversationUnreadCount: Int = lastUpdatedStore.unreadCount(by: labelID, userID: self.userID, type: .conversation)
        var conversationCount = conversationUnreadCount + offset
        if conversationCount < 0 {
            conversationCount = 0
        }
        lastUpdatedStore.updateUnreadCount(by: labelID, userID: self.userID, unread: conversationCount, total: nil, type: .conversation, shouldSave: true)
    }

    private func updateCounterInsideContext(plus: Bool, with labelID: LabelID) {
        let offset = plus ? 1 : -1
        // Message Count
        let labelCount = lastUpdatedStore.lastUpdate(by: labelID, userID: userID, type: .singleMessage)
        let unreadCount = Int(labelCount?.unread ?? 0)
        var count = unreadCount + offset
        if count < 0 {
            count = 0
        }
        lastUpdatedStore.updateUnreadCount(
            by: labelID,
            userID: userID,
            unread: count,
            total: labelCount?.total,
            type: .singleMessage,
            shouldSave: true
        )

        // Conversation Count
        let contextLabelCount = lastUpdatedStore.lastUpdate(by: labelID, userID: userID, type: .conversation)
        let conversationUnreadCount = Int(contextLabelCount?.unread ?? 0)
        var conversationCount = conversationUnreadCount + offset
        if conversationCount < 0 {
            conversationCount = 0
        }
        lastUpdatedStore.updateUnreadCount(
            by: labelID,
            userID: userID,
            unread: conversationCount,
            total: contextLabelCount?.total,
            type: .conversation,
            shouldSave: true
        )
    }
}

// MARK: - label related functions
extension CacheService {
    func addNewLabel(serverResponse: [String: Any], objectID: String? = nil, completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { [weak self] context in
            do {
                guard let self = self else { return }
                if let objectID = objectID,
                    let id = self.coreDataService.managedObjectIDForURIRepresentation(objectID),
                    let managedObject = try? context.existingObject(with: id),
                    let label = managedObject as? Label,
                    let labelID = serverResponse["ID"] as? String {
                    label.labelID = labelID
                }
                var response = serverResponse
                response["UserID"] = self.userID.rawValue
                try GRTJSONSerialization.object(withEntityName: Label.Attributes.entityName, fromJSONDictionary: response, in: context)
                _ = context.saveUpstreamIfNeeded()
            } catch {
            }
            completion?()
        }
    }

    func updateLabel(serverReponse: [String: Any], completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            do {
                var response = serverReponse
                response["UserID"] = self.userID.rawValue
                if response["ParentID"] == nil {
                    response["ParentID"] = ""
                }
                try GRTJSONSerialization.object(withEntityName: Label.Attributes.entityName, fromJSONDictionary: response, in: context)
                _ = context.saveUpstreamIfNeeded()
            } catch {
            }
            DispatchQueue.main.async {
                self.coreDataService.mainContext.refreshAllObjects()
                completion?()
            }
        }
    }

    func deleteLabels(objectIDs: [NSManagedObjectID], completion: (() -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            for id in objectIDs {
                guard let label = try? context.existingObject(with: id) else {
                    continue
                }
                context.delete(label)
            }
            _ = context.saveUpstreamIfNeeded()
        }
        DispatchQueue.main.async {
            completion?()
        }
    }
}

// MARK: - contact related functions
extension CacheService {
    func addNewContact(
        serverResponse: [[String: Any]],
        shouldFixName: Bool = false,
        localContactObjectID: String? = nil,
        completion: @escaping (Error?) -> Void
    ) {
        coreDataService.performAndWaitOnRootSavingContext { [weak self]  context in
            guard let self = self else { return }
            do {
                // Delete the temporary contact that is created locally.
                if let id = localContactObjectID,
                   let objectID = self.coreDataService.managedObjectIDForURIRepresentation(id),
                   let managedObject = try? context.existingObject(with: objectID) {
                    context.delete(managedObject)
                }

                let contacts = try GRTJSONSerialization.objects(
                    withEntityName: Contact.Attributes.entityName,
                    fromJSONArray: serverResponse,
                    in: context
                ) as? [Contact]

                contacts?.forEach { contact in
                    contact.userID = self.userID.rawValue
                    if shouldFixName {
                        _ = contact.fixName(force: true)
                    }
                    if let emails = contact.emails.allObjects as? [Email] {
                        emails.forEach { e in
                            e.userID = self.userID.rawValue
                        }
                    }
                }

                _ = context.saveUpstreamIfNeeded()
                completion(nil)
            } catch {
                completion(error)
            }
        }
    }

    func updateContact(contactID: ContactID, cardsJson: [String: Any], completion: @escaping (NSError?) -> Void) {
        coreDataService.performOnRootSavingContext { context in
            do {
                // remove all emailID associated with the current contact in the core data
                // since the new data will be added to the core data (parse from response)
                if let originalContact = Contact.contactForContactID(contactID.rawValue, inManagedObjectContext: context) {
                    if let emailObjects = originalContact.emails.allObjects as? [Email] {
                        for emailObject in emailObjects {
                            context.delete(emailObject)
                        }
                    }
                }

                if let newContact = try GRTJSONSerialization.object(withEntityName: Contact.Attributes.entityName, fromJSONDictionary: cardsJson, in: context) as? Contact {
                    newContact.needsRebuild = true
                    let savingError = context.saveUpstreamIfNeeded()
                    completion(savingError)
                } else {
                    assertionFailure("Groot should output a Contact")
                    completion(nil)
                }
            } catch {
                completion(error as NSError)
            }
        }
    }

    func deleteContact(by contactID: ContactID, completion: ((NSError?) -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            var err: NSError?
            if let contact = Contact.contactForContactID(contactID.rawValue, inManagedObjectContext: context) {
                context.delete(contact)
            }
            if let error = context.saveUpstreamIfNeeded() {
                err = error
            }
            completion?(err)
        }
    }

    func updateContactDetail(serverResponse: [String: Any], completion: ((Contact?, NSError?) -> Void)?) {
        coreDataService.performOnRootSavingContext { context in
            do {
                if let contact = try GRTJSONSerialization.object(withEntityName: Contact.Attributes.entityName, fromJSONDictionary: serverResponse, in: context) as? Contact {
                    contact.isDownloaded = true
                    _ = contact.fixName(force: true)
                    if let error = context.saveUpstreamIfNeeded() {
                        completion?(nil, error)
                    } else {
                        completion?(contact, nil)
                    }
                } else {
                    completion?(nil, NSError.unableToParseResponse(serverResponse))
                }
            } catch {
                completion?(nil, error as NSError)
            }
        }
    }
}

extension CacheService {
    struct Dependencies {
        let coreDataService: CoreDataContextProviderProtocol
        let lastUpdatedStore: LastUpdatedStoreProtocol

        init(
            coreDataService: CoreDataContextProviderProtocol = sharedServices.get(by: CoreDataService.self),
            lastUpdatedStore: LastUpdatedStoreProtocol = sharedServices.get(by: LastUpdatedStore.self)
        ) {
            self.coreDataService = coreDataService
            self.lastUpdatedStore = lastUpdatedStore
        }
    }
}
