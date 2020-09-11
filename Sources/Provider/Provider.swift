//
//  Provider.swift
//  Networker
//
//  Created by Twig on 5/6/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Combine
import Networking
import Persister

/// Represents the type of an instance that can be retrieved by a `Provider`.
public typealias Providable = Codable & Identifiable

/// Describes a type that can retrieve items from persistence or networking and store them in persistence.
public protocol Provider {
    
    /// Attempts to retrieve an item using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the item will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the item from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the item wasn’t successfully retrieved from persistence.
    ///   - completionQueue: The queue on which to call the completion handler.
    ///   - completion: The closure called upon completing the request that provides the desired item or the error that occurred when attempting to retrieve it.
    func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<Item, ProviderError>) -> Void)
    
    /// Attempts to retrieve an array of items using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the items will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    ///   - completionQueue: The queue on which to call the completion handler.
    ///   - completion: The closure called upon completing the request that provides the desired items or the error that occurred when attempting to retrieve them.
    func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<[Item], ProviderError>) -> Void)
    
    /// Produces a publisher which, when subscribed to, attempts to retrieve an item using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the item will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior]) -> AnyPublisher<Item, ProviderError>
    
    /// Produces a publisher which, when subscribed to, attempts to retrieve an array of items using the provided request, checking persistence first where possible and falling back to the network. If the network is used, the items will be persisted upon success.
    /// - Parameters:
    ///   - request: The request that provides the details needed to retrieve the items from persistence or networking.
    ///   - decoder: The decoder used to convert network response data into an array of the type specified by the generic placeholder.
    ///   - providerBehaviors: Actions to perform before the provider request is performed and / or after the provider request is completed.
    ///   - requestBehaviors: Actions to perform before the network request is performed and / or after the network request is completed. Only called if the items weren’t successfully retrieved from persistence.
    func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior]) -> AnyPublisher<[Item], ProviderError>
}
