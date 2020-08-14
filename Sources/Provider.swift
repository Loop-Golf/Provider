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

public typealias Providable = Codable & Identifiable

public protocol Provider {
    func provide<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], cacheBehaviors: [Cache], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<T, Error>) -> Void)
    
    func provideObjects<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], cacheBehaviors: [Cache], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<[T], Error>) -> Void)
}
