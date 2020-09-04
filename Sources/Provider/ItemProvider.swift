//
//  ItemProvider.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister

public final class ItemProvider: Provider {
    
    private let networkRequestPerformer: NetworkRequestPerformer
    private let cache: Cache?
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    
    public init(networkRequestPerformer: NetworkRequestPerformer, cache: Cache?, defaultProviderBehaviors: [ProviderBehavior]) {
        self.networkRequestPerformer = networkRequestPerformer
        self.cache = cache
        self.defaultProviderBehaviors = defaultProviderBehaviors
    }
    
    public func provide<Item: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<Item, ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedItem: Item = try? self.cache?.read(forKey: request.persistenceKey) {
                completionQueue.async { completion(.success(cachedItem)) }
                
                providerBehaviors.providerDidProvide(item: cachedItem, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let item = try decoder.decode(Item.self, from: data)
                                try self?.cache?.write(item: item, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(item)) }
                                
                                providerBehaviors.providerDidProvide(item: item, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(.networkError(.noData)))}
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(.networkError(error))) }
                    }
                }
            }
        }
    }
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: PersistenceDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, completion: @escaping (Result<[Item], ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedItems: [Item] = self.cache?.readItems(forKey: request.persistenceKey), !cachedItems.isEmpty {
                completionQueue.async { completion(.success(cachedItems)) }
                
                providerBehaviors.providerDidProvide(item: cachedItems, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let items = try decoder.decode([Item].self, from: data)
                                self?.cache?.writeItems(items, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(items)) }
                                
                                providerBehaviors.providerDidProvide(item: items, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(.networkError(.noData))) }
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(.networkError(error))) }
                    }
                }
            }
        }
    }
}

extension ItemProvider {
    public static func configuredProvider(withRootPersistenceURL persistenceURL: URL = FileManager.default.documentDirectoryURL, cacheCapacity: CacheCapacity = .limited(numberOfItems: 100)) -> ItemProvider {
        let diskCache = DiskCache(rootDirectoryURL: persistenceURL)
        let persister = Persister(memoryCache: MemoryCache(capacity: cacheCapacity), diskCache: diskCache)
        
        return ItemProvider(networkRequestPerformer: NetworkController(), cache: persister, defaultProviderBehaviors: [])
    }
}

extension FileManager {
    public var documentDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .documentDirectory, in: .userDomainMask).first
    }
}

private extension Cache {
    func readItems<Item: Codable>(forKey key: Key) -> [Item]? {
        let itemIDs: [String]? = try? read(forKey: key)
        
        return itemIDs?.compactMap { try? read(forKey: $0) }
    }
    
    func writeItems<Item: Providable>(_ items: [Item], forKey key: Key) {
        items.forEach { item in
            try? write(item: item, forKey: item.identifier)
        }
        
        let itemIdentifiers = items.compactMap { $0.identifier }
        try? write(item: itemIdentifiers, forKey: key)
    }
}
