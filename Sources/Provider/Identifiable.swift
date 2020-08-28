//
//  Identifiable.swift
//  Networker
//
//  Created by Twig on 5/10/19.
//  Copyright © 2019 Lickability. All rights reserved.
//

import Foundation

public typealias Key = String

public protocol Identifiable {
    var identifier: Key { get }
}
