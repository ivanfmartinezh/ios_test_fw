//
//  CoreDataCache.swift
//  Proton Mail - Created on 12/18/18.
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
import ProtonCore_Keymaker

/// core data related cache versioning. when clean or rebuild. should also rebuild the counter and queue
class CoreDataCache: Migrate {

    /// latest version, pass in from outside. should be constants in global.
    internal var latestVersion: Int

    /// concider pass this value in. keep the version tracking in app cache service
    internal var supportedVersions: [Int] = []

    /// saver for versioning
    private let versionSaver: Saver<Int>

    enum Key {
        static let coreDataVersion = "latest_core_data_cache"
    }
    enum Version: Int {
        // Change this value to rebuild coredata
        static let CacheVersion: Int = 5 // this is core data cache

        case v1 = 1
        case v2 = 2
    }

    init() {
        self.latestVersion = Version.CacheVersion
        self.versionSaver = UserDefaultsSaver<Int>(key: Key.coreDataVersion)
    }

    var currentVersion: Int {
        get {
            return self.versionSaver.get() ?? 0
        }
        set {
            self.versionSaver.set(newValue: newValue)
        }
    }

    var initalRun: Bool {
        get {
            return currentVersion == 0
        }
    }

    internal func migrate(from verfrom: Int, to verto: Int) -> Bool {
        return false
    }

    internal func rebuild(reason: RebuildReason) {
        CoreDataStore.deleteDataStore()

        if self.currentVersion <= Version.v2.rawValue {
            let userVersion = UserDefaultsSaver<Int>(key: UsersManager.CoderKey.Version)
            userVersion.set(newValue: 0)
            KeychainWrapper.keychain.remove(forKey: "BioProtection" + ".version")
            KeychainWrapper.keychain.remove(forKey: "PinProtection" + ".version")
        }

        // TODO:: fix me
        // sharedMessageDataService.cleanUp()
        self.currentVersion = self.latestVersion
    }

    internal func cleanLagacy() {

    }
}
