//
//  ProviderError.swift
//  Networker
//
//  Created by Twig on 5/16/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Networking
import Persister

/// Possible errors encountered while attempting to provide items.
public enum ProviderError: Error {
    
    /// A struct that represents a failure when retrieving an individual item during a request for multiple items.
    public struct PartialRetrievalFailure {
        
        /// They key for the item that failed to be retrieved.
        let key: String
        
        /// The error that occurred when attempting to retrieve the item from persistence.
        let persistenceError: PersistenceError
    }

    /// An underlying networking error occurred.
    /// - Parameter error: The error that occurred with the network request.
    case networkError(_ error: NetworkError)
    
    /// An underlying persistence error occurred.
    /// - Parameter error: The error that occurred while performing cache read/write operations.
    case persistenceError(_ error: PersistenceError)
    
    /// An underlying decoding error occurred.
    /// - Parameter error: The error that occurred while decoding.
    case decodingError(_ error: Error)
    
    /// There was no strong reference kept to the `Provider`.
    case noStrongReferenceToProvider
    
    /// A request to retrieve multiple items ended in failure. This error provides a partial response in the event that we were able to retrieve some of the requested items from the cache.
    /// - Parameters:
    ///   - retrievedItems: A list of items that were able to be retrieved, that represent a partial list of the requested items.
    ///   - persistenceFailures: The errors that occurred while attempting to retrieve items from persistence.
    ///   - networkError: The error that occurred with the network request.
    case partialRetrieval(retrievedItems: [Providable], persistenceFailures: [PartialRetrievalFailure], networkError: NetworkError)
}
