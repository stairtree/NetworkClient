//===----------------------------------------------------------------------===//
//
// This source file is part of the StructuredAPIClient open source project
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

// Handle token auth and add appropriate auth headers to an existing transport.
public final class TokenAuthenticationHandler: Transport {
    public let next: Transport?
    private let logger: Logger
    private let auth: AuthState

    public init(base: Transport, accessToken: Token? = nil, refreshToken: Token? = nil, tokenProvider: TokenProvider, logger: Logger? = nil) {
        self.next = base
        self.logger = logger ?? Logger(label: "TokenAuth")
        self.auth = AuthState(accessToken: accessToken, refreshToken: refreshToken, provider: tokenProvider, logger: logger)
    }

    public func send(request: URLRequest, completion: @escaping (Result<TransportResponse, Error>) -> Void) {
        self.auth.token { result in
            switch result {
            case let .failure(error):
                completion(.failure(TransportFailure.unknown(error)))
            case let .success(token):
                let headers = ["Authorization": "Bearer \(token)"]
                let transport = AddHTTPHeadersHandler(base: self.next!, headers: headers)
                
                transport.send(request: request, completion: completion)
            }
        }
    }
}

public protocol TokenProvider {
    // Get access token and refresh token
    func fetchToken(completion: @escaping (Result<(Token, Token), Error>) -> Void)

    // Refreh the current token
    func refreshToken(withRefreshToken refreshToken: Token, completion: @escaping (Result<Token, Error>) -> Void)
}

public protocol Token {
    var raw: String { get }
    var expiresAt: Date? { get }
}

final class AuthState {
    var accessToken: Token? = nil
    var refreshToken: Token? = nil

    let provider: TokenProvider
    let logger: Logger

    internal init(accessToken: Token? = nil, refreshToken: Token? = nil, provider: TokenProvider, logger: Logger? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.provider = provider
        self.logger = logger ?? Logger(label: "AuthState")
    }

    func token(_ completion: @escaping (Result<String, Error>) -> Void) {
        if let access = self.accessToken, (access.expiresAt ?? Date.distantFuture) > Date() {
            return completion(.success(access.raw))
        } else if let refresh = self.refreshToken, (refresh.expiresAt ?? Date.distantFuture) > Date() {
            logger.trace("Refreshing token")
            self.provider.refreshToken(withRefreshToken: refresh, completion: { result in
                switch result {
                case let .failure(error):
                    return completion(.failure(error))
                case let .success(access):
                    self.accessToken = access
                    return completion(.success(access.raw))
                }
            })
        } else {
            logger.trace("Fetching initial tokens")
            self.provider.fetchToken(completion: { result in
                switch result {
                case let .failure(error):
                    return completion(.failure(error))
                case let .success((access, refresh)):
                    self.accessToken = access
                    self.refreshToken = refresh
                    return completion(.success(access.raw))
                }
            })
        }
    }
}
