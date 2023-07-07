// Copyright (c) 2021 Proton AG
//
// This file is part of Proton Mail.
//
// Proton Mail is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Proton Mail is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Proton Mail. If not, see https://www.gnu.org/licenses/.

import Foundation
import ProtonCore_Networking
import class ProtonCore_Services.APIErrorCode

struct TaskCompletionHelper {
    enum Constant {
        static let networkResponseErrorKey = "com.alamofire.serialization.response.error.response"
    }

    func calculateIsInternetIssue(error: NSError, currentNetworkStatus: ConnectionStatus) -> Bool {
        var result = false

        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorSecureConnectionFailed,
                 NSURLErrorDataNotAllowed,
                 NSURLErrorCannotFindHost:
                result = true
            default:
                break
            }
        } else if error.domain == NSPOSIXErrorDomain &&
                    error.code == 100 {
            // Network protocol error
            result = true
        } else {
            switch currentNetworkStatus {
            case .notConnected:
                result = true
            default: break
            }
        }

        if let responseError = error as? ResponseError {
            // When device is having low connectivity, the core will return this error.
            if responseError.httpCode == nil &&
                responseError.responseCode == nil &&
                responseError.underlyingError?.code == APIErrorCode.deviceHavingLowConnectivity {
                result = true
            }
        }

        return result
    }

    func handleReachabilityChangedNotification(isTimeoutError: Bool, isInternetIssue: Bool) {
        // Show timeout error banner or not reachable banner in mailbox
        if isTimeoutError {
            NotificationCenter.default.post(Notification(name: NSNotification.Name.reachabilityChanged, object: 0, userInfo: nil))
        } else if isInternetIssue {
            NotificationCenter.default.post(Notification(name: NSNotification.Name.reachabilityChanged, object: 1, userInfo: nil))
        }
    }

    func parseStatusCodeIfErrorReceivedFromNetworkResponse(errorUserInfo: [String: Any]) -> Int? {
        if let response = errorUserInfo[Constant.networkResponseErrorKey] as? HTTPURLResponse {
            return response.statusCode
        }
        return nil
    }

    func handleResult(queueTask: QueueManager.Task,
                      error: NSError?,
                      notifyQueueManager: @escaping (QueueManager.Task, QueueManager.TaskResult) -> Void) {
        var taskResult = QueueManager.TaskResult()

        guard let error = error else {
            notifyQueueManager(queueTask, taskResult)
            return
        }

        var statusCode = 200
        let errorCode = error.code
        var isInternetIssue = false
        let errorUserInfo = error.userInfo

        // Check if error returns from the network response. Otherwise, check if it is internet issue
        if let statusCodeFromResponse = parseStatusCodeIfErrorReceivedFromNetworkResponse(errorUserInfo: errorUserInfo) {
            statusCode = statusCodeFromResponse
        } else {
            isInternetIssue = calculateIsInternetIssue(error: error, currentNetworkStatus: InternetConnectionStatusProvider().currentStatus)

            handleReachabilityChangedNotification(isTimeoutError: errorCode == NSURLErrorTimedOut,
                                                  isInternetIssue: isInternetIssue)
        }

        calculateTaskResult(result: &taskResult,
                            isInternetIssue: isInternetIssue,
                            statusCode: statusCode,
                            errorCode: errorCode)
        notifyQueueManager(queueTask, taskResult)
    }

    func calculateTaskResult(result: inout QueueManager.TaskResult, isInternetIssue: Bool, statusCode: Int, errorCode: Int) {
        guard isInternetIssue == false else {
            result.action = .connectionIssue
            return
        }

        switch statusCode {
        case HTTPStatusCode.notFound.rawValue:
            result.action = .removeRelated
        case HTTPStatusCode.internalServerError.rawValue:
            if result.retry < 3 {
                result.action = .retry
                result.retry += 1
            } else {
                result.action = .removeRelated
            }
        case HTTPStatusCode.ok.rawValue where errorCode == APIErrorCode.humanVerificationRequired:
            fallthrough
        case HTTPStatusCode.ok.rawValue where errorCode > 1000:
            result.action = .removeRelated
        case HTTPStatusCode.ok.rawValue where errorCode < 200:
            result.action = .removeRelated
        default:
            if statusCode != .ok {
                result.action = .removeRelated
            } else if errorCode != APIErrorCode.AuthErrorCode.authCacheLocked {
                result.action = .removeRelated
            } else {
                result.action = .checkReadQueue
            }
        }
    }
}
