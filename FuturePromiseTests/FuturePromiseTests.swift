//
//  Licensed under Apache License v2.0
//
//  See LICENSE.txt for license information
//  SPDX-License-Identifier: Apache-2.0
//
//  Copyright © 2018 Jarroo.
//

import XCTest
import FuturePromise

private func delayedOperation(of delay: Int) -> Future<Bool> {
    let queue = DispatchQueue.main
    let promise: Promise<Bool> = queue.newPromise()
    queue.asyncAfter(deadline: .now() + .seconds(delay)) {
        promise.succeed(result: true)
    }
    return promise.futureResult
}

class FuturePromiseTests: XCTestCase {
    
    func testExample() {
        let exp1 = expectation(description: "Expectation 1")
        let exp2 = expectation(description: "Expectation 2")
        let expDone = expectation(description: "Expectation 1")

        delayedOperation(of: 1).then { (Bool) -> Future<Bool> in
            exp1.fulfill()
            return delayedOperation(of: 2)
        }.then { (Bool) -> Future<Bool> in
            exp2.fulfill()
            return delayedOperation(of: 3)
        }.whenComplete {
            expDone.fulfill()
        }
        waitForExpectations(timeout: 30)
    }
}
