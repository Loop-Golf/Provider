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
}
