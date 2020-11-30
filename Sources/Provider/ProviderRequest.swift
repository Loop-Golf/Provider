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
    
    /// The key to use for persistence of the item.
    var persistenceKey: Key? { get }
    
    /// A `Bool` that can be set to ignore any locally cached results. By default requests with the `GET` `HTTPMethod` return `false`, otherwise this returns `true`.
    var ignoresCachedContent: Bool { get }
}

extension ProviderRequest {
    
    var ignoresCachedContent: Bool {
        switch httpMethod {
        case .get: return false
        case .patch, .post, .put, .delete: return true
        }
    }
}
