//
//  ItemProvider.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Combine
import Networking
import Persister

/// Retrieves items from persistence or networking and stores them in persistence.
public final class ItemProvider {
    
    private typealias CacheItemsResponse<T: Providable> = (itemContainers: [ItemContainer<T>], partialErrors: [ProviderError.PartialRetrievalPersistenceError])
    
    /// Performs network requests when items cannot be retrieved from persistence.
    public let networkRequestPerformer: NetworkRequestPerformer
    
    /// The cache used to persist / recall previously retrieved items.
    public let cache: Cache?
    
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    
    /// Creates a new `ItemProvider`.
    /// - Parameters:
    ///   - networkRequestPerformer: Performs network requests when items cannot be retrieved from persistence.
    ///   - cache: The cache used to persist / recall previously retrieved items.
    ///   - defaultProviderBehaviors: Actions to perform before _every_ provider request is performed and / or after _every_ provider request is completed.
    public init(networkRequestPerformer: NetworkRequestPerformer, cache: Cache?, defaultProviderBehaviors: [ProviderBehavior] = []) {
        self.networkRequestPerformer = networkRequestPerformer
        self.cache = cache
        self.defaultProviderBehaviors = defaultProviderBehaviors
    }
}

extension ItemProvider: Provider {
    
    // MARK: - Provider
    
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, expiredItemCompletion: ((Result<Item, Never>) -> Void)? = nil, completion: @escaping (Result<Item, ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completionQueue.async { completion(.failure(ProviderError.noStrongReferenceToProvider)) }
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedContainer: ItemContainer<Item> = try? self.cache?.read(forKey: request.persistenceKey) {
                if cachedContainer.expirationDate < Date() {
                    if let expiredCompletion = expiredItemCompletion {
                        completionQueue.async { expiredCompletion(.success(cachedContainer.item)) }
                        providerBehaviors.providerDidProvide(item: cachedContainer.item, forRequest: request)
                    }
                } else {
                    completionQueue.async { completion(.success(cachedContainer.item)) }
                    providerBehaviors.providerDidProvide(item: cachedContainer.item, forRequest: request)
                    return
                }
            }
            
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
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, expiredItemsCompletion: ((Result<[Item], Never>) -> Void)? = nil, completion: @escaping (Result<[Item], ProviderError>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completionQueue.async { completion(.failure(ProviderError.noStrongReferenceToProvider)) }
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            let cacheResponse: CacheItemsResponse<Item>? = try? self.cache?.readItems(forKey: request.persistenceKey)
            
            if let cacheResponse = cacheResponse, !cacheResponse.itemContainers.isEmpty {
                let cachedItems = cacheResponse.itemContainers
                
                let items = cachedItems.map { $0.item }
                let isExpired = cachedItems.contains { $0.expirationDate < Date() }

                if isExpired {
                    if let expiredCompletion = expiredItemsCompletion, cacheResponse.partialErrors.isEmpty {
                        completionQueue.async { expiredCompletion(.success(items)) }
                        providerBehaviors.providerDidProvide(item: items, forRequest: request)
                    }
                } else if cacheResponse.partialErrors.isEmpty {
                    completionQueue.async { completion(.success(items)) }
                    providerBehaviors.providerDidProvide(item: items, forRequest: request)
                    
                    return
                }
            }
            
            func networkRequestFailed(error: NetworkError) {
                let allowsExpiredResponse = expiredItemsCompletion != nil
                let itemsAreExpired = cacheResponse?.itemContainers.first?.expirationDate < Date()
                
                if let cacheResponse = cacheResponse, !cacheResponse.itemContainers.isEmpty {
                    if !itemsAreExpired || (itemsAreExpired && allowsExpiredResponse) {
                        completion(.failure(.partialRetrieval(retrievedItems: cacheResponse.itemContainers.map { $0.item }, persistenceErrors: cacheResponse.partialErrors, networkError: error)))
                    } else {
                        completion(.failure(.networkError(error)))
                    }
                } else {
                    completion(.failure(.networkError(error)))
                }
            }
            
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
                            completionQueue.async { networkRequestFailed(error: .decodingError(error)) }
                        }
                    } else {
                        completionQueue.async { networkRequestFailed(error: .noData) }
                    }
                case let .failure(error):
                    completionQueue.async { networkRequestFailed(error: error) }
                }
            }
        }
    }
        
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItem: Bool = false) -> AnyPublisher<Item, ProviderError> {
        
        let cachePublisher = Just<ItemContainer<Item>?>(try? self.cache?.read(forKey: request.persistenceKey))
            .setFailureType(to: ProviderError.self)
        
        let networkPublisher = networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
            .mapError { ProviderError.networkError($0) }
            .tryCompactMap { $0.data }
            .mapError { _ in ProviderError.networkError(.noData) }
            .tryMap { try decoder.decode(Item.self, from: $0) }
            .mapError { ProviderError.decodingError($0) }
            .handleEvents(receiveOutput: { [weak self] item in
                try? self?.cache?.write(item: item, forKey: request.persistenceKey)
            })
            .eraseToAnyPublisher()
        
        let providerPublisher = cachePublisher
            .flatMap { item -> AnyPublisher<Item, ProviderError> in
                if let item = item {
                    let itemPublisher = Just(item)
                        .map { $0.item }
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                                        
                    if let expiration = item.expirationDate, expiration >= Date() {
                        return itemPublisher
                    } else if allowExpiredItem, let expiration = item.expirationDate, expiration < Date() {
                        return itemPublisher.merge(with: networkPublisher).eraseToAnyPublisher()
                    } else {
                        return networkPublisher
                    }
                } else {
                    return networkPublisher
                }
            }
        
        return providerPublisher
                .handleEvents(receiveSubscription: { _ in
                    providerBehaviors.providerWillProvide(forRequest: request)
                }, receiveOutput: { item in
                    providerBehaviors.providerDidProvide(item: item, forRequest: request)
                })
                .subscribe(on: providerQueue)
                .eraseToAnyPublisher()
    }
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItems: Bool = false) -> AnyPublisher<[Item], ProviderError> {
        
        let cachePublisher = Just<CacheItemsResponse<Item>?>(try? self.cache?.readItems(forKey: request.persistenceKey))
            .setFailureType(to: ProviderError.self)

        let networkPublisher = networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
            .mapError { ProviderError.networkError($0) }
            .tryCompactMap { $0.data }
            .mapError { _ in ProviderError.networkError(.noData) }
            .tryMap { try decoder.decode([Item].self, from: $0) }
            .mapError { ProviderError.decodingError($0) }
            .handleEvents(receiveOutput: { [weak self] items in
                self?.cache?.writeItems(items, forKey: request.persistenceKey)
            })
            .print()
            .eraseToAnyPublisher()
        
        let providerPublisher = cachePublisher
            .flatMap { response -> AnyPublisher<[Item], ProviderError> in
                if let response = response {
                    let itemContainers = response.itemContainers
                    
                    let itemPublisher = Just(itemContainers.map { $0.item })
                        .setFailureType(to: ProviderError.self)
                        .eraseToAnyPublisher()
                    
                    if !response.partialErrors.isEmpty {
                        return networkPublisher
                            .mapError { networkError in
                                let itemsAreExpired = response.itemContainers.first?.expirationDate < Date()
                                
                                if !itemsAreExpired || (itemsAreExpired && allowExpiredItems) {
                                    return ProviderError.partialRetrieval(retrievedItems: response.itemContainers.map { $0.item }, persistenceErrors: response.partialErrors, networkError: .underlyingNetworkingError(networkError))
                                } else {
                                    return networkError
                                }
                            }
                            .eraseToAnyPublisher()
                    } else if let expiration = itemContainers.first?.expirationDate, expiration >= Date() {
                        return itemPublisher
                    } else if allowExpiredItems, let expiration = itemContainers.first?.expirationDate, expiration < Date() {
                        return itemPublisher.merge(with: networkPublisher).eraseToAnyPublisher()
                    } else {
                        return networkPublisher
                    }
                } else {
                    return networkPublisher
                }
        }
        
        return providerPublisher
                .handleEvents(receiveSubscription: { _ in
                    providerBehaviors.providerWillProvide(forRequest: request)
                }, receiveOutput: { item in
                    providerBehaviors.providerDidProvide(item: item, forRequest: request)
                })
                .subscribe(on: providerQueue)
                .eraseToAnyPublisher()
    }
}

extension ItemProvider {
    
    /// Creates an `ItemProvider` configured with a `Persister` (memory and disk cache) and `NetworkController`.
    /// - Parameters:
    ///   - persistenceURL: The location on disk in which items are persisted. Defaults to the Application Support directory.
    ///   - memoryCacheCapacity: The capacity of the LRU memory cache. Defaults to a limited capacity of 100 items.
    public static func configuredProvider(withRootPersistenceURL persistenceURL: URL = FileManager.default.applicationSupportDirectoryURL, memoryCacheCapacity: CacheCapacity = .limited(numberOfItems: 100)) -> ItemProvider {
        let memoryCache = MemoryCache(capacity: memoryCacheCapacity)
        let diskCache = DiskCache(rootDirectoryURL: persistenceURL)
        let persister = Persister(memoryCache: memoryCache, diskCache: diskCache)
        
        return ItemProvider(networkRequestPerformer: NetworkController(), cache: persister, defaultProviderBehaviors: [])
    }
}

extension FileManager {
    public var applicationSupportDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }
}

private func <(lhs: Date?, rhs: Date) -> Bool {
    if let lhs = lhs {
        return lhs < rhs
    }
    
    return false
}

private extension Cache {
    func readItems<Item: Codable>(forKey key: Key) throws -> ([ItemContainer<Item>], [ProviderError.PartialRetrievalPersistenceError]) {
        guard let itemIDsContainer: ItemContainer<[String]> = try read(forKey: key) else {
            throw PersistenceError.noValidDataForKey
        }
        
        var failedItemErrors: [ProviderError.PartialRetrievalPersistenceError] = []
        let validItems: [ItemContainer<Item>] = itemIDsContainer.item.compactMap {
            let fallbackError = ProviderError.PartialRetrievalPersistenceError(key: $0, persistenceError: .noValidDataForKey)

            do {
                if let container: ItemContainer<Item> = try read(forKey: $0) {
                    return container
                }
                
                failedItemErrors.append(fallbackError)
                return nil
            } catch {
                if let persistenceError = error as? PersistenceError {
                    let retrievalError = ProviderError.PartialRetrievalPersistenceError(key: $0, persistenceError: persistenceError)

                    failedItemErrors.append(retrievalError)
                } else {
                    failedItemErrors.append(fallbackError)
                }
                
                return nil
            }
        }
        
        return (validItems, failedItemErrors)
    }
    
    func writeItems<Item: Providable>(_ items: [Item], forKey key: Key) {
        items.forEach { item in
            try? write(item: item, forKey: item.identifier)
        }
        
        let itemIdentifiers = items.compactMap { $0.identifier }
        try? write(item: itemIdentifiers, forKey: key)
    }
}
