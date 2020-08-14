//
//  ProviderBehavior.swift
//  Networker
//
//  Created by Twig on 5/9/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

public protocol ProviderBehavior {
    func providerWillProvide(forRequest request: ProviderRequest)
    func providerDidProvide<T: Codable>(object: T, forRequest request: ProviderRequest)
}

extension ProviderBehavior {
    func providerWillProvide(forRequest request: ProviderRequest) { }
    func providerDidProvide<T: Codable>(object: T, forRequest request: ProviderRequest) { }
}

extension Array: ProviderBehavior where Element == ProviderBehavior {
    public func providerWillProvide(forRequest request: ProviderRequest) {
        forEach { $0.providerWillProvide(forRequest: request) }
    }
    
    public func providerDidProvide<T: Codable>(object: T, forRequest request: ProviderRequest) {
        forEach { $0.providerDidProvide(object: object, forRequest: request) }
    }
}
