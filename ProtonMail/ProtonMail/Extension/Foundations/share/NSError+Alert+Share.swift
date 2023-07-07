//
//  NSError+Alert+Share.swift
//  Share - Created on 9/26/17.
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

extension NSError {
    static var errorOccuredNotification: NSNotification.Name {
        return NSNotification.Name("NSErrorOccured")
    }
    static var noErrorNotification: NSNotification.Name {
        return NSNotification.Name("NSErrorNoError")
    }

    class func alertMessageSentToast() {
        NotificationCenter.default.post(
            name: NSError.noErrorNotification,
            object: nil,
            userInfo: ["text": LocalString._message_sent_ok_desc]
        )
    }

    func alertSentErrorToast() {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": "\(LocalString._message_sent_failed_desc): \(self.localizedDescription)"]
        )
    }

    class func alertLocalCacheErrorToast() {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": LocalString._email_failed_to_send]
        )
    }

    func alertErrorToast() {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": NSLocalizedString(localizedDescription, comment: "Title")]
        )
    }

    class func alertMessageSentErrorToast() {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": LocalString._messages_sending_failed_try_again]
        )
    }

    class func alertMessageSentError(details: String) {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": LocalString._messages_sending_failed_try_again + " " + details]
        )
    }

    class func alertSavingDraftError(details: String) {
        NotificationCenter.default.post(
            name: NSError.errorOccuredNotification,
            object: nil,
            userInfo: ["text": details]
        )
    }
}
