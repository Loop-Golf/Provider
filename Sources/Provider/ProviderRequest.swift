//
//  ProviderRequest.swift
//  Networker
//
//  Created by Twig on 5/8/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Networking

/// A protocol that defines the parameters that make up a item providing request.
public protocol ProviderRequest: NetworkRequest {
    
    /// The key to use for persistence of the item.
    var persistenceKey: Key { get }
}
