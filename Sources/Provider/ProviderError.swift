//
//  ProviderError.swift
//  Networker
//
//  Created by Twig on 5/16/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

/// A list of possible errors encountered while attempting to provide items.
enum ProviderError: Error {
    
    /// An underlying decoding error occurred.
    /// - Parameter error: The error that occurred while decoding.
    case decodingError(_ error: Error)
    
    /// There was no strong reference kept to the `ObjectProvider`.
    case noStrongReferenceToObjectProvider
}
