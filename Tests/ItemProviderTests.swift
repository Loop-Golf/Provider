//
//  ItemProviderTests.swift
//  ProviderTests
//
//  Created by Michael Liberatore on 8/14/20.
//  Copyright © 2020 Lickability. All rights reserved.
//

import Combine
import XCTest
import OHHTTPStubs
import OHHTTPStubsSwift

@testable import Provider

class ItemProviderTests: XCTestCase {
    
    private let provider = ItemProvider.configuredProvider(withRootPersistenceURL: FileManager.default.cachesDirectoryURL, memoryCacheCapacity: .unlimited)
    private var cancellables = Set<AnyCancellable>()
    
    override func tearDown() {
        HTTPStubs.removeAllStubs()
        try? provider.cache?.removeAll()
        
        super.tearDown()
    }

    func testProvideItem() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Item.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success: break
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Item.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
                }
                
                self.provider.provide(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<TestItem, ProviderError>) in
                    switch result {
                    case .success:
                        break
                    case let .failure(error):
                        XCTFail("There should be no error: \(error)")
                    }
                    
                    expectation.fulfill()
                }
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<TestItem, ProviderError>) in
            switch result {
            case .success:
                XCTFail("There should be an error.")
                expectation.fulfill()
            case .failure:
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItems() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The items will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Items.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case let .success(items):
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsReturnsCachedResult() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        let originalStub = stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Items.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case .success:
                HTTPStubs.removeStub(originalStub)
                
                stub(condition: { _ in true }) { _ in
                    fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
                }
                
                self.provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<[TestItem], ProviderError>) in
                    switch result {
                    case let .success(items):
                        XCTAssertEqual(items.count, 3)
                    case let .failure(error):
                        XCTFail("There should be no error: \(error)")
                    }
                    
                    expectation.fulfill()
                }
            case let .failure(error):
                XCTFail("There should be no error: \(error)")
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [], completionQueue: .main) { (result: Result<[TestItem], ProviderError>) in
            switch result {
            case .success:
                XCTFail("There should be an error.")
                expectation.fulfill()
            case .failure:
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemPublisher() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Item.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request, providerBehaviors: [], requestBehaviors: [])
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { (item: TestItem) in
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemPublisherFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        expectation.assertForOverFulfill = false
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItem.json", type(of: self))!, headers: nil)
        }
        
        provider.provide(request: request, providerBehaviors: [], requestBehaviors: [])
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { (item: TestItem) in
                XCTFail("There should be no item.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisher() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("Items.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [])
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in }, receiveValue: { (items: [TestItem]) in
                XCTAssertEqual(items.count, 3)
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
    
    func testProvideItemsPublisherFailure() {
        let request = TestProviderRequest()
        
        let expectation = self.expectation(description: "The item will exist.")
        
        stub(condition: { _ in true }) { _ in
            fixture(filePath: OHPathForFile("InvalidItems.json", type(of: self))!, headers: nil)
        }
        
        provider.provideItems(request: request, providerBehaviors: [], requestBehaviors: [])
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
            .sink(receiveCompletion: { _ in expectation.fulfill() }, receiveValue: { (items: [TestItem]) in
                XCTFail("There should be no items.")
                expectation.fulfill()
            })
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 2)
    }
}

struct TestProviderRequest: ProviderRequest {
    
    let persistenceKey: Key
    var baseURL: URL { URL(string: "https://www.google.com")! }
    var path: String { "" }

    init(key: Key = "TestExample") {
        self.persistenceKey = key
    }
}

struct TestItem: Providable {
    var identifier: Key { return title }
    
    let title: String
}

extension FileManager {
    
    fileprivate var cachesDirectoryURL: URL! { //swiftlint:disable:this implicitly_unwrapped_optional
        return urls(for: .cachesDirectory, in: .userDomainMask).first
    }
}
