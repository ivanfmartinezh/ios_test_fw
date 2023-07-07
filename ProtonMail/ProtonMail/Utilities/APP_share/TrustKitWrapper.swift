//
//  TrustKitConfiguration.swift
//  Proton Mail - Created on 26/08/2019.
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

import TrustKit
import ProtonCore_Services

protocol TrustKitUIDelegate: AnyObject {
    func onTrustKitValidationError(_ alert: UIAlertController)
}

// TODO:: in the future move this to core NetworkingUI
final class TrustKitWrapper {
    typealias Delegate = TrustKitUIDelegate
    typealias Configuration = [String: Any]

    static private weak var delegate: Delegate?
    static private(set) var current: TrustKit?

    private static func configuration(hardfail: Bool = true) -> Configuration {
        let reportURIs: [String] = [
            "https://reports.proton.me/reports/tls"
        ]

        return [
            kTSKSwizzleNetworkDelegates: false,
            kTSKPinnedDomains: [
                "protonmail.ch": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKForceSubdomainMatch: true,
                    kTSKNoSSLValidation: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonmail.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "protonvpn.ch": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKForceSubdomainMatch: true,
                    kTSKNoSSLValidation: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "verify.protonmail.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "verify-api.protonmail.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "verify.protonvpn.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "verify-api.protonvpn.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "account.protonmail.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonvpn.ch certificate
                        "drtmcR2kFkM8qJClsuWgUzxgBkePfRCkRpqUesyDmeE=", // Current
                        "YRGlaY0jyJ4Jw2/4M8FIftwbDIQfh8Sdro96CeEel54=", // Hot backup
                        "AfMENBVvOS8MnISprtvyPsjKlPooqh8nMB/pvCrpJpw=", // Cold backup
                    ]
                ],
                "account.protonvpn.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // verify.protonvpn.com and verify-api.protonvpn.com
                        "8joiNBdqaYiQpKskgtkJsqRxF7zN0C0aqfi8DacknnI=", // Current
                        "JMI8yrbc6jB1FYGyyWRLFTmDNgIszrNEMGlgy972e7w=", // Hot backup
                        "Iu44zU84EOCZ9vx/vz67/MRVrxF1IO4i4NIa8ETwiIY=", // Cold backup
                    ]
                ],
                "protonmail.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // verify.protonmail.com and verify-api.protonmail.com certificate
                        "8joiNBdqaYiQpKskgtkJsqRxF7zN0C0aqfi8DacknnI=", // Current
                        "JMI8yrbc6jB1FYGyyWRLFTmDNgIszrNEMGlgy972e7w=", // Hot backup
                        "Iu44zU84EOCZ9vx/vz67/MRVrxF1IO4i4NIa8ETwiIY=", // Cold backup
                    ]
                ],
                "protonvpn.com": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // verify.protonvpn.com and verify-api.protonvpn.com
                        "8joiNBdqaYiQpKskgtkJsqRxF7zN0C0aqfi8DacknnI=", // Current
                        "JMI8yrbc6jB1FYGyyWRLFTmDNgIszrNEMGlgy972e7w=", // Hot backup
                        "Iu44zU84EOCZ9vx/vz67/MRVrxF1IO4i4NIa8ETwiIY=", // Cold backup
                    ]
                ],
                "proton.me": [
                    kTSKEnforcePinning: hardfail,
                    kTSKIncludeSubdomains: true,
                    kTSKForceSubdomainMatch: true,
                    kTSKNoSSLValidation: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // proton.me certificate
                        "CT56BhOTmj5ZIPgb/xD5mH8rY3BLo/MlhP7oPyJUEDo=", // Current
                        "35Dx28/uzN3LeltkCBQ8RHK0tlNSa2kCpCRGNp34Gxc=", // Hot backup
                        "qYIukVc63DEITct8sFT7ebIq5qsWmuscaIKeJx+5J5A=", // Cold backup
                    ]
                ],
                ".compute.amazonaws.com": [
                    kTSKEnforcePinning: true,
                    kTSKIncludeSubdomains: true,
                    kTSKForceSubdomainMatch: true,
                    kTSKNoSSLValidation: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonmail.ch and api.protonvpn.ch proxy domains certificates
                        "EU6TS9MO0L/GsDHvVc9D5fChYLNy5JdGYpJw0ccgetM=", // Current
                        "iKPIHPnDNqdkvOnTClQ8zQAIKG0XavaPkcEo0LBAABA=", // Backup 1
                        "MSlVrBCdL0hKyczvgYVSRNm88RicyY04Q2y5qrBt0xA=", // Backup 2
                        "C2UxW0T1Ckl9s+8cXfjXxlEqwAfPM4HiW2y3UdtBeCw=", // Backup 3
                    ]
                ],
                kTSKCatchallPolicy: [
                    kTSKEnforcePinning: true,
                    kTSKNoSSLValidation: true,
                    kTSKNoHostnameValidation: true,
                    kTSKAllowIPsOnly: true,
                    kTSKDisableDefaultReportUri: true,
                    kTSKReportUris: reportURIs,
                    kTSKPublicKeyHashes: [
                        // api.protonmail.ch and api.protonvpn.ch proxy domains certificates
                        "EU6TS9MO0L/GsDHvVc9D5fChYLNy5JdGYpJw0ccgetM=", // Current
                        "iKPIHPnDNqdkvOnTClQ8zQAIKG0XavaPkcEo0LBAABA=", // Backup 1
                        "MSlVrBCdL0hKyczvgYVSRNm88RicyY04Q2y5qrBt0xA=", // Backup 2
                        "C2UxW0T1Ckl9s+8cXfjXxlEqwAfPM4HiW2y3UdtBeCw=", // Backup 3
                    ]
                ]
            ]
        ]
    }

    static func start(delegate: Delegate?, customConfiguration: Configuration? = nil) {

        let config = customConfiguration ?? self.configuration()

        let instance: TrustKit = {
            #if !APP_EXTENSION
            return TrustKit(configuration: config)
            #else
            return TrustKit(configuration: config, sharedContainerIdentifier: Constants.AppGroup)
            #endif
        }()

        instance.pinningValidatorCallback = { validatorResult, hostName, policy in
            if validatorResult.evaluationResult != .success,
                validatorResult.finalTrustDecision != .shouldAllowConnection {
                if hostName.contains(check: ".compute.amazonaws.com") {
                    let alert = UIAlertController(title: LocalString._cert_validation_failed_title, message: LocalString._cert_validation_hardfailed_message, preferredStyle: .alert)
                    alert.addAction(.init(title: LocalString._general_cancel_button, style: .cancel, handler: { _ in /* nothing */ }))
                    self.delegate?.onTrustKitValidationError(alert)
                } else {
                    let alert = UIAlertController(title: LocalString._cert_validation_failed_title, message: LocalString._cert_validation_failed_message, preferredStyle: .alert)
                    alert.addAction(.init(title: LocalString._cert_validation_failed_continue, style: .destructive, handler: { _ in
                        self.start(delegate: delegate, customConfiguration: self.configuration(hardfail: false))
                    }))
                    alert.addAction(.init(title: LocalString._general_cancel_button, style: .cancel, handler: { _ in /* nothing */ }))
                    self.delegate?.onTrustKitValidationError(alert)
                }
            }
        }

        self.delegate = delegate
        self.current = instance
        PMAPIService.trustKit = instance
    }
}
