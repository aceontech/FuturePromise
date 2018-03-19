//
//  Licensed under Apache License v2.0
//
//  See LICENSE.txt for license information
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

extension DispatchQueue {

    /// Creates and returns a new `Promise` that will be notified using this `DispatchQueue` as execution `Thread`.
    public func newPromise<T>(file: StaticString = #file, line: UInt = #line) -> Promise<T> {
        return Promise<T>(queue: self, file: file, line: line)
    }
}
