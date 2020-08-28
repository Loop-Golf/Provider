//
//  Provider.swift
//  Networker
//
//  Created by Twig on 5/6/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister

/// Represents the type of an instance that can be retrieved by a `Provider`.
public typealias Providable = Codable & Identifiable

/// Describes a type that can retrieve items from network or persistence, and store in persistence.
public protocol Provider {
    func provide<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<T, ProviderError>) -> Void)
    
    func provideObjects<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<[T], ProviderError>) -> Void)
}
