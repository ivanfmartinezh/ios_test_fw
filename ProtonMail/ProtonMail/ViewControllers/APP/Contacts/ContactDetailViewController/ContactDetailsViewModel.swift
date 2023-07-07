//
//  ContactDetailsViewModel.swift
//  Proton Mail - Created on 5/2/17.
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

typealias LoadingProgress = () -> Void

class ContactDetailsViewModel: NSObject {
    var user: UserManager
    let coreDataService: CoreDataService
    private(set) var contact: ContactEntity

    var reloadView: (() -> Void)?
    
    init(user: UserManager, coreDataService: CoreDataService, contact: ContactEntity) {
        self.user = user
        self.coreDataService = coreDataService
        self.contact = contact
        super.init()
    }

    func paidUser() -> Bool {
        return user.hasPaidMailPlan
    }

    @discardableResult
    func rebuild() -> Bool {
        fatalError("This method must be overridden")
    }

    func sections() -> [ContactEditSectionType] {
        fatalError("This method must be overridden")
    }

    func statusType2() -> Bool {
        fatalError("This method must be overridden")
    }

    func statusType3() -> Bool {
        fatalError("This method must be overridden")
    }

    func type3Error() -> Bool {
        fatalError("This method must be overridden")
    }

    func debugging() -> Bool {
        fatalError("This method must be overridden")
    }

    func hasEncryptedContacts() -> Bool {
        fatalError("This method must be overridden")
    }
    
    func getDetails(loading : LoadingProgress) -> Promise<Void> {
        fatalError("This method must be overridden")
    }
    
    func getContact() -> ContactEntity? {
        fatalError("This method must be overridden")
    }

    func setContact(_ contact: ContactEntity) {
        self.contact = contact
    }
    
    func getProfile() -> ContactEditProfile {
        fatalError("This method must be overridden")
    }

    func getProfilePicture() -> UIImage? {
        fatalError("This method must be overridden")
    }

    func getEmails() -> [ContactEditEmail] {
        fatalError("This method must be overridden")
    }

    func getPhones() -> [ContactEditPhone] {
        fatalError("This method must be overridden")
    }

    func getAddresses() -> [ContactEditAddress] {
        fatalError("This method must be overridden")
    }

    func getInformations() -> [ContactEditInformation] {
        fatalError("This method must be overridden")
    }

    func getFields() -> [ContactEditField] {
        fatalError("This method must be overridden")
    }

    func getNotes() -> [ContactEditNote] {
        fatalError("This method must be overridden")
    }

    func getUrls() -> [ContactEditUrl] {
        fatalError("This method must be overridden")
    }

    func export() -> String {
        fatalError("This method must be overridden")
    }

    func exportName() -> String {
        fatalError("This method must be overridden")
    }
}
