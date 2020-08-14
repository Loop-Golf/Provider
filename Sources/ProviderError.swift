//
//  ProviderError.swift
//  Networker
//
//  Created by Twig on 5/16/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

enum ProviderError: Error {
    case decodingFailed(underlyingError: Error)
    case noStrongReferenceToObjectProvider
}
