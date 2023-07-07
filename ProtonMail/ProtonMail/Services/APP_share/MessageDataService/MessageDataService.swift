//
//  MessageDataService.swift
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

import CoreData
import Foundation
import Groot
import PromiseKit
import ProtonCore_Crypto
import ProtonCore_DataModel
import ProtonCore_Networking
import ProtonCore_Services
import ProtonMailAnalytics

protocol MessageDataServiceProtocol: Service {
    var pushNotificationMessageID: String? { get set }
    var messageDecrypter: MessageDecrypterProtocol { get }

    /// Request to get the messages for a user
    /// - Parameters:
    ///   - labelID: identifier for labels, folders and locations.
    ///   - endTime: timestamp to get messages earlier than this value.
    ///   - fetchUnread: whether we want only unread messages or not.
    func fetchMessages(labelID: LabelID, endTime: Int, fetchUnread: Bool, completion: @escaping (_ task: URLSessionDataTask?, _ result: Swift.Result<JSONDictionary, ResponseError>) -> Void)

    /// Requests the total number of messages
    func fetchMessagesCount(completion: @escaping (MessageCountResponse) -> Void)

    func fetchMessageMetaData(messageIDs: [MessageID], completion: @escaping (FetchMessagesByIDResponse) -> Void)

    func isEventIDValid() -> Bool
    func idsOfMessagesBeingSent() -> [String]

    func getMessageSendingData(for uri: String) -> MessageSendingData?

    func updateMessageAfterSend(
        message: MessageEntity,
        sendResponse: JSONDictionary,
        completionQueue: DispatchQueue,
        completion: @escaping () -> Void
    )
    func messageWithLocation(recipientList: String,
                             bccList: String,
                             ccList: String,
                             title: String,
                             encryptionPassword: String,
                             passwordHint: String,
                             expirationTimeInterval: TimeInterval,
                             body: String,
                             attachments: [Any]?,
                             mailbox_pwd: Passphrase,
                             sendAddress: Address,
                             inManagedObjectContext context: NSManagedObjectContext) -> Message
    func saveDraft(_ message: Message?)
    func updateMessage(_ message: Message,
                       expirationTimeInterval: TimeInterval,
                       body: String,
                       mailbox_pwd: Passphrase)
    func mark(messageObjectIDs: [NSManagedObjectID], labelID: LabelID, unRead: Bool) -> Bool
    func updateAttKeyPacket(message: MessageEntity, addressID: String)
    func delete(att: AttachmentEntity, messageID: MessageID) -> Promise<Void>
    func upload(att: Attachment)
}

protocol LocalMessageDataServiceProtocol: Service {
    func cleanMessage(removeAllDraft: Bool, cleanBadgeAndNotifications: Bool) -> Promise<Void>
}

/// Message data service
class MessageDataService: MessageDataServiceProtocol, LocalMessageDataServiceProtocol, MessageDataProcessProtocol {

    typealias ReadBlock = (() -> Void)

    // TODO: those 3 var need to double check to clean up
    var pushNotificationMessageID: String?

    let apiService: APIService
    let userID: UserID
    weak var userDataSource: UserDataSource?
    let labelDataService: LabelsDataService
    let contactDataService: ContactDataService
    let localNotificationService: LocalNotificationService
    let contextProvider: CoreDataContextProviderProtocol
    let lastUpdatedStore: LastUpdatedStoreProtocol
    let cacheService: CacheService
    let messageDecrypter: MessageDecrypterProtocol
    let undoActionManager: UndoActionManagerProtocol
    let contactCacheStatus: ContactCacheStatusProtocol

    weak var viewModeDataSource: ViewModeDataSource?

    weak var queueManager: QueueManager?
    weak var parent: UserManager?

    init(api: APIService,
         userID: UserID,
         labelDataService: LabelsDataService,
         contactDataService: ContactDataService,
         localNotificationService: LocalNotificationService,
         queueManager: QueueManager?,
         contextProvider: CoreDataContextProviderProtocol,
         lastUpdatedStore: LastUpdatedStoreProtocol,
         user: UserManager,
         cacheService: CacheService,
         undoActionManager: UndoActionManagerProtocol,
         contactCacheStatus: ContactCacheStatusProtocol) {
        self.apiService = api
        self.userID = userID
        self.labelDataService = labelDataService
        self.contactDataService = contactDataService
        self.localNotificationService = localNotificationService
        self.contextProvider = contextProvider
        self.lastUpdatedStore = lastUpdatedStore
        self.parent = user
        self.cacheService = cacheService
        self.messageDecrypter = MessageDecrypter(userDataSource: user)
        self.undoActionManager = undoActionManager
        self.contactCacheStatus = contactCacheStatus

        setupNotifications()
        self.queueManager = queueManager
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func fetchMessages(labelID: LabelID, endTime: Int, fetchUnread: Bool, completion: @escaping (_ task: URLSessionDataTask?, _ result: Swift.Result<JSONDictionary, ResponseError>) -> Void) {
        let request = FetchMessagesByLabelRequest(labelID: labelID.rawValue, endTime: endTime, isUnread: fetchUnread)
        apiService.perform(request: request, jsonDictionaryCompletion: completion)
    }

    func fetchMessagesCount(completion: @escaping (MessageCountResponse) -> Void) {
        let counterRoute = MessageCountRequest()
        apiService.perform(request: counterRoute, response: MessageCountResponse()) { _, response in
            completion(response)
        }
    }

    // MAKR : upload attachment

    // MARK: - - Refactored functions

    ///  nonmaly fetching the message from server based on label and time. //TODO:: change to promise
    ///
    /// - Parameters:
    ///   - labelID: labelid, location id, forlder id
    ///   - time: the latest update time
    ///   - forceClean: force clean the exsition messages first
    ///   - onDownload: Closure called when items have been downloaded but not yet parsed. Gives a chance to clean up right before we add a new dataset
    ///   - completion: aync complete handler

    @available(*, deprecated, message: "Moving to FetchMessagesUseCase")
    func fetchMessages(byLabel labelID: LabelID, time: Int, forceClean: Bool, isUnread: Bool, queued: Bool = true, completion: @escaping CompletionBlock, onDownload: (() -> Void)? = nil) {
        let queue = queued ? queueManager?.queue : noQueue
        queue? {
            let completionWrapper: (_ task: URLSessionDataTask?, _ result: Swift.Result<JSONDictionary, ResponseError>) -> Void = { task, result in
                do {
                    let response = try result.get()
                    onDownload?()
                    try self.cacheService.parseMessagesResponse(
                        labelID: labelID,
                        isUnread: isUnread,
                        response: response,
                        idsOfMessagesBeingSent: self.idsOfMessagesBeingSent()
                    )

                            let counterRoute = MessageCountRequest()
                            self.apiService.perform(request: counterRoute, response: MessageCountResponse()) { _, response in
                                if response.error == nil {
                                    self.parent?.eventsService.processEvents(messageCounts: response.counts)
                                }
                            }
                            DispatchQueue.main.async {
                                completion(task, response, nil)
                            }
                } catch {
                    DispatchQueue.main.async {
                        completion(task, nil, error as NSError?)
                    }
                }
            }
            let request = FetchMessagesByLabelRequest(labelID: labelID.rawValue, endTime: time, isUnread: isUnread)
            self.apiService.perform(request: request, jsonDictionaryCompletion: completionWrapper)
        }
    }

    func isEventIDValid() -> Bool {
        let eventID = lastUpdatedStore.lastEventID(userID: self.userID)
        return eventID != "" && eventID != "0"
    }

    /// Sync mail setting when user in composer
    /// workaround
    func syncMailSetting() {
        self.queueManager?.queue {
            let eventAPI = EventCheckRequest(eventID: self.lastUpdatedStore.lastEventID(userID: self.userID))
            self.apiService.perform(request: eventAPI, response: EventCheckResponse()) { _, response in
                guard response.responseCode == 1000 else {
                    return
                }
                self.parent?.eventsService.processEvents(mailSettings: response.mailSettings)
                self.parent?.eventsService.processEvents(space: response.usedSpace)
            }
        }
    }

    /// upload attachment to server
    ///
    /// - Parameter att: Attachment
    func upload(att: Attachment) {
        self.queue(att: att, action: .uploadAtt(attachmentObjectID: att.objectID.uriRepresentation().absoluteString))
    }

    /// delete attachment from server
    ///
    /// - Parameter att: Attachment
    func delete(att: AttachmentEntity, messageID: MessageID) -> Promise<Void> {
        return Promise { seal in
            let objectID = att.objectID.rawValue.uriRepresentation().absoluteString
            let task = QueueManager.Task(
                messageID: messageID.rawValue,
                action: .deleteAtt(attachmentObjectID: objectID,
                                   attachmentID: att.id.rawValue),
                userID: self.userID,
                dependencyIDs: [],
                isConversation: false
            )
            _ = self.queueManager?.addTask(task)
            self.cacheService.delete(attachment: att) {
                seal.fulfill_()
            }
        }
    }

    func updateAttKeyPacket(message: MessageEntity, addressID: String) {
        let objectID = message.objectID.rawValue.uriRepresentation().absoluteString
        self.queue(.updateAttKeyPacket(messageObjectID: objectID, addressID: addressID))
    }

    // MARK : Send message

    func send(inQueue message: Message, deliveryTime: Date?) {
        message.managedObjectContext!.perform {
            self.localNotificationService.scheduleMessageSendingFailedNotification(
                .init(messageID: message.messageID, subtitle: message.title)
            )

            self.queue(
                message: message,
                action: .send(messageObjectID: message.objectID.uriRepresentation().absoluteString, deliveryTime: deliveryTime)
            )
        }
    }

    func updateMessageCount(completion: (() -> Void)? = nil) {
        self.queueManager?.queue {
            guard let viewMode = self.viewModeDataSource?.getCurrentViewMode() else {
                completion?()
                return
            }

            switch viewMode {
            case .singleMessage:
                let counterApi = MessageCountRequest()
                self.apiService.perform(request: counterApi, response: MessageCountResponse()) { _, response in
                    guard response.error == nil else {
                        completion?()
                        return
                    }
                    self.parent?.eventsService.processEvents(messageCounts: response.counts)
                    completion?()
                }
            case .conversation:
                let conversationCountApi = ConversationCountRequest(addressID: nil)
                self.apiService.perform(request: conversationCountApi, response: ConversationCountResponse()) { _, response in
                    guard response.error == nil else {
                        completion?()
                        return
                    }
                    let countDict = response.responseDict?["Counts"] as? [[String: Any]]
                    self.parent?.eventsService.processEvents(conversationCounts: countDict)
                    completion?()
                }
            }
        }
    }

    // TODO: fixme - double check it  // this way is a little bit hacky. future we will prebuild the send message body
    func injectTransientValuesIntoMessages() {
        let ids = queueManager?.queuedMessageIds() ?? []
        contextProvider.performOnRootSavingContext { context in
            ids.forEach { messageID in
                guard let objectID = self.contextProvider.managedObjectIDForURIRepresentation(messageID),
                      let managedObject = try? context.existingObject(with: objectID) else {
                    return
                }
                if let message = managedObject as? Message {
                    self.cachePropertiesForBackground(in: message)
                }
                if let attachment = managedObject as? Attachment {
                    self.cachePropertiesForBackground(in: attachment.message)
                }
            }
        }
    }

    //// only needed for drafts
    private func cachePropertiesForBackground(in message: Message) {
        // these cached objects will allow us to update the draft, upload attachment and send the message after the mainKey will be locked
        // they are transient and will not be persisted in the db, only in managed object context
        message.cachedPassphrase = userDataSource!.mailboxPassword
        message.cachedAuthCredential = userDataSource!.authCredential
        message.cachedUser = userDataSource!.userInfo
        if let addressID = message.addressID {
            message.cachedAddress = defaultUserAddress(of: AddressID(addressID)) // computed property depending on current user settings
        }
    }

    func empty(location: Message.Location) {
        self.empty(labelID: location.labelID)
    }

    func empty(labelID: LabelID) {
        self.cacheService.markMessageAndConversationDeleted(labelID: labelID)
        self.labelDataService.resetCounter(labelID: labelID)
        queue(.empty(currentLabelID: labelID.rawValue))
    }

    private func noQueue(_ readBlock: @escaping ReadBlock) {
        readBlock()
    }

    @available(*, deprecated, message: "Moving to FetchMessageDetailUseCase")
    func forceFetchDetailForMessage(
        _ message: MessageEntity,
        runInQueue: Bool = true,
        ignoreDownloaded: Bool = false,
        completion: @escaping (NSError?) -> Void
    ) {
        let msgID = message.messageID
        let closure = runInQueue ? self.queueManager?.queue : noQueue
        closure? {
            let completionWrapper: (_ task: URLSessionDataTask?, _ result: Swift.Result<JSONDictionary, ResponseError>) -> Void = { _, result in
                let objectId = message.objectID.rawValue
                self.contextProvider.performOnRootSavingContext { context in
                    let response = try? result.get()
                    var error = result.error as NSError?
                    if let newMessage = context.object(with: objectId) as? Message, response != nil {
                        // TODO: need check the response code
                        if var msg: [String: Any] = response?["Message"] as? [String: Any] {
                            msg.removeValue(forKey: "Location")
                            msg.removeValue(forKey: "Starred")
                            msg.removeValue(forKey: "test")
                            msg["UserID"] = self.userID.rawValue
                            msg.addAttachmentOrderField()

                            do {
                                if !ignoreDownloaded,
                                   newMessage.isDetailDownloaded,
                                   let time = msg["Time"] as? TimeInterval,
                                   let oldTime = newMessage.time?.timeIntervalSince1970 {
                                    // remote time and local time are not empty
                                    if oldTime > time {
                                        DispatchQueue.main.async {
                                            completion(error)
                                        }
                                        return
                                    }
                                }
                                let localAttachments = newMessage.attachments.allObjects.compactMap { $0 as? Attachment}.filter { attach in
                                    if attach.isSoftDeleted {
                                        return false
                                    }
                                    return !attach.inline()
                                }
                                let localAttachmentCount = localAttachments.count

                                // This will remove all attachments that are still not uploaded to BE
                                try GRTJSONSerialization.object(withEntityName: Message.Attributes.entityName, fromJSONDictionary: msg, in: context)

                                // Adds back the attachments that are still uploading
                                for att in localAttachments {
                                    if att.managedObjectContext != nil {
                                        if !newMessage.attachments.contains(att) {
                                            newMessage.attachments.adding(att)
                                            att.message = newMessage
                                        }
                                    } else {
                                        if let newAtt = context.object(with: att.objectID) as? Attachment {
                                            if !newMessage.attachments.contains(newAtt) {
                                                newMessage.attachments.adding(newAtt)
                                                newAtt.message = newMessage
                                            }
                                        }
                                    }
                                }

                                // Use local attachment count since the not-uploaded attachment is not counted
                                newMessage.numAttachments = NSNumber(value: localAttachmentCount)
                                newMessage.isDetailDownloaded = true
                                newMessage.messageStatus = 1
                                if newMessage.unRead {
                                    self.cacheService.updateCounterSync(markUnRead: false, on: newMessage)
                                    if let labelID = newMessage.firstValidFolder() {
                                        self.mark(
                                            messageObjectIDs: [objectId],
                                            labelID: LabelID(labelID),
                                            unRead: false,
                                            context: context
                                        )
                                    }
                                }

                                newMessage.unRead = false
                                PushUpdater().remove(notificationIdentifiers: [newMessage.notificationId])
                                error = context.saveUpstreamIfNeeded()
                                DispatchQueue.main.async {
                                    completion(error)
                                }
                            } catch let ex as NSError {
                                DispatchQueue.main.async {
                                    completion(ex)
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                completion(NSError.badResponse())
                            }
                        }
                    } else {
                        error = NSError.unableToParseResponse(response)
                        DispatchQueue.main.async {
                            completion(error)
                        }
                    }
                }
            }
            let request = MessageDetailRequest(messageID: msgID)
            self.apiService.perform(request: request, jsonDictionaryCompletion: completionWrapper)
        }
    }

    func fetchNotificationMessageDetail(_ messageID: MessageID, completion: @escaping (Error?) -> Void) {
        self.queueManager?.queue {
            let completionWrapper: (_ task: URLSessionDataTask?, _ result: Swift.Result<JSONDictionary, ResponseError>) -> Void = { task, result in
                self.contextProvider.performOnRootSavingContext { context in
                    switch result {
                    case .success(let response):
                        // TODO: need check the respons code
                        if var msg: [String: Any] = response["Message"] as? [String: Any] {
                            msg.removeValue(forKey: "Location")
                            msg.removeValue(forKey: "Starred")
                            msg.removeValue(forKey: "test")
                            msg["UserID"] = self.userID.rawValue
                            msg.addAttachmentOrderField()

                            do {
                                if let messageOut = try GRTJSONSerialization.object(withEntityName: Message.Attributes.entityName, fromJSONDictionary: msg, in: context) as? Message {
                                    messageOut.messageStatus = 1
                                    messageOut.isDetailDownloaded = true
                                    if messageOut.unRead == true {
                                        messageOut.unRead = false
                                        PushUpdater().remove(notificationIdentifiers: [messageOut.notificationId])
                                        self.cacheService.updateCounterSync(markUnRead: false, on: messageOut)
                                    }
                                    let tmpError = context.saveUpstreamIfNeeded()
                                    if let labelID = messageOut.firstValidFolder() {
                                        self.mark(
                                            messageObjectIDs: [messageOut.objectID],
                                            labelID: LabelID(labelID),
                                            unRead: false,
                                            context: context
                                        )
                                    }

                                    DispatchQueue.main.async {
                                        completion(tmpError)
                                    }
                                }
                            } catch let ex as NSError {
                                DispatchQueue.main.async {
                                    completion(ex)
                                }
                            }
                        } else {
                            DispatchQueue.main.async {
                                completion(NSError.badResponse())
                            }
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            completion(error)
                        }
                    }
                }
            }

            self.contextProvider.performOnRootSavingContext { context in
                guard
                    let message = Message.messageForMessageID(messageID.rawValue,
                                                              inManagedObjectContext: context),
                    message.isDetailDownloaded
                else {
                    let request = MessageDetailRequest(messageID: messageID)
                    self.apiService.perform(request: request, jsonDictionaryCompletion: completionWrapper)
                    return
                }
                if let labelID = message.firstValidFolder() {
                    self.mark(messageObjectIDs: [message.objectID], labelID: LabelID(labelID), unRead: false, context: context)
                }
                DispatchQueue.main.async {
                    completion(nil)
                }
            }
        }
    }

    // MARK: fuctions for only fetch the local cache

    /**
     fetch the message by location from local cache

     :param: location message location enum

     :returns: NSFetchedResultsController
     */
    func fetchedResults(by labelID: LabelID,
                        viewMode: ViewMode,
                        isUnread: Bool = false,
                        isAscending: Bool = false) -> NSFetchedResultsController<NSFetchRequestResult>? {
        switch viewMode {
        case .singleMessage:
            let moc = self.contextProvider.mainContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Message.Attributes.entityName)
            if isUnread {
                fetchRequest.predicate = NSPredicate(format: "(ANY labels.labelID = %@) AND (%K > %d) AND (%K == %@) AND (%K == %@) AND (%K == %@)",
                                                     labelID.rawValue,
                                                     Message.Attributes.messageStatus,
                                                     0,
                                                     Message.Attributes.userID,
                                                     self.userID.rawValue,
                                                     Message.Attributes.unRead,
                                                     NSNumber(true),
                                                     Message.Attributes.isSoftDeleted,
                                                     NSNumber(false))
            } else {
                fetchRequest.predicate = NSPredicate(format: "(ANY labels.labelID = %@) AND (%K > %d) AND (%K == %@) AND (%K == %@)",
                                                     labelID.rawValue,
                                                     Message.Attributes.messageStatus,
                                                     0,
                                                     Message.Attributes.userID,
                                                     self.userID.rawValue,
                                                     Message.Attributes.isSoftDeleted,
                                                     NSNumber(false))
            }
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(Message.time), ascending: isAscending),
                                            NSSortDescriptor(key: #keyPath(Message.order), ascending: isAscending)]
            fetchRequest.fetchBatchSize = 30
            fetchRequest.includesPropertyValues = true
            return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
        case .conversation:
            let moc = self.contextProvider.mainContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ContextLabel.Attributes.entityName)
            if isUnread {
                fetchRequest.predicate = NSPredicate(format: "(%K == %@) AND (%K == %@) AND (conversation != nil) AND (%K > 0) AND (%K == %@)",
                                                     ContextLabel.Attributes.labelID,
                                                     labelID.rawValue,
                                                     ContextLabel.Attributes.userID,
                                                     self.userID.rawValue,
                                                     ContextLabel.Attributes.unreadCount,
                                                     "conversation.\(Conversation.Attributes.isSoftDeleted)",
                                                     NSNumber(false))
            } else {
                fetchRequest.predicate = NSPredicate(format: "(%K == %@) AND (%K == %@) AND (conversation != nil) AND (%K == %@)",
                                                     ContextLabel.Attributes.labelID,
                                                     labelID.rawValue,
                                                     ContextLabel.Attributes.userID,
                                                     self.userID.rawValue,
                                                     "conversation.\(Conversation.Attributes.isSoftDeleted)",
                                                     NSNumber(false))
            }
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ContextLabel.time, ascending: isAscending),
                                            NSSortDescriptor(keyPath: \ContextLabel.order, ascending: isAscending)]
            fetchRequest.fetchBatchSize = 30
            fetchRequest.includesPropertyValues = true
            return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
        }
    }

    /**
     fetch the message from local cache use message id

     :param: messageID String

     :returns: NSFetchedResultsController
     */
    func fetchedMessageControllerForID(_ messageID: MessageID) -> NSFetchedResultsController<Message> {
        let moc = self.contextProvider.mainContext
        let fetchRequest = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", Message.Attributes.messageID, messageID.rawValue)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Message.Attributes.time, ascending: false), NSSortDescriptor(key: #keyPath(Message.order), ascending: false)]
        return NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: moc, sectionNameKeyPath: nil, cacheName: nil)
    }

    /**
     clean all the local cache data.
     when use this :
     1. logout
     2. local cache version changed
     3. hacked action detacted
     4. use wraped manully.
     */
    func cleanUp() -> Promise<Void> {
        return self.cleanMessage(cleanBadgeAndNotifications: true).done { _ in
            self.lastUpdatedStore.removeUpdateTime(by: self.userID, type: .singleMessage)
            self.lastUpdatedStore.removeUpdateTime(by: self.userID, type: .conversation)
            self.signout()
        }
    }

    func signin() {
        self.queue(.signin)
    }

    private func signout() {
        self.queue(.signout)
    }

    static func cleanUpAll() -> Promise<Void> {
        return Promise { seal in
            let queueManager = sharedServices.get(by: QueueManager.self)
            queueManager.clearAll {
                let coreDataService = sharedServices.get(by: CoreDataService.self)
                coreDataService.enqueueOnRootSavingContext { context in
                    Message.deleteAll(inContext: context)
                    Conversation.deleteAll(inContext: context)
                    _ = context.saveUpstreamIfNeeded()
                    seal.fulfill_()
                }
            }
        }
    }

    func cleanMessage(removeAllDraft: Bool = true, cleanBadgeAndNotifications: Bool) -> Promise<Void> {
        return Promise { seal in
            self.contextProvider.performOnRootSavingContext { context in
                self.removeMessageFromDB(context: context, removeAllDraft: removeAllDraft)

                let contextLabelFetch = NSFetchRequest<ContextLabel>(entityName: ContextLabel.Attributes.entityName)
                contextLabelFetch.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                                          ContextLabel.Attributes.userID,
                                                          self.userID.rawValue,
                                                          ContextLabel.Attributes.isSoftDeleted,
                                                          NSNumber(false))
                if let labels = try? context.fetch(contextLabelFetch) {
                    labels.forEach { context.delete($0) }
                }

                let conversationFetch = NSFetchRequest<Conversation>(entityName: Conversation.Attributes.entityName)
                conversationFetch.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                                          Conversation.Attributes.userID.rawValue,
                                                          self.userID.rawValue,
                                                          Conversation.Attributes.isSoftDeleted.rawValue,
                                                          NSNumber(false))
                if let conversations = try? context.fetch(conversationFetch) {
                    conversations.forEach { context.delete($0) }
                }

                _ = context.saveUpstreamIfNeeded()
                context.refreshAllObjects()

                if cleanBadgeAndNotifications {
                    UIApplication.setBadge(badge: 0)
                }
                seal.fulfill_()
            }
        }
    }

    // Remove message from db
    // In some conditions, some of the messages can't be deleted
    private func removeMessageFromDB(context: NSManagedObjectContext, removeAllDraft: Bool) {
        let fetch = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        // Don't delete the soft deleted message
        // Or they would come back when user pull down to refresh
        fetch.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                      Message.Attributes.userID,
                                      self.userID.rawValue,
                                      Message.Attributes.isSoftDeleted,
                                      NSNumber(false))

        guard let results = try? context.fetch(fetch) else {
            return
        }

        if removeAllDraft {
            results.forEach { context.delete($0) }
            return
        }
        let draftID = Message.Location.draft.rawValue

        for message in results {
            if let labels = message.labels.allObjects as? [Label] {
                if !labels.contains(where: { $0.labelID == draftID }) {
                    context.delete(message)
                }
            }
        }

        // The remove is triggered by pull down to refresh
        // So if the messages correspond to some conditions, can't delete it
        for message in results {
            if let labels = message.labels.allObjects as? [Label],
               labels.contains(where: { $0.labelID == draftID }) {
                if let attachments = message.attachments.allObjects as? [Attachment],
                   attachments.contains(where: { $0.attachmentID == "0" }) {
                    // If the draft is uploading attachments, don't delete it
                    continue
                } else if isMessageBeingSent(id: message.messageID) {
                    // If the draft is sending, don't delete it
                    continue
                } else if let _ = UUID(uuidString: message.messageID) {
                    // If the message ID is UUiD, means hasn't created draft, don't delete it
                    continue
                }
                context.delete(message)
            }
        }
    }

    func search(_ query: String, page: Int, completion: @escaping (Swift.Result<[Message], Error>) -> Void) {
        let completionWrapper: ([String: Any]?, Error?) -> Void = { response, error in
            if let error = error {
                completion(.failure(error))
            } else if var messagesArray = response?["Messages"] as? [[String: Any]] {
                for (index, _) in messagesArray.enumerated() {
                    messagesArray[index]["UserID"] = self.userID.rawValue
                }
                self.contextProvider.performOnRootSavingContext { context in
                    do {
                        if let messages = try GRTJSONSerialization.objects(withEntityName: Message.Attributes.entityName, fromJSONArray: messagesArray, in: context) as? [Message] {
                            for message in messages {
                                message.messageStatus = 1
                            }
                            _ = context.saveUpstreamIfNeeded()

                            completion(.success(messages))
                        } else {
                            fatalError("Groot output must be a Message.")
                        }
                    } catch let ex as NSError {
                        completion(.failure(ex))
                    }
                }
            } else {
                let parseError = NSError(
                    domain: APIServiceErrorDomain,
                    code: APIErrorCode.badParameter,
                    localizedDescription: "Unexpected data returned by the API."
                )
                completion(.failure(parseError))
            }
        }
        let api = SearchMessageRequest(keyword: query, page: page)
        self.apiService.perform(request: api, response: SearchMessageResponse()) { _, response in
            if let error = response.error {
                completionWrapper(nil, error)
            } else {
                completionWrapper(response.jsonDic, nil)
            }
        }
    }

    func saveDraft(_ message: Message?) {
        if let message = message, let context = message.managedObjectContext {
            context.performAndWait {
                if message.title.isEmpty {
                    message.title = "(No Subject)"
                }
                _ = context.saveUpstreamIfNeeded()

                self.queue(
                    message: message,
                    action: .saveDraft(messageObjectID: message.objectID.uriRepresentation().absoluteString)
                )
            }
        }
    }

    func fetchMessageMetaData(messageIDs: [MessageID], completion: @escaping (FetchMessagesByIDResponse) -> Void) {
        let messages: [String] = messageIDs.map(\.rawValue)
        let request = FetchMessagesByID(msgIDs: messages)
        self.apiService
            .perform(request: request, response: FetchMessagesByIDResponse()) { _, response in
                completion(response)
            }
    }

    // MARK: old functions

    fileprivate func attachmentsForMessage(_ message: Message) -> [Attachment] {
        if let all = message.attachments.allObjects as? [Attachment] {
            return all.filter { !$0.isSoftDeleted }.sorted(by: { $0.order < $1.order })
        }
        return []
    }

    struct SendStatus: OptionSet {
        let rawValue: Int

        static let justStart = SendStatus([])
        static let fetchEmailOK = SendStatus(rawValue: 1 << 0)
        static let getBody = SendStatus(rawValue: 1 << 1)
        static let updateBuilder = SendStatus(rawValue: 1 << 2)
        static let processKeyResponse = SendStatus(rawValue: 1 << 3)
        static let checkMimeAndPlainText = SendStatus(rawValue: 1 << 4)
        static let setAtts = SendStatus(rawValue: 1 << 5)
        static let goNext = SendStatus(rawValue: 1 << 6)
        static let checkMime = SendStatus(rawValue: 1 << 7)
        static let buildMime = SendStatus(rawValue: 1 << 8)
        static let checkPlainText = SendStatus(rawValue: 1 << 9)
        static let buildPlainText = SendStatus(rawValue: 1 << 10)
        static let initBuilders = SendStatus(rawValue: 1 << 11)
        static let encodeBody = SendStatus(rawValue: 1 << 12)
        static let buildSend = SendStatus(rawValue: 1 << 13)
        static let sending = SendStatus(rawValue: 1 << 14)
        static let done = SendStatus(rawValue: 1 << 15)
        static let doneWithError = SendStatus(rawValue: 1 << 16)
        static let exceptionCatched = SendStatus(rawValue: 1 << 17)
    }

    enum SendingError: Error {
        case emptyEncodedBody
    }

    func getMessageSendingData(for uri: String) -> MessageSendingData? {
        // TODO: Use `CoreDataContextProviderProtocol.read` when available
        var messageSendingData: MessageSendingData?
        contextProvider.performAndWaitOnRootSavingContext { [weak self] context in
            guard let objectID = self?.contextProvider.managedObjectIDForURIRepresentation(uri) else {
                return
            }
            guard let message = context.find(with: objectID) as? Message else {
                return
            }
            let msg = MessageEntity(message)
            messageSendingData = MessageSendingData(
                message: msg,
                cachedUserInfo: message.cachedUser,
                cachedAuthCredential: message.cachedAuthCredential,
                cachedSenderAddress: message.cachedAddress,
                defaultSenderAddress: self?.defaultUserAddress(of: msg.addressID)
            )
        }
        return messageSendingData
    }

    func updateMessageAfterSend(
        message: MessageEntity,
        sendResponse: JSONDictionary,
        completionQueue: DispatchQueue,
        completion: @escaping () -> Void
    ) {
        contextProvider.performOnRootSavingContext { [unowned self] context in
            if let newMessage = try? GRTJSONSerialization.object(
                withEntityName: Message.Attributes.entityName,
                fromJSONDictionary: sendResponse["Sent"] as! [String: Any],
                in: context
            ) as? Message {
                newMessage.messageStatus = 1
                newMessage.isDetailDownloaded = true
                newMessage.unRead = false
            } else {
                assertionFailure("Failed to parse response Message")
            }
            if context.saveUpstreamIfNeeded() == nil {
                _ = markReplyStatus(message.originalMessageID, action: message.action)
            }
            completionQueue.async {
                completion()
            }
        }
    }

    func send(byID objectIDInURI: String, deliveryTime: Date?, UID: String, completion: @escaping (Error?) -> Void) {
        // TODO: needs to refractor
        self.contextProvider.performOnRootSavingContext { context in
            guard let objectID = self.contextProvider.managedObjectIDForURIRepresentation(objectIDInURI),
                  let message = context.find(with: objectID) as? Message
            else {
                completion(NSError.badParameter(objectIDInURI))
                return
            }
            guard let userManager = self.parent, userManager.userID.rawValue == UID else {
                completion(NSError.userLoggedOut())
                return
            }

            if message.messageID.isEmpty {
                completion(NSError.badParameter(objectIDInURI))
                return
            }

            if message.managedObjectContext == nil {
                NSError.alertLocalCacheErrorToast()
                let err = RuntimeError.bad_draft.error
                completion(err)
                return
            }

            self.forceFetchDetailForMessage(.init(message),
                                            runInQueue: false,
                                            ignoreDownloaded: true) { _ in
                self.send(message: message,
                          context: context,
                          userManager: userManager,
                          deliveryTime: deliveryTime,
                          completion: completion)
            }
        }
    }

    private func addBreadcrumbIfNeeded(
        addressIdFromMessage: String?,
        cachedAddress: Address?,
        defaultAddress: Address?
    ) {
        let prefix = 6
        let areAddressesDifferent = cachedAddress?.addressID != defaultAddress?.addressID
        if areAddressesDifferent {
            let message = """
            cached address \(cachedAddress?.addressID.prefix(prefix) ?? "_nil_")
            different from default address \(defaultAddress?.addressID.prefix(prefix) ?? "_nil_")
            | addressID in message: \(addressIdFromMessage ?? "_nil_")
            """
            Breadcrumbs.shared.add(message: message, to: .invalidSignatureWhenSendingMessage)
        }
    }

    private func send(
        message: Message,
        context: NSManagedObjectContext,
        userManager: UserManager,
        deliveryTime: Date?,
        completion: @escaping (Error?) -> Void
    ) {
        context.perform {
            var status = SendStatus.justStart

            let userInfo = message.cachedUser ?? userManager.userInfo

            _ = userInfo.userPrivateKeys

            let userPrivKeysArray = userInfo.userPrivateKeys
            let addrPrivKeys = userInfo.addressKeys

            let authCredential = message.cachedAuthCredential ?? userManager.authCredential
            let passphrase = message.cachedPassphrase ?? userManager.mailboxPassword
            guard let addressID = message.addressID,
                  let addressKey = (message.cachedAddress ?? userManager.messageService.defaultUserAddress(of: AddressID(addressID)))?.keys.first else {
                completion(NSError.lockError())
                return
            }
            self.addBreadcrumbIfNeeded(
                addressIdFromMessage: message.addressID,
                cachedAddress: message.cachedAddress,
                defaultAddress: userManager.messageService.defaultUserAddress(of: AddressID(addressID))
            )

            var requests = [UserEmailPubKeys]()
            let emails = message.allEmails
            for email in emails {
                requests.append(UserEmailPubKeys(email: email, authCredential: authCredential))
            }

            let isEncryptedToOutside = !message.password.isEmpty

            // get attachment
            let attachments = self.attachmentsForMessage(message)

            // create builder
            let dependencies = MessageSendingRequestBuilder.Dependencies(
                fetchAttachment: FetchAttachment(dependencies: .init(apiService: userManager.apiService))
            )
            let sendBuilder = MessageSendingRequestBuilder(dependencies: dependencies)

            let fetchAndVerifyContacts = FetchAndVerifyContacts(user: userManager)
            let fetchAndVerifyContactsParams = FetchAndVerifyContacts.Parameters(emailAddresses: emails)

            // build contacts if user setup key pinning
            var contacts = [PreContact]()
            firstly {
                Promise<[PreContact]> { seal in
                    fetchAndVerifyContacts.execute(params: fetchAndVerifyContactsParams) { result in
                        switch result {
                        case .success(let preContacts):
                            seal.fulfill(preContacts)
                        case .failure(let error):
                            seal.reject(error)
                        }
                    }
                }
            }.then { cs -> Guarantee<[Result<KeysResponse>]> in
                // Debug info
                status.insert(SendStatus.fetchEmailOK)
                // fech email keys from api
                contacts.append(contentsOf: cs)
                return when(resolved: requests.getPromises(api: userManager.apiService))
            }.then { results -> Promise<MessageSendingRequestBuilder> in
                // Debug info
                status.insert(SendStatus.getBody)
                return context.performAsPromise {
                    // all prebuild errors need pop up from here
                    guard let splited = try message.split(),
                          let bodyData = splited.dataPacket,
                          let keyData = splited.keyPacket,
                          let session = try keyData.getSessionFromPubKeyPackage(
                            userKeys: userPrivKeysArray,
                            passphrase: passphrase,
                            keys: addrPrivKeys
                          ) else {
                        throw RuntimeError.cant_decrypt.error
                    }
                    // Debug info
                    status.insert(SendStatus.updateBuilder)
                    let key = session.sessionKey
                    sendBuilder.update(bodyData: bodyData, bodySession: key, algo: session.algo)
                    sendBuilder.set(password: Password(value: message.password), hint: message.passwordHint)
                    // Debug info
                    status.insert(SendStatus.processKeyResponse)

                    for (index, result) in results.enumerated() {
                        switch result {
                        case .fulfilled(let value):
                            let req = requests[index]
                            let localContact = contacts.find(email: req.email)

                            let encryptionPreferences = EncryptionPreferencesHelper
                                .getEncryptionPreferences(
                                    email: req.email,
                                    keysResponse: value,
                                    userDefaultSign: userInfo.sign == 1,
                                    userAddresses: userManager.addresses,
                                    contact: localContact
                                )
                            let sendPreferences = SendPreferencesHelper
                                .getSendPreferences(
                                    encryptionPreferences: encryptionPreferences,
                                    isMessageHavingPWD: isEncryptedToOutside
                                )

                            sendBuilder.add(email: req.email, sendPreferences: sendPreferences)
                        case .rejected(let error):
                            throw error
                        }
                    }
                    // Debug info
                    status.insert(SendStatus.checkMimeAndPlainText)
                    if sendBuilder.hasMime || sendBuilder.hasPlainText {
                        guard let clearbody = try message.decryptBody(
                            keys: addrPrivKeys,
                            userKeys: userPrivKeysArray,
                            passphrase: passphrase
                        ) else {
                            throw RuntimeError.cant_decrypt.error
                        }
                        sendBuilder.set(clearBody: clearbody)
                    }
                    // Debug info
                    status.insert(SendStatus.setAtts)

                    for att in attachments {
                        if att.managedObjectContext != nil {
                            if let sessionPack = try att.getSession(
                                userKeys: userPrivKeysArray,
                                keys: addrPrivKeys,
                                mailboxPassword: userManager.mailboxPassword
                            ) {
                                let key = sessionPack.sessionKey
                                sendBuilder.add(attachment: PreAttachment(id: att.attachmentID,
                                                                          session: key,
                                                                          algo: sessionPack.algo,
                                                                          att: AttachmentEntity(att)))
                            }
                        }
                    }
                    // Debug info
                    status.insert(SendStatus.goNext)

                    return sendBuilder
                }
            }.then { sendbuilder -> Promise<MessageSendingRequestBuilder> in
                if !sendBuilder.hasMime {
                    return .value(sendBuilder)
                }
                return sendbuilder
                    .fetchAttachmentBodyForMime(passphrase: passphrase,
                                                userInfo: userInfo)
            }.then { _ -> Promise<MessageSendingRequestBuilder> in
                // Debug info
                status.insert(SendStatus.checkMime)

                if !sendBuilder.hasMime {
                    return .value(sendBuilder)
                }
                // Debug info
                status.insert(SendStatus.buildMime)

                // build pgp sending mime body
                return sendBuilder.buildMime(senderKey: addressKey,
                                             passphrase: passphrase,
                                             userKeys: userPrivKeysArray,
                                             keys: addrPrivKeys,
                                             in: context)
            }.then { _ -> Promise<MessageSendingRequestBuilder> in
                // Debug info
                status.insert(SendStatus.checkPlainText)

                if !sendBuilder.hasPlainText {
                    return .value(sendBuilder)
                }
                // Debug info
                status.insert(SendStatus.buildPlainText)

                // build pgp sending mime body
                return sendBuilder.buildPlainText(senderKey: addressKey,
                                                  passphrase: passphrase,
                                                  userKeys: userPrivKeysArray,
                                                  keys: addrPrivKeys)
            }.then { _ -> Guarantee<[Result<AddressPackageBase>]> in
                // Debug info
                status.insert(SendStatus.initBuilders)
                // build address packages
                let promises = try sendBuilder.getBuilderPromises()
                return when(resolved: promises)
            }.then { results -> Promise<SendMessageRequest> in
                context.performAsPromise {
                    // Debug info
                    status.insert(SendStatus.encodeBody)

                    // build api request
                    guard let encodedBody = sendBuilder.bodyDataPacket?.base64EncodedString(options: NSData.Base64EncodingOptions(rawValue: 0)) else {
                        throw SendingError.emptyEncodedBody
                    }

                    var msgs = [AddressPackageBase]()
                    for res in results {
                        switch res {
                        case .fulfilled(let value):
                            msgs.append(value)
                        case .rejected(let error):
                            throw error
                        }
                    }
                    // Debug info
                    status.insert(SendStatus.buildSend)

                    if let _ = UUID(uuidString: message.messageID) {
                        // Draft saved failed, can't send this message
                        let parseError = NSError(domain: APIServiceErrorDomain,
                                                 code: APIErrorCode.badParameter,
                                                 localizedDescription: "Invalid ID")
                        throw parseError
                    }
                    let delaySeconds = self.userDataSource?.userInfo.delaySendSeconds ?? 0
                    return SendMessageRequest(
                        messageID: message.messageID,
                        expirationTime: Int(message.expirationOffset),
                        delaySeconds: delaySeconds,
                        messagePackage: msgs,
                        body: encodedBody,
                        clearBody: sendBuilder.clearBodyPackage,
                        clearAtts: sendBuilder.clearAtts,
                        mimeDataPacket: sendBuilder.mimeBody,
                        clearMimeBody: sendBuilder.clearMimeBodyPackage,
                        plainTextDataPacket: sendBuilder.plainBody,
                        clearPlainTextBody: sendBuilder.clearPlainBodyPackage,
                        authCredential: authCredential,
                        deliveryTime: deliveryTime
                    )
                }
            }.then { sendApi -> Promise<SendResponse> in
                // Debug info
                status.insert(SendStatus.sending)
                return userManager.apiService.run(route: sendApi)
            }.done { [weak self] res in
                context.performAndWait { [weak self] in
                    guard let self = self,
                          let parent = self.parent,
                          parent.isLoggedOut == false else { return }
                    // Debug info
                    let error = res.error
                    if error == nil {
                        self.localNotificationService.unscheduleMessageSendingFailedNotification(.init(messageID: message.messageID))

                        #if APP_EXTENSION
                            NSError.alertMessageSentToast()
                        #else
                        if let deliveryTime = deliveryTime {
                            let labelID = Message.Location.scheduled.labelID
                            let messageID = MessageID(message.messageID)
                            self.parent?
                                .eventsService
                                .fetchEvents(byLabel: labelID, notificationMessageID: nil, completion: { _ in
                                    NotificationCenter.default.post(
                                        name: .scheduledMessageSucceed,
                                        object: (messageID,
                                                 deliveryTime,
                                                 self.userID)
                                    )
                            })
                        } else {
                            self.undoActionManager.showUndoSendBanner(for: MessageID(message.messageID))
                        }
                        #endif

                        if let newMessage = try? GRTJSONSerialization.object(withEntityName: Message.Attributes.entityName,
                                                                             fromJSONDictionary: res.responseDict["Sent"] as! [String: Any],
                                                                             in: context) as? Message {
                            newMessage.messageStatus = 1
                            newMessage.isDetailDownloaded = true
                            newMessage.unRead = false
                            PushUpdater().remove(notificationIdentifiers: [newMessage.notificationId])
                        } else {
                            assertionFailure("Failed to parse response Message")
                        }

                        if context.saveUpstreamIfNeeded() == nil,
                           let originalMsgID = message.orginalMessageID {
                            _ = self.markReplyStatus(MessageID(originalMsgID), action: message.action)
                        }
                    } else {
                        // Debug info
                        status.insert(SendStatus.doneWithError)
                        if error?.responseCode == 9001 {
                            // here need let user to show the human check.
                            self.queueManager?.isRequiredHumanCheck = true
                            error?.toNSError.alertSentErrorToast()
                        } else if error?.responseCode == 15198 {
                            error?.toNSError.alertSentErrorToast()
                        } else {
                            error?.toNSError.alertErrorToast()
                        }
                        NSError.alertMessageSentErrorToast()
                        // show message now
                        self.sendInvalidSignatureEventIfNeeded(responseCode: error?.responseCode ?? -1)
                        self.localNotificationService.scheduleMessageSendingFailedNotification(
                            .init(
                                messageID: message.messageID,
                                error: "\(LocalString._message_sent_failed_desc):\n\(error!.localizedDescription)",
                                timeInterval: 1,
                                subtitle: message.title
                            )
                        )
                    }
                    completion(error)
                }
            }.catch(policy: .allErrors) { error in
                status.insert(SendStatus.exceptionCatched)
                self.handleSendError(error: error, message: message) { error in
                    completion(error)
                }
            }
        }
    }

    func cancelQueuedSendingTask(messageID: String) {
        self.queueManager?.removeAllTasks(of: messageID, removalCondition: { action in
            switch action {
            case .send:
                return true
            default:
                return false
            }
        }, completeHandler: { [weak self] in
            self?.localNotificationService
                .unscheduleMessageSendingFailedNotification(.init(messageID: messageID))
        })
    }

    private func handleSendError(error: Error, message: Message, completion: @escaping (Error?) -> Void) {
        guard let err = error as? ResponseError,
              let responseCode = err.responseCode else {
            NSError.alertMessageSentError(details: error.localizedDescription)
            completion(error)
            return
        }

        var msgID = ""
        var msgEntity: MessageEntity?
        var title = ""
        message.managedObjectContext?.performAndWait {
            msgID = message.messageID
            msgEntity = MessageEntity(message)
            title = message.title
        }

        if responseCode == APIErrorCode.humanVerificationRequired {
            // here need let user to show the human check.
            self.queueManager?.isRequiredHumanCheck = true
            NSError.alertMessageSentError(details: err.localizedDescription)
        } else if responseCode == 15198 {
            NSError.alertMessageSentError(details: err.localizedDescription)
        } else if responseCode == APIErrorCode.alreadyExist || responseCode == 15004 {
            // The error means "Message has already been sent"
            // Since the message is sent, this alert is useless to user
            self.localNotificationService.unscheduleMessageSendingFailedNotification(.init(messageID: msgID))
            // Draft folder must be single message mode
            if let msgEntity = msgEntity {
                self.forceFetchDetailForMessage(msgEntity) { _ in }
            }
            completion(nil)
            return
        } else if responseCode == APIErrorCode.invalidRequirements {
            self.localNotificationService.unscheduleMessageSendingFailedNotification(.init(messageID: msgID))
            // The scheduled message exceeded maximum allowance
            NotificationCenter.default.post(name: .showScheduleSendUnavailable, object: nil)
            completion(nil)
            return
        } else if responseCode == PGPTypeErrorCode.emailAddressFailedValidation.rawValue {
            // Email address validation failed
            NSError.alertMessageSentError(details: err.localizedDescription)

            #if !APP_EXTENSION
            let title = LocalString._address_invalid_error_to_draft_action_title
            let toDraftAction = UIAlertAction(title: title, style: .default) { (_) in
                NotificationCenter.default.post(
                    name: .switchView,
                    object: DeepLink(
                        String(describing: MailboxViewController.self),
                        sender: Message.Location.draft.rawValue
                    )
                )
            }
            UIAlertController.showOnTopmostVC(
                title: LocalString._address_invalid_error_sending_title,
                message: LocalString._address_invalid_error_sending,
                action: toDraftAction
            )
            #endif
        } else {
            NSError.alertMessageSentError(details: err.localizedDescription)
        }

        // show message now
        let errorMsg = responseCode == PGPTypeErrorCode.emailAddressFailedValidation.rawValue ? LocalString._messages_validation_failed_try_again : "\(LocalString._messages_sending_failed_try_again):\n\(err.localizedDescription)"
        self.localNotificationService
            .scheduleMessageSendingFailedNotification(.init(messageID: msgID,
                                                            error: errorMsg,
                                                            timeInterval: 1,
                                                            subtitle: title))
        sendInvalidSignatureEventIfNeeded(responseCode: responseCode)
        completion(err)
    }

    private func sendInvalidSignatureEventIfNeeded(responseCode: Int) {
        guard responseCode == 2001 else { return }
        Breadcrumbs.shared.add(message: "Received error code \(responseCode)", to: .invalidSignatureWhenSendingMessage)
        Analytics.shared.sendError(
            .sendMessageInvalidSignature,
            trace: Breadcrumbs.shared.trace(for: .invalidSignatureWhenSendingMessage)
        )
    }
    
    private func markReplyStatus(_ oriMsgID: MessageID?, action : NSNumber?) -> Promise<Void> {
        guard let originMessageID = oriMsgID,
              let act = action,
              !originMessageID.rawValue.isEmpty else {
            return Promise()
        }

        let fetchRequest = NSFetchRequest<Message>(entityName: Message.Attributes.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", Message.Attributes.messageID, originMessageID.rawValue)
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: Message.Attributes.time, ascending: false),
            NSSortDescriptor(key: #keyPath(Message.order), ascending: false)
        ]

        return Promise { seal in
            self.contextProvider.performOnRootSavingContext { context in
                do {
                    guard let msgToUpdate = try fetchRequest.execute().first else {
                        seal.fulfill_()
                        return
                    }

                    // {0|1|2} // Optional, reply = 0, reply all = 1, forward = 2
                    if act == 0 {
                        msgToUpdate.replied = true
                    } else if act == 1 {
                        msgToUpdate.repliedAll = true
                    } else if act == 2 {
                        msgToUpdate.forwarded = true
                    } else {
                        // ignore
                    }

                    if let error = context.saveUpstreamIfNeeded(){
                        throw error
                    }

                    seal.fulfill_()
                } catch {
                    seal.reject(error)
                }
            }
        }
    }

    // MARK: Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(MessageDataService.didSignOutNotification(_:)),
                                               name: NSNotification.Name.didSignOut,
                                               object: nil)
        // TODO: add monitoring for didBecomeActive
    }

    @objc fileprivate func didSignOutNotification(_ notification: Notification) {
        _ = cleanUp()
    }

    private func queue(message: Message, action: MessageAction) {
        if message.objectID.isTemporaryID {
            do {
                try message.managedObjectContext?.obtainPermanentIDs(for: [message])
            } catch {
                assertionFailure("\(error)")
            }
        }
        var messageID = ""
        message.managedObjectContext?.performAndWait {
            self.cachePropertiesForBackground(in: message)
            messageID = message.messageID
        }
        switch action {
        case .saveDraft, .send:
            let task = QueueManager.Task(messageID: messageID, action: action, userID: self.userID, dependencyIDs: [], isConversation: false)
            _ = self.queueManager?.addTask(task)
        default:
            if message.managedObjectContext != nil, !messageID.isEmpty {
                let task = QueueManager.Task(messageID: messageID, action: action, userID: self.userID, dependencyIDs: [], isConversation: false)
                _ = self.queueManager?.addTask(task)
            }
        }
    }

    func queue(_ action: MessageAction) {
        let task = QueueManager.Task(messageID: "", action: action, userID: self.userID, dependencyIDs: [], isConversation: false)
        _ = self.queueManager?.addTask(task)
    }

    private func queue(att: Attachment, action: MessageAction) {
        if att.objectID.isTemporaryID {
            att.managedObjectContext?.performAndWait {
                try? att.managedObjectContext?.obtainPermanentIDs(for: [att])
            }
        }
        att.managedObjectContext?.performAndWait {
            self.cachePropertiesForBackground(in: att.message)
        }
        let updatedID = att.objectID.uriRepresentation().absoluteString
        var updatedAction: MessageAction?
        switch action {
        case .uploadAtt:
            updatedAction = .uploadAtt(attachmentObjectID: updatedID)
        case .uploadPubkey:
            updatedAction = .uploadPubkey(attachmentObjectID: updatedID)
        case .deleteAtt:
            updatedAction = .deleteAtt(attachmentObjectID: updatedID,
                                       attachmentID: att.attachmentID)
        default:
            break
        }
        let task = QueueManager.Task(messageID: att.message.messageID, action: updatedAction ?? action, userID: self.userID, dependencyIDs: [], isConversation: false)
        _ = self.queueManager?.addTask(task)
    }

    func cleanLocalMessageCache(completion: @escaping (Error?) -> Void) {
        let getLatestEventID = EventLatestIDRequest()
        self.apiService.perform(request: getLatestEventID, response: EventLatestIDResponse()) { _, response in
            guard response.error == nil, !response.eventID.isEmpty else {
                completion(response.error)
                return
            }
            self.contactCacheStatus.contactsCached = 0
            guard self.viewModeDataSource?.getCurrentViewMode() != nil else {
                return
            }

            let completionBlock: () -> Void = {
                self.labelDataService.fetchV4Labels { _ in
                    self.contactDataService.cleanUp().ensure {
                        self.contactDataService.fetchContacts { error in
                            if error == nil {
                                _ = self.lastUpdatedStore.updateEventID(by: self.userID, eventID: response.eventID).ensure {
                                    completion(error)
                                }
                            } else {
                                DispatchQueue.main.async {
                                    completion(error)
                                }
                            }
                        }
                    }.cauterize()
                }
            }

            self.fetchMessages(
                byLabel: Message.Location.inbox.labelID,
                time: 0,
                forceClean: false,
                isUnread: false,
                completion: { _, _, _ in
                    completionBlock()
                },
                onDownload: {
                    self.cleanMessage(cleanBadgeAndNotifications: true).then { _ -> Promise<Void> in
                        self.contactDataService.cleanUp()
                    }.cauterize()
                }
            )
        }
    }

    func encryptBody(_ addressID: AddressID,
                     clearBody: String,
                     mailbox_pwd: Passphrase) throws -> String {
        // TODO: Refactor this method later.
        let addressId = addressID.rawValue
        if addressId.isEmpty {
            return .empty
        }

        if let key = self.userDataSource?.getAddressKey(address_id: addressId) {
            return try clearBody.encrypt(withKey: key,
                                         userKeys: self.userDataSource!.userPrivateKeys,
                                         mailbox_pwd: mailbox_pwd)
        } else { // fallback
            let key = self.userDataSource!.getAddressPrivKey(address_id: addressId)
            return try clearBody.encryptNonOptional(withPrivKey: key, mailbox_pwd: mailbox_pwd.value)
        }
    }

    func getUserAddressID(for message: Message) -> String {
        if let addressID = message.addressID,
           let addr = defaultUserAddress(of: AddressID(addressID)) {
            return addr.addressID
        }
        return ""
    }

    func defaultUserAddress(of addressID: AddressID) -> Address? {
        guard let userInfo = userDataSource?.userInfo else {
            return nil
        }
        if !addressID.rawValue.isEmpty {
            if let addr = userInfo.userAddresses.address(byID: addressID.rawValue),
               addr.send == .active {
                return addr
            } else {
                if let addr = userInfo.userAddresses.defaultSendAddress() {
                    return addr
                }
            }
        } else {
            if let addr = userInfo.userAddresses.defaultSendAddress() {
                return addr
            }
        }
        return nil
    }

    func userAddress(of addressID: AddressID) -> Address? {
        guard let userInfo = userDataSource?.userInfo else {
            return nil
        }
        return userInfo.userAddresses.address(byID: addressID.rawValue)
    }

    func messageWithLocation(recipientList: String,
                             bccList: String,
                             ccList: String,
                             title: String,
                             encryptionPassword: String,
                             passwordHint: String,
                             expirationTimeInterval: TimeInterval,
                             body: String,
                             attachments: [Any]?,
                             mailbox_pwd: Passphrase,
                             sendAddress: Address,
                             inManagedObjectContext context: NSManagedObjectContext) -> Message {
        let message = Message(context: context)
        message.messageID = MessageID.generateLocalID().rawValue
        message.toList = recipientList
        message.bccList = bccList
        message.ccList = ccList
        message.title = title
        message.passwordHint = passwordHint
        message.time = Date()
        message.expirationOffset = Int32(expirationTimeInterval)
        message.messageStatus = 1
        message.setAsDraft()
        message.userID = self.userID.rawValue
        message.addressID = sendAddress.addressID

        if expirationTimeInterval > 0 {
            message.expirationTime = Date(timeIntervalSinceNow: expirationTimeInterval)
        }

        do {
            message.body = try self.encryptBody(.init(message.addressID ?? ""), clearBody: body, mailbox_pwd: mailbox_pwd)
            if !encryptionPassword.isEmpty {
                message.passwordEncryptedBody = try body.encryptNonOptional(password: encryptionPassword)
            }
            if let attachments = attachments {
                for (index, attachment) in attachments.enumerated() {
                    if let image = attachment as? UIImage {
                        if let fileData = image.pngData() {
                            let attachment = Attachment(context: context)
                            attachment.attachmentID = "0"
                            attachment.message = message
                            attachment.fileName = "\(index).png"
                            attachment.mimeType = "image/png"
                            attachment.fileData = fileData
                            attachment.fileSize = fileData.count as NSNumber
                            continue
                        }
                    }
                }
            }
        } catch {}
        return message
    }

    func updateMessage(_ message: Message,
                       expirationTimeInterval: TimeInterval,
                       body: String,
                       mailbox_pwd: Passphrase) {
        if expirationTimeInterval > 0 {
            message.expirationTime = Date(timeIntervalSinceNow: expirationTimeInterval)
        }
        message.body = (try? self.encryptBody(.init(message.addressID ?? ""), clearBody: body, mailbox_pwd: mailbox_pwd)) ?? ""
    }

    func undoSend(
        of messageId: MessageID,
        completion: @escaping (Swift.Result<UndoSendResponse, ResponseError>) -> Void
    ) {
        let request = UndoSendRequest(messageID: messageId)
        apiService.perform(request: request) { task, result in
            completion(result)
        }
    }
}
