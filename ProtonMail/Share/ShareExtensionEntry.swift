//
//  ShareExtensionEntry.swift
//  Share - Created on 6/28/17.
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
import ProtonCore_FeatureSwitch
import ProtonCore_Services
import ProtonCore_UIFoundations
import UIKit

@objc(ShareExtensionEntry)
class ShareExtensionEntry: UINavigationController {
    var appCoordinator: ShareAppCoordinator?

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.setup()
    }

    private func setup() {
        #if DEBUG
        PMAPIService.noTrustKit = true
        #endif
        DFSSetting.enableDFS = true
        DFSSetting.limitToXXXLarge = true
        TrustKitWrapper.start(delegate: self)
        configureCoreFeatureFlags()
        appCoordinator = ShareAppCoordinator(navigation: self)
        if #available(iOSApplicationExtension 15.0, *) {
            setupNavigationBarAppearance()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.appCoordinator?.start()
    }

    func configureCoreFeatureFlags() {
        FeatureFactory.shared.enable(&.unauthSession)
    }
}

extension ShareExtensionEntry: TrustKitUIDelegate {
    func onTrustKitValidationError(_ alert: UIAlertController) {
        self.appCoordinator?.navigationController?.present(alert, animated: true, completion: nil)
    }
}

extension ShareExtensionEntry {
    @available(iOS 15.0, *)
    private func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = ColorProvider.BackgroundNorm
        appearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
    }
}
