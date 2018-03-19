//
//  Licensed under Apache License v2.0
//
//  See LICENSE.txt for license information
//  SPDX-License-Identifier: Apache-2.0
//

import Foundation

extension DispatchQueue {
    
    /// Creates and returns a new `Future` that is already marked as failed. Notifications will be done using this `DispatchQueue` as execution `Thread`.
    ///
    /// - parameters:
    ///     - error: the `Error` that is used by the `Future`.
    /// - returns: a failed `Future`.
    public func newFailedFuture<T>(error: Error) -> Future<T> {
        return Future<T>(queue: self, error: error, file: "n/a", line: 0)
    }

    /// Creates and returns a new `Future` that is already marked as success. Notifications will be done using this `DispatchQueue` as execution `Thread`.
    ///
    /// - parameters:
    ///     - result: the value that is used by the `Future`.
    /// - returns: a failed `Future`.
    public func newSucceededFuture<T>(result: T) -> Future<T> {
        return Future<T>(queue: self, result: result, file: "n/a", line: 0)
    }
}
