//
//  ObjectProvider.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation
import Networking
import Persister

public final class ObjectProvider: Provider {
    
    private let networkRequestPerformer: NetworkRequestPerformer
    private let cache: Cache?
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    
    public init(networkRequestPerformer: NetworkRequestPerformer, cache: Cache?, defaultProviderBehaviors: [ProviderBehavior]) {
        self.networkRequestPerformer = networkRequestPerformer
        self.cache = cache
        self.defaultProviderBehaviors = defaultProviderBehaviors
    }
    
    public func provide<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder, providerBehaviors: [ProviderBehavior], requestBehaviors: [RequestBehavior], completionQueue: DispatchQueue, completion: @escaping (Result<T, Error>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToObjectProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            // TODO: handle try/catch
            if let cachedObject: T = try? self.cache?.read(forKey: request.persistenceKey) {
                completionQueue.async { completion(.success(cachedObject)) }
                
                providerBehaviors.providerDidProvide(item: cachedObject, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let object = try decoder.decode(T.self, from: data)
                                try self?.cache?.write(item: object, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(object)) }
                                
                                providerBehaviors.providerDidProvide(item: object, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(NetworkError.noData))}
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(error)) }
                    }
                }
            }
        }
    }
    
    public func provideObjects<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, completion: @escaping (Result<[T], Error>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToObjectProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedObjects: [T] = self.cache?.readItems(forKey: request.persistenceKey), !cachedObjects.isEmpty {
                completionQueue.async { completion(.success(cachedObjects)) }
                
                providerBehaviors.providerDidProvide(item: cachedObjects, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { [weak self] (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let objects = try decoder.decode([T].self, from: data)
                                self?.cache?.writeItems(objects, forKey: request.persistenceKey)
                                completionQueue.async { completion(.success(objects)) }
                                
                                providerBehaviors.providerDidProvide(item: objects, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingError(error))) }
                            }
                        } else {
                            completionQueue.async { completion(.failure(NetworkError.noData)) }
                        }
                    case let .failure(error):
                        completionQueue.async { completion(.failure(error)) }
                    }
                }
            }
        }
    }
}

extension ObjectProvider {
    public static func configuredProvider(withRootPersistenceURL persistenceURL: URL = FileManager.default.documentDirectoryURL, cacheCapacity: CacheCapacity = .limited(numberOfItems: 100)) -> ObjectProvider {
        let diskCache = DiskCache(rootDirectoryURL: persistenceURL)
        let persister = Persister(memoryCache: MemoryCache(capacity: cacheCapacity), diskCache: diskCache)
        
        return ObjectProvider(networkRequestPerformer: NetworkController(), cache: persister, defaultProviderBehaviors: [])
    }
}

extension FileManager {
    public var documentDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .documentDirectory, in: .userDomainMask).first
    }
}

private extension Cache {
    // TODO: make throw
    func readItems<T: Codable>(forKey key: Key) -> [T]? {
        let objectIDs: [String]? = try? read(forKey: key)
        
        return objectIDs?.compactMap { try? read(forKey: $0) }
    }
    
    func writeItems<T: Providable>(_ items: [T], forKey key: Key) {
        items.forEach { item in
            try? write(item: item, forKey: item.identifier)
        }
        
        let itemIdentifiers = items.compactMap { $0.identifier }
        try? write(item: itemIdentifiers, forKey: key)
    }
}
