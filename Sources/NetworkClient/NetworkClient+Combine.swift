//===----------------------------------------------------------------------===//
//
// This source file is part of the Network Client open source project
//
// Copyright (c) Stairtree GmbH
// Licensed under the MIT license
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import Metrics
#if canImport(Combine)
import Combine

@available(iOS 13.0, macOS 10.15, watchOS 6.0, tvOS 13.0, *)
extension NetworkClient {
    public func load<Request: NetworkRequest>(_ req: Request) -> AnyPublisher<Request.ResponseDataType, Error> {
        do {
            let urlRequest =  try req.makeRequest(baseURL: baseURL)
            let requestTimer = Timer(label: "Request '\(urlRequest.debugString)'")
            let requestStart = DispatchTime.now()
            logger.trace(Logger.Message(stringLiteral: urlRequest.debugString))
            
            // Response handler
            func handleResponse(_ response: Response) throws -> Request.ResponseDataType {
                requestTimer.recordInterval(since: requestStart)
                requestTimer.destroy()
                let decodingTimer = Timer(label: "Decoding '\(urlRequest.debugString)'")
                let decodingStart = DispatchTime.now()
                defer {
                    decodingTimer.recordInterval(since: decodingStart)
                    decodingTimer.destroy()
                }
                switch response {
                case let .success(data): return try req.parseResponse(data)
                case let .failure(status, data): throw try req.parseError(data, for: status)
                case let .error(error): throw APIError.transport(error)
                }
            }
            
            // Send it to the transport
            return Future<Request.ResponseDataType, Error> { completion in
                self.transport.send(request: urlRequest, completion: { response in
                    let result = Result(catching: { try handleResponse(response) })
                    completion(result)
                })
            }
            .eraseToAnyPublisher()
        } catch {
            return Fail<Request.ResponseDataType, Error>(error: error).eraseToAnyPublisher()
        }
    }
}
#endif