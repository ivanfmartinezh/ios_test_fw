//
//  OpenPGPTests.swift
//  ProtonMailTests
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
import XCTest
import GoLibs
import OpenPGP

class OpenPGPTests: XCTestCase {

    func testCheckPassphrase() {
        let result = PMNOpenPgp.checkPassphrase(OpenPGPDefines.privateKey,
                                                passphrase: OpenPGPDefines.passphrase.value)
        XCTAssertTrue(result, "checkPassphrase failed")
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            for _ in 0 ... 100 {
                let result = PMNOpenPgp.checkPassphrase(OpenPGPDefines.privateKey,
                                                        passphrase: OpenPGPDefines.passphrase.value)
                XCTAssertTrue(result, "checkPassphrase failed")
            }
        }
    }
    
    let openPGP = PMNOpenPgp.createInstance()
    func testEncryption() {
        self.measure {
            for _ in 0 ... 10 {
                let out = openPGP?.encryptMessageSingleKey(OpenPGPDefines.publicKey,
                                                           plainText: "test",
                                                           privateKey: "",
                                                           passphras: "",
                                                           trim: false)
                
                
                XCTAssertNotNil(out)
            }
        }
    }

}
