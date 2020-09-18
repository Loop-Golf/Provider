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
    
    private typealias CacheItemsResponse<T: Providable> = (itemContainers: [ItemContainer<T>], partialErrors: [ProviderError.PartialRetrievalFailure])
    
    /// Performs network requests when items cannot be retrieved from persistence.
    public let networkRequestPerformer: NetworkRequestPerformer
    
    /// The cache used to persist / recall previously retrieved items.
    public let cache: Cache?
    
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    private var cancellables = Set<AnyCancellable?>()
    
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
    
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, allowExpiredItem: Bool = false, itemHandler: @escaping (Result<Item, ProviderError>) -> Void) {
        
        var cancellable: AnyCancellable?
        cancellable = provide(request: request,
                     decoder: decoder,
                     providerBehaviors: providerBehaviors,
                     requestBehaviors: requestBehaviors,
                     allowExpiredItem: allowExpiredItem)
            .receive(on: completionQueue)
            .sink(receiveCompletion: { [weak self] result in
                switch result {
                case let .failure(error):
                    itemHandler(.failure(error))
                case .finished:
                    self?.cancellables.remove(cancellable)
                }
            }, receiveValue: { (item: Item) in
                itemHandler(.success(item))
            })
        
        completionQueue.async { self.cancellables.insert(cancellable) }
    }
    
    public func provideItems<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, allowExpiredItems: Bool = false, itemsHandler: @escaping (Result<[Item], ProviderError>) -> Void) {
        
        var cancellable: AnyCancellable?
        cancellable = provideItems(request: request,
                     decoder: decoder,
                     providerBehaviors: providerBehaviors,
                     requestBehaviors: requestBehaviors,
                     allowExpiredItems: allowExpiredItems)
            .receive(on: completionQueue)
            .sink(receiveCompletion: { [weak self] result in
                switch result {
                case let .failure(error):
                    itemsHandler(.failure(error))
                case .finished:
                    self?.cancellables.remove(cancellable)
                }
            }, receiveValue: { (items: [Item]) in
                itemsHandler(.success(items))
            })
        
        completionQueue.async { self.cancellables.insert(cancellable) }
    }
        
    public func provide<Item: Providable>(request: ProviderRequest, decoder: ItemDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], allowExpiredItem: Bool = false) -> AnyPublisher<Item, ProviderError> {
        
        let cachePublisher: Result<ItemContainer<Item>?, ProviderError>.Publisher
        
        if let persistenceKey = request.persistenceKey {
            cachePublisher = Just<ItemContainer<Item>?>(try? self.cache?.read(forKey: persistenceKey))
                .setFailureType(to: ProviderError.self)
        } else {
            cachePublisher = Just<ItemContainer<Item>?>(nil)
                .setFailureType(to: ProviderError.self)
        }
        
        let networkPublisher = networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
            .mapError { ProviderError.networkError($0) }
            .tryCompactMap { $0.data }
            .mapError { _ in ProviderError.networkError(.noData) }
            .tryMap { try decoder.decode(Item.self, from: $0) }
            .mapError { ProviderError.decodingError($0) }
            .handleEvents(receiveOutput: { [weak self] item in
                if let persistenceKey = request.persistenceKey {
                    try? self?.cache?.write(item: item, forKey: persistenceKey)
                }
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
        
        let cachePublisher: Result<CacheItemsResponse<Item>?, ProviderError>.Publisher
        
        if let persistenceKey = request.persistenceKey {
            cachePublisher = Just<CacheItemsResponse<Item>?>(try? self.cache?.readItems(forKey: persistenceKey))
                .setFailureType(to: ProviderError.self)
        } else {
            cachePublisher = Just<CacheItemsResponse<Item>?>(nil)
                .setFailureType(to: ProviderError.self)
        }

        let networkPublisher = networkRequestPerformer.send(request, requestBehaviors: requestBehaviors)
            .mapError { ProviderError.networkError($0) }
            .tryCompactMap { $0.data }
            .mapError { _ in ProviderError.networkError(.noData) }
            .tryMap { try decoder.decode([Item].self, from: $0) }
            .mapError { ProviderError.decodingError($0) }
            .handleEvents(receiveOutput: { [weak self] items in
                if let persistenceKey = request.persistenceKey {
                    self?.cache?.writeItems(items, forKey: persistenceKey)
                }
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
                                    return ProviderError.partialRetrieval(retrievedItems: response.itemContainers.map { $0.item }, persistenceFailures: response.partialErrors, networkError: .underlyingNetworkingError(networkError))
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
    func readItems<Item: Codable>(forKey key: Key) throws -> ([ItemContainer<Item>], [ProviderError.PartialRetrievalFailure]) {
        guard let itemIDsContainer: ItemContainer<[String]> = try read(forKey: key) else {
            throw PersistenceError.noValidDataForKey
        }
        
        var failedItemErrors: [ProviderError.PartialRetrievalFailure] = []
        let validItems: [ItemContainer<Item>] = itemIDsContainer.item.compactMap {
            let fallbackError = ProviderError.PartialRetrievalFailure(key: $0, persistenceError: .noValidDataForKey)

            do {
                if let container: ItemContainer<Item> = try read(forKey: $0) {
                    return container
                }
                
                failedItemErrors.append(fallbackError)
                return nil
            } catch {
                if let persistenceError = error as? PersistenceError {
                    let retrievalError = ProviderError.PartialRetrievalFailure(key: $0, persistenceError: persistenceError)

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
