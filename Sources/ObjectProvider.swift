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
    private let defaultProviderBehaviors: [ProviderBehavior]
    private let defaultCacheBehaviors: [Cache]
    private let providerQueue = DispatchQueue(label: "ProviderQueue", attributes: .concurrent)
    
    public init(networkRequestPerformer: NetworkRequestPerformer, defaultProviderBehaviors: [ProviderBehavior], defaultCacheBehaviors: [Cache]) {
        self.networkRequestPerformer = networkRequestPerformer
        self.defaultProviderBehaviors = defaultProviderBehaviors
        self.defaultCacheBehaviors = defaultCacheBehaviors
    }
    
    public func provide<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], cacheBehaviors: [Cache] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, completion: @escaping (Result<T, Error>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToObjectProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            let cacheBehaviors = self.defaultCacheBehaviors + cacheBehaviors
            
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedObject: T = cacheBehaviors.cachedObject(key: request.persistenceKey) {
                completionQueue.async { completion(.success(cachedObject)) }
                
                providerBehaviors.providerDidProvide(object: cachedObject, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let object = try decoder.decode(T.self, from: data)
                                cacheBehaviors.cacheObject(object, key: request.persistenceKey)
                                completionQueue.async { completion(.success(object)) }
                                
                                providerBehaviors.providerDidProvide(object: object, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingFailed(underlyingError: error))) }
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
    
    public func provideObjects<T: Providable>(request: ProviderRequest, decoder: PersistenceDecoder = JSONDecoder(), providerBehaviors: [ProviderBehavior] = [], cacheBehaviors: [Cache] = [], requestBehaviors: [RequestBehavior] = [], completionQueue: DispatchQueue = .main, completion: @escaping (Result<[T], Error>) -> Void) {
        providerQueue.async { [weak self] in
            guard let self = self else {
                completion(.failure(ProviderError.noStrongReferenceToObjectProvider))
                return
            }
            
            let providerBehaviors = self.defaultProviderBehaviors + providerBehaviors
            let cacheBehaviors = self.defaultCacheBehaviors + cacheBehaviors
            
            providerBehaviors.providerWillProvide(forRequest: request)
            
            if let cachedObjects: [T] = cacheBehaviors.cachedObjects(key: request.persistenceKey), !cachedObjects.isEmpty {
                completionQueue.async { completion(.success(cachedObjects)) }
                
                providerBehaviors.providerDidProvide(object: cachedObjects, forRequest: request)
            } else {
                self.networkRequestPerformer.send(request, requestBehaviors: requestBehaviors) { (result: Result<NetworkResponse, NetworkError>) in
                    switch result {
                    case let .success(response):
                        if let data = response.data {
                            do {
                                let objects = try decoder.decode([T].self, from: data)
                                cacheBehaviors.cacheObjects(objects, key: request.persistenceKey)
                                completionQueue.async { completion(.success(objects)) }
                                
                                providerBehaviors.providerDidProvide(object: objects, forRequest: request)
                            } catch {
                                completionQueue.async { completion(.failure(ProviderError.decodingFailed(underlyingError: error))) }
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
        
        return ObjectProvider(networkRequestPerformer: NetworkController(), defaultProviderBehaviors: [], defaultCacheBehaviors: [persister])
    }
}

extension FileManager {
    public var documentDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .documentDirectory, in: .userDomainMask).first
    }
}

private extension Array where Element == Cache {
    func cachedObject<T: Codable>(key: Key) -> T? {
        for cache in self {
            if let object: T = try? cache.read(forKey: key) {
                return object
            }
        }
        
        return nil
    }
    
    func cachedObjects<T: Codable>(key: Key) -> [T]? {
        let objectIDs: [String]? = cachedObject(key: key)
        
        return objectIDs?.compactMap { cachedObject(key: $0) }
    }
    
    func cacheObject<T: Providable>(_ object: T, key: Key) {
        forEach { try? $0.write(item: object, forKey: key) }
    }
    
    func cacheObjects<T: Providable>(_ objects: [T], key: Key) {
        objects.forEach { object in
            self.forEach {
                try? $0.write(item: object, forKey: object.identifier)
            }
        }
        
        let objectIdentifiers = objects.compactMap { $0.identifier }
        forEach { try? $0.write(item: objectIdentifiers, forKey: key) }
    }
}
