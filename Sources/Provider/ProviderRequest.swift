//
//  ProviderRequest.swift
//  Networker
//
//  Created by Twig on 5/8/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Networking

/// Describes a type that defines the parameters that make up an item providing request.
public protocol ProviderRequest: NetworkRequest {
    
    /// The key to use for persistence of the request’s response.
    /// * For single item requests, it’ll be common for the `persistenceKey` to match the provided item’s `identifier`.
    /// * For multiple item requests, the `persistenceKey` represents the collection of items returned as a whole.
    /// - Note: If `persistenceKey` is `nil`, `Provider` will not check the cache for item(s), and will not store the provided item(s) in the cache.
    var persistenceKey: Key? { get }
}
