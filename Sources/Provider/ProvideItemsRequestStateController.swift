//
//  ProvideItemsRequestStateController.swift
//  Provider
//
//  Created by Twig on 8/30/22.
//  Copyright © 2022 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister
import Combine

/// A class responsible for representing the state and value of a provider items request being made.
public final class ProvideItemsRequestStateController<Item: Providable> {
    
    /// The state of a provider request's lifecycle.
    public enum ProvideItemsRequestState {
        
        /// A request that has not yet been started.
        case notInProgress
        
        /// A request that has been started, but not completed.
        case inProgress
                
        /// A request that has been completed with an associated result.
        case completed(Result<[Item], ProviderError>)
        
        /// A `Bool` representing if a request is in progress.
        public var isInProgress: Bool {
            switch self {
            case .notInProgress, .completed:
                return false
            case .inProgress:
                return true
            }
        }
        
        /// The completed `LocalizedError`, if one exists.
        public var completedError: LocalizedError? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result):
                switch result {
                case .success:
                    return nil
                case let .failure(error):
                    switch error {
                    case let .networkError(networkError):
                        return networkError
                    default:
                        return error
                    }
                }
            }
        }
                
        /// A list of `Item`s for the completed request `Item` if they exist.
        public var completedItems: [Item]? {
            switch self {
            case .notInProgress, .inProgress:
                return nil
            case let .completed(result):
                switch result {
                case let .success(response):
                    return response
                case .failure:
                    return nil
                }
            }
        }
        
        /// A `Bool` indicating if the request has finished successfully.
        public var didFinishSuccessfully: Bool {
            return completedItems != nil
        }
        
        /// A `Bool` indicating if the request has finished with an error.
        public var didFinishUnsuccessfully: Bool {
            return completedError != nil
        }
    }
    
    /// A `Publisher` that can be subscribed to in order to receive updates about the status of a request.
    public private(set) lazy var publisher: AnyPublisher<ProvideItemsRequestState, Never> = {
        return providerStatePublisher.prepend(.notInProgress).eraseToAnyPublisher()
    }()
    
    private let provider: Provider
    private let providerStatePublisher = PassthroughSubject<ProvideItemsRequestState, Never>()
    private var cancellables = Set<AnyCancellable>()
    
    /// Initializes the `ProvideItemsRequestStateController` with the specified parameters.
    /// - Parameter provider: The `Provider` used to provide a response from.
    public init(provider: Provider) {
        self.provider = provider
    }
    
    /// Sends a request with the specified parameters to provide back a list of items.
    /// - Parameters:
    ///   - request: The request to send.
    ///   - decoder: The decoder to use to decode a successful response.
    ///   - providerBehaviors: Additional `ProviderBehavior`s to use.
    ///   - requestBehaviors: Additional `RequestBehavior`s to append to the request.
    ///   - allowExpiredItem: A `Bool` indicating if the provider should be allowed to return an expired item.
    public func provideItems(request: ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItems: Bool = false) {
        providerStatePublisher.send(.inProgress)

        provider.provideItems(request: request, decoder: decoder, providerBehaviors: providerBehaviors, requestBehaviors: requestBehaviors, allowExpiredItems: allowExpiredItems)
            .mapToResult()
            .receive(on: DispatchQueue.main)
            .sink { [providerStatePublisher] result in
                providerStatePublisher.send(.completed(result))
            }
            .store(in: &cancellables)
    }
    
    /// Resets the state of the `providerStatePublisher` and cancels any in flight requests that may be ongoing. Cancellation is not guaranteed, and requests that are near completion may end up finishing, despite being cancelled.
    public func resetState() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()

        providerStatePublisher.send(.notInProgress)
    }
}
