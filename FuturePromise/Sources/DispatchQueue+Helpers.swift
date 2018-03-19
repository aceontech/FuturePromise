//
//  Licensed under Apache License v2.0
//
//  See LICENSE.txt for license information
//  SPDX-License-Identifier: Apache-2.0
//
//  Copyright © 2018 Jarroo.
//

import Foundation

extension DispatchQueue {

    var inQueue: Bool {
        let currentQueueLabel = String(cString: __dispatch_queue_get_label(nil), encoding: .utf8)
        return self.label == currentQueueLabel
    }

    public func execute(_ task: @escaping () -> Void) {
        self.sync {
            task()
        }
    }
}
