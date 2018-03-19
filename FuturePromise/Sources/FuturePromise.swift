//
//  Licensed under Apache License v2.0
//
//  See LICENSE.txt for license information
//  SPDX-License-Identifier: Apache-2.0
//

/// A `Result`-like type that is used to track the data through the
/// callback pipeline.
private enum FutureValue<T> {
    case success(T)
    case failure(Error)
}

/// Internal list of callbacks.
///
/// Most of these are closures that pull a value from one future, call a user callback, push the
/// result into another, then return a list of callbacks from the target future that are now ready to be invoked.
///
/// In particular, note that _run() here continues to obtain and execute lists of callbacks until it completes.
/// This eliminates recursion when processing `then()` chains.
private struct CallbackList: ExpressibleByArrayLiteral {
    typealias Element = () -> CallbackList
    var firstCallback: Element?
    var furtherCallbacks: [Element]?

    init() {
        firstCallback = nil
        furtherCallbacks = nil
    }

    init(arrayLiteral: Element...) {
        self.init()
        if !arrayLiteral.isEmpty {
            firstCallback = arrayLiteral[0]
            if arrayLiteral.count > 1 {
                furtherCallbacks = Array(arrayLiteral.dropFirst())
            }
        }
    }

    mutating func append(_ callback: @escaping () -> CallbackList) {
        if self.firstCallback == nil {
            self.firstCallback = callback
        } else {
            if self.furtherCallbacks != nil {
                self.furtherCallbacks!.append(callback)
            } else {
                self.furtherCallbacks = [callback]
            }
        }
    }

    private func allCallbacks() -> [Element] {
        switch (self.firstCallback, self.furtherCallbacks) {
        case (.none, _):
            return []
        case (.some(let onlyCallback), .none):
            return [onlyCallback]
        case (.some(let first), .some(let others)):
            return [first] + others
        }
    }

    func _run() {
        switch (self.firstCallback, self.furtherCallbacks) {
        case (.none, _):
            return
        case (.some(let onlyCallback), .none):
            var onlyCallback = onlyCallback
            loop: while true {
                let cbl = onlyCallback()
                switch (cbl.firstCallback, cbl.furtherCallbacks) {
                case (.none, _):
                    break loop
                case (.some(let ocb), .none):
                    onlyCallback = ocb
                    continue loop
                case (.some(_), .some(_)):
                    var pending = cbl.allCallbacks()
                    while pending.count > 0 {
                        let list = pending
                        pending = []
                        for f in list {
                            let next = f()
                            pending.append(contentsOf: next.allCallbacks())
                        }
                    }
                    break loop
                }
            }
        case (.some(let first), .some(let others)):
            var pending = [first]+others
            while pending.count > 0 {
                let list = pending
                pending = []
                for f in list {
                    let next = f()
                    pending.append(contentsOf: next.allCallbacks())
                }
            }
        }
    }

}

/// A promise to provide a result later.
///
/// This is the provider API for `Future<T>`. If you want to return an
/// unfulfilled `Future<T>` -- presumably because you are interfacing to
/// some asynchronous service that will return a real result later, follow this
/// pattern:
///
/// ```
/// func someAsyncOperation(args) -> Future<ResultType> {
///     let promise: Promise<ResultType> = queue.newPromise()
///     someAsyncOperationWithACallback(args) { result -> Void in
///         // when finished...
///         promise.succeed(result: result)
///         // if error...
///         promise.fail(error: error)
///     }
///     return promise.futureResult
/// }
/// ```
///
/// Note that the future result is returned before the async process has provided a value.
///
/// It's actually not very common to use this directly. Usually, you really want one
/// of the following:
///
/// * If you have an `Future` and want to do something else after it completes,
///     use `.then()`
/// * If you just want to get a value back after running something on another thread,
///     use `Future<ResultType>.async()`
/// * If you already have a value and need an `Future<>` object to plug into
///     some other API, create an already-resolved object with `queue.newSucceededFuture(result)`
///     or `queue.newFailedFuture(error:)`.
///
public struct Promise<T> {
    /// The `Future` which is used by the `Promise`. You can use it to add callbacks which are notified once the
    /// `Promise` is completed.
    public let futureResult: Future<T>

    /// General initializer
    ///
    /// - parameters:
    ///     - eventLoop: The dispatch queue this promise is tied to.
    ///     - file: The file this promise was allocated in, for debugging purposes.
    ///     - line: The line this promise was allocated on, for debugging purposes.
    init(queue: DispatchQueue, file: StaticString, line: UInt) {
        futureResult = Future<T>(queue: queue, file: file, line: line)
    }

    /// Deliver a successful result to the associated `Future<T>` object.
    ///
    /// - parameters:
    ///     - result: The successful result of the operation.
    public func succeed(result: T) {
        _resolve(value: .success(result))
    }

    /// Deliver an error to the associated `Future<T>` object.
    ///
    /// - parameters:
    ///      - error: The error from the operation.
    public func fail(error: Error) {
        _resolve(value: .failure(error))
    }

    /// Fire the associated `Future` on the appropriate dispatch queue.
    ///
    /// This method provides the primary difference between the `Promise` and most
    /// other `Promise` implementations: specifically, all callbacks fire on the `DispatchQueue`
    /// that was used to create the promise.
    ///
    /// - parameters:
    ///     - value: The value to fire the future with.
    private func _resolve(value: FutureValue<T>) {
        if futureResult.queue.inQueue {
            _setValue(value: value)._run()
        } else {
            futureResult.queue.execute {
                self._setValue(value: value)._run()
            }
        }
    }

    /// Set the future result and get the associated callbacks.
    ///
    /// - parameters:
    ///     - value: The result of the promise.
    /// - returns: The callback list to run.
    fileprivate func _setValue(value: FutureValue<T>) -> CallbackList {
        return futureResult._setValue(value: value)
    }
}


/// Holder for a result that will be provided later.
///
/// Functions that promise to do work asynchronously can return an `Future<T>`.
/// The recipient of such an object can then observe it to be notified when the operation completes.
///
/// The provider of a `Future<T>` can create and return a placeholder object
/// before the actual result is available. For example:
///
/// ```
/// func getNetworkData(args) -> Future<NetworkResponse> {
///     let promise: Promise<NetworkResponse> = queue.newPromise()
///     queue.async {
///         . . . do some work . . .
///         promise.succeed(response)
///         . . . if it fails, instead . . .
///         promise.fail(error)
///     }
///     return promise.futureResult
/// }
/// ```
///
/// Note that this function returns immediately; the promise object will be given a value
/// later on. This behaviour is common to Future/Promise implementations in many programming
/// languages. If you are unfamiliar with this kind of object, the following resources may be
/// helpful:
///
/// - [Javascript](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Using_promises)
/// - [Scala](http://docs.scala-lang.org/overviews/core/futures.html)
/// - [Python](https://docs.google.com/document/d/10WOZgLQaYNpOrag-eTbUm-JUCCfdyfravZ4qSOQPg1M/edit)
///
/// If you receive a `Future<T>` from another function, you have a number of options:
/// The most common operation is to use `then()` or `map()` to add a function that will be called
/// with the eventual result.  Both methods returns a new `Future<T>` immediately
/// that will receive the return value from your function, but they behave differently. If you have
/// a function that can return synchronously, the `map` function will transform the result `T` to a
/// the new result value `U` and return an `Future<U>`.
///
/// ```
/// let networkData = getNetworkData(args)
///
/// // When network data is received, convert it.
/// let processedResult: Future<Processed> = networkData.map { (n: NetworkResponse) -> Processed in
///     ... parse network data ....
///     return processedResult
/// }
/// ```
///
/// If however you need to do more asynchronous processing, you can call `then()`. The return value of the
/// function passed to `then` must be a new `Future<U>` object: the return value of `then()` is
/// a new `Future<U>` that will contain the eventual result of both the original operation and
/// the subsequent one.
///
/// ```
/// // When converted network data is available, begin the database operation.
/// let databaseResult: Future<DBResult> = processedResult.then { (p: Processed) -> Future<DBResult> in
///     return someDatabaseOperation(p)
/// }
/// ```
///
/// In essence, future chains created via `then()` provide a form of data-driven asynchronous programming
/// that allows you to dynamically declare data dependencies for your various operations.
///
/// `Future` chains created via `then()` are sufficient for most purposes. All of the registered
/// functions will eventually run in order. If one of those functions throws an error, that error will
/// bypass the remaining functions. You can use `thenIfError()` to handle and optionally recover from
/// errors in the middle of a chain.
///
/// At the end of an `Future` chain, you can use `whenSuccess()` or `whenFailure()` to add an
/// observer callback that will be invoked with the result or error at that point. (Note: If you ever
/// find yourself invoking `promise.succeed()` from inside a `whenSuccess()` callback, you probably should
/// use `then()` or `cascade(promise:)` instead.)
///
/// `Future` objects are typically obtained by:
/// * Using `Future<T>.async` or a similar wrapper function.
/// * Using `.then()` on an existing future to create a new future for the next step in a series of operations.
/// * Initializing an `Future` that already has a value or an error
public final class Future<T> {
    // TODO: Provide a tracing facility.  It would be nice to be able to set '.debugTrace = true' on any Future or Promise and have every subsequent chained Future report the success result or failure error.  That would simplify some debugging scenarios.
    fileprivate var value: FutureValue<T>? {
        didSet {
            _isFulfilled = true
        }
    }

    fileprivate var _isFulfilled: Bool

    /// The `DispatchQueue` which is tied to the `Future` and is used to notify all registered callbacks.
    public let queue: DispatchQueue

    /// Whether this `Future` has been fulfilled. This is a thread-safe
    /// computed-property.
    internal var isFulfilled: Bool {
        return _isFulfilled
    }

    /// Callbacks that should be run when this `Future<T>` gets a value.
    /// These callbacks may give values to other `Future`s; if that happens,
    /// they return any callbacks from those `Future`s so that we can run
    /// the entire chain from the top without recursing.
    fileprivate var callbacks: CallbackList = CallbackList()

    private init(queue: DispatchQueue, value: FutureValue<T>?, file: StaticString, line: UInt) {
        self.queue = queue
        self.value = value
        self._isFulfilled = value != nil

//        debugOnly {
//            if let me = eventLoop as? SelectableEventLoop {
//                me.promiseCreationStoreAdd(future: self, file: file, line: line)
//            }
//        }
    }


    fileprivate convenience init(queue: DispatchQueue, file: StaticString, line: UInt) {
        self.init(queue: queue, value: nil, file: file, line: line)
    }

    /// A Future<T> that has already succeeded
    convenience init(queue: DispatchQueue, result: T, file: StaticString, line: UInt) {
        self.init(queue: queue, value: .success(result), file: file, line: line)
    }

    /// A Future<T> that has already failed
    convenience init(queue: DispatchQueue, error: Error, file: StaticString, line: UInt) {
        self.init(queue: queue, value: .failure(error), file: file, line: line)
    }

//    deinit {
//        debugOnly {
//            if let eventLoop = self.queue as? SelectableDispatchQueue {
//                let creation = queue.promiseCreationStoreRemove(future: self)
//                if !isFulfilled {
//                    fatalError("leaking promise created at \(creation)", file: creation.file, line: creation.line)
//                }
//            } else {
//                precondition(isFulfilled, "leaking an unfulfilled Promise")
//            }
//        }
//    }
}

extension Future: Equatable {
    public static func ==(lhs: Future, rhs: Future) -> Bool {
        return lhs === rhs
    }
}

// 'then' and 'map' implementations. This is really the key of the entire system.
extension Future {
    /// When the current `Future<T>` is fulfilled, run the provided callback,
    /// which will provide a new `Future`.
    ///
    /// This allows you to dynamically dispatch new asynchronous tasks as phases in a
    /// longer series of processing steps. Note that you can use the results of the
    /// current `Future<T>` when determining how to dispatch the next operation.
    ///
    /// This works well when you have APIs that already know how to return `Future`s.
    /// You can do something with the result of one and just return the next future:
    ///
    /// ```
    /// let d1 = networkRequest(args).future()
    /// let d2 = d1.then { t -> Future<U> in
    ///     . . . something with t . . .
    ///     return netWorkRequest(args)
    /// }
    /// d2.whenSuccess { u in
    ///     NSLog("Result of second request: \(u)")
    /// }
    /// ```
    ///
    /// Note:  In a sense, the `Future<U>` is returned before it's created.
    ///
    /// - parameters:
    ///     - callback: Function that will receive the value of this `Future` and return
    ///         a new `Future`.
    /// - returns: A future that will receive the eventual value.
    public func then<U>(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (T) -> Future<U>) -> Future<U> {
        let next = Promise<U>(queue: queue, file: file, line: line)
        _whenComplete {
            switch self.value! {
            case .success(let t):
                let futureU = callback(t)
                if futureU.queue.inQueue {
                    return futureU._addCallback {
                        next._setValue(value: futureU.value!)
                    }
                } else {
                    futureU.cascade(promise: next)
                    return CallbackList()
                }
            case .failure(let error):
                return next._setValue(value: .failure(error))
            }
        }
        return next.futureResult
    }

    /// When the current `Future<T>` is fulfilled, run the provided callback, which
    /// performs a synchronous computation and returns a new value of type `U`. The provided
    /// callback may optionally `throw`.
    ///
    /// Operations performed in `thenThrowing` should not block, or they will block the entire
    /// dispatch queue. `thenThrowing` is intended for use when you have a data-driven function that
    /// performs a simple data transformation that can potentially error.
    ///
    /// If your callback function throws, the returned `Future` will error.
    ///
    /// - parameters:
    ///     - callback: Function that will receive the value of this `Future` and return
    ///         a new value lifted into a new `Future`.
    /// - returns: A future that will receive the eventual value.
    public func thenThrowing<U>(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (T) throws -> U) -> Future<U> {
        return self.then(file: file, line: line) { (value: T) -> Future<U> in
            do {
                return Future<U>(queue: self.queue, result: try callback(value), file: file, line: line)
            } catch {
                return Future<U>(queue: self.queue, error: error, file: file, line: line)
            }
        }
    }

    /// When the current `Future<T>` is in an error state, run the provided callback, which
    /// may recover from the error and returns a new value of type `U`. The provided callback may optionally `throw`,
    /// in which case the `Future` will be in a failed state with the new thrown error.
    ///
    /// Operations performed in `thenIfErrorThrowing` should not block, or they will block the entire
    /// dispatch queue. `thenIfErrorThrowing` is intended for use when you have the ability to synchronously
    /// recover from errors.
    ///
    /// If your callback function throws, the returned `Future` will error.
    ///
    /// - parameters:
    ///     - callback: Function that will receive the error value of this `Future` and return
    ///         a new value lifted into a new `Future`.
    /// - returns: A future that will receive the eventual value or a rethrown error.
    public func thenIfErrorThrowing(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (Error) throws -> T) -> Future<T> {
        return self.thenIfError(file: file, line: line) { value in
            do {
                return Future(queue: self.queue, result: try callback(value), file: file, line: line)
            } catch {
                return Future(queue: self.queue, error: error, file: file, line: line)
            }
        }
    }

    /// When the current `Future<T>` is fulfilled, run the provided callback, which
    /// performs a synchronous computation and returns a new value of type `U`.
    ///
    /// Operations performed in `map` should not block, or they will block the entire event
    /// loop. `map` is intended for use when you have a data-driven function that performs
    /// a simple data transformation that can potentially error.
    ///
    /// ```
    /// let future1 = eventually()
    /// let future2 = future1.map { T -> U in
    ///     ... stuff ...
    ///     return u
    /// }
    /// let future3 = future2.map { U -> V in
    ///     ... stuff ...
    ///     return v
    /// }
    /// ```
    ///
    /// - parameters:
    ///     - callback: Function that will receive the value of this `Future` and return
    ///         a new value lifted into a new `Future`.
    /// - returns: A future that will receive the eventual value.
    public func map<U>(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (T) -> (U)) -> Future<U> {
        if U.self == T.self && U.self == Void.self {
            whenSuccess(callback as! (T) -> Void)
            return self as! Future<U>
        } else {
            return then { return Future<U>(queue: self.queue, result: callback($0), file: file, line: line) }
        }
    }

    /// When the current `Future<T>` is in an error state, run the provided callback, which
    /// may recover from the error by returning an `Future<U>`. The callback is intended to potentially
    /// recover from the error by returning a new `Future` that will eventually contain the recovered
    /// result.
    ///
    /// If the callback cannot recover it should return a failed `Future`.
    ///
    /// - parameters:
    ///     - callback: Function that will receive the error value of this `Future` and return
    ///         a new value lifted into a new `Future`.
    /// - returns: A future that will receive the recovered value.
    public func thenIfError(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (Error) -> Future<T>) -> Future<T> {
        let next = Promise<T>(queue: queue, file: file, line: line)
        _whenComplete {
            switch self.value! {
            case .success(let t):
                return next._setValue(value: .success(t))
            case .failure(let e):
                let t = callback(e)
                if t.queue.inQueue {
                    return t._addCallback {
                        next._setValue(value: t.value!)
                    }
                } else {
                    t.cascade(promise: next)
                    return CallbackList()
                }
            }
        }
        return next.futureResult
    }

    /// When the current `Future<T>` is in an error state, run the provided callback, which
    /// can recover from the error and return a new value of type `U`. The provided callback may not `throw`,
    /// so this function should be used when the error is always recoverable.
    ///
    /// Operations performed in `mapIfError` should not block, or they will block the entire
    /// dispatch queue. `mapIfError` is intended for use when you have the ability to synchronously
    /// recover from errors.
    ///
    /// - parameters:
    ///     - callback: Function that will receive the error value of this `Future` and return
    ///         a new value lifted into a new `Future`.
    /// - returns: A future that will receive the recovered value.
    public func mapIfError(file: StaticString = #file, line: UInt = #line, _ callback: @escaping (Error) -> T) -> Future<T> {
        return thenIfError { return Future<T>(queue: self.queue, result: callback($0), file: file, line: line) }
    }


    /// Add a callback.  If there's already a value, invoke it and return the resulting list of new callback functions.
    fileprivate func _addCallback(_ callback: @escaping () -> CallbackList) -> CallbackList {
        assert(queue.inQueue)
        if value == nil {
            callbacks.append(callback)
            return CallbackList()
        }
        return callback()
    }

    /// Add a callback.  If there's already a value, run as much of the chain as we can.
    fileprivate func _whenComplete(_ callback: @escaping () -> CallbackList) {
        if queue.inQueue {
            _addCallback(callback)._run()
        } else {
            queue.execute {
                self._addCallback(callback)._run()
            }
        }
    }

    fileprivate func _whenCompleteWithValue(_ callback: @escaping (FutureValue<T>) -> Void) {
        _whenComplete {
            callback(self.value!)
            return CallbackList()
        }
    }

    /// Adds an observer callback to this `Future` that is called when the
    /// `Future` has a success result.
    ///
    /// An observer callback cannot return a value, meaning that this function cannot be chained
    /// from. If you are attempting to create a computation pipeline, consider `map` or `then`.
    /// If you find yourself passing the results from this `Future` to a new `Promise`
    /// in the body of this function, consider using `cascade` instead.
    ///
    /// - parameters:
    ///     - callback: The callback that is called with the successful result of the `Future`.
    public func whenSuccess(_ callback: @escaping (T) -> Void) {
        _whenComplete {
            if case .success(let t) = self.value! {
                callback(t)
            }
            return CallbackList()
        }
    }

    /// Adds an observer callback to this `Future` that is called when the
    /// `Future` has a failure result.
    ///
    /// An observer callback cannot return a value, meaning that this function cannot be chained
    /// from. If you are attempting to create a computation pipeline, consider `mapIfError` or `thenIfError`.
    /// If you find yourself passing the results from this `Future` to a new `Promise`
    /// in the body of this function, consider using `cascade` instead.
    ///
    /// - parameters:
    ///     - callback: The callback that is called with the failed result of the `Future`.
    public func whenFailure(_ callback: @escaping (Error) -> Void) {
        _whenComplete {
            if case .failure(let e) = self.value! {
                callback(e)
            }
            return CallbackList()
        }
    }

    /// Adds an observer callback to this `Future` that is called when the
    /// `Future` has any result.
    ///
    /// Unlike its friends `whenSuccess` and `whenFailure`, `whenComplete` does not receive the result
    /// of the `Future`. This is because its primary purpose is to do the appropriate cleanup
    /// of any resources that needed to be kept open until the `Future` had resolved.
    ///
    /// - parameters:
    ///     - callback: The callback that is called when the `Future` is fulfilled.
    public func whenComplete(_ callback: @escaping () -> Void) {
        _whenComplete {
            callback()
            return CallbackList()
        }
    }


    /// Internal:  Set the value and return a list of callbacks that should be invoked as a result.
    fileprivate func _setValue(value: FutureValue<T>) -> CallbackList {
        assert(queue.inQueue)
        if self.value == nil {
            self.value = value
            let callbacks = self.callbacks
            self.callbacks = CallbackList()
            return callbacks
        }
        return CallbackList()
    }
}


extension Future {
    /// Return a new `Future` that succeeds when this "and" another
    /// provided `Future` both succeed. It then provides the pair
    /// of results. If either one fails, the combined `Future` will fail with
    /// the first error encountered.
    public func and<U>(_ other: Future<U>, file: StaticString = #file, line: UInt = #line) -> Future<(T,U)> {
        let promise = Promise<(T,U)>(queue: queue, file: file, line: line)
        var tvalue: T?
        var uvalue: U?

        assert(self.queue === promise.futureResult.queue)
        _whenComplete { () -> CallbackList in
            switch self.value! {
            case .failure(let error):
                return promise._setValue(value: .failure(error))
            case .success(let t):
                if let u = uvalue {
                    return promise._setValue(value: .success((t, u)))
                } else {
                    tvalue = t
                }
            }
            return CallbackList()
        }

        let hopOver = other.hopTo(queue: self.queue)
        hopOver._whenComplete { () -> CallbackList in
            assert(self.queue.inQueue)
            switch other.value! {
            case .failure(let error):
                return promise._setValue(value: .failure(error))
            case .success(let u):
                if let t = tvalue {
                    return promise._setValue(value: .success((t, u)))
                } else {
                    uvalue = u
                }
            }
            return CallbackList()
        }

        return promise.futureResult
    }

    /// Return a new Future that contains this "and" another value.
    /// This is just syntactic sugar for `future.and(loop.newSucceedFuture<U>(result: result))`.
    public func and<U>(result: U, file: StaticString = #file, line: UInt = #line) -> Future<(T,U)> {
        return and(Future<U>(queue: self.queue, result: result, file: file, line: line))
    }
}

extension Future {

    /// Fulfill the given `Promise` with the results from this `Future`.
    ///
    /// This is useful when allowing users to provide promises for you to fulfill, but
    /// when you are calling functions that return their own proimses. They allow you to
    /// tidy up your computational pipelines. For example:
    ///
    /// ```
    /// doWork().then {
    ///     doMoreWork($0)
    /// }.then {
    ///     doYetMoreWork($0)
    /// }.thenIfError {
    ///     maybeRecoverFromError($0)
    /// }.map {
    ///     transformData($0)
    /// }.cascade(promise: userPromise)
    /// ```
    ///
    /// - parameters:
    ///     - promise: The `Promise` to fulfill with the results of this future.
    public func cascade(promise: Promise<T>) {
        _whenCompleteWithValue { v in
            switch v {
            case .failure(let err):
                promise.fail(error: err)
            case .success(let value):
                promise.succeed(result: value)
            }
        }
    }

    /// Fulfill the given `Promise` with the error result from this `Future`,
    /// if one exists.
    ///
    /// This is an alternative variant of `cascade` that allows you to potentially return early failures in
    /// error cases, while passing the user `Promise` onwards. In general, however, `cascade` is
    /// more broadly useful.
    ///
    /// - parameters:
    ///     - promise: The `Promise` to fulfill with the results of this future.
    public func cascadeFailure<U>(promise: Promise<U>) {
        self.whenFailure { err in
            promise.fail(error: err)
        }
    }
}

extension Future {
    /// Wait for the resolution of this `Future` by blocking the current thread until it
    /// resolves.
    ///
    /// If the `Future` resolves with a value, that value is returned from `wait()`. If
    /// the `Future` resolves with an error, that error will be thrown instead.
    /// `wait()` will block whatever thread it is called on, so it must not be called on dispatch queue
    /// threads: it is primarily useful for testing, or for building interfaces between blocking
    /// and non-blocking code.
    ///
    /// - returns: The value of the `Future` when it completes.
    /// - throws: The error value of the `Future` if it errors.
    public func wait() throws -> T {
//        if !(self.queue is EmbeddedDispatchQueue) {
//            precondition(!queue.inQueue, "wait() must not be called when on the DispatchQueue")
//        }

        var v: FutureValue <T>? = nil
        let group = DispatchGroup()
        group.enter()
//        let lock = ConditionLock(value: 0)
        _whenComplete { () -> CallbackList in
//            lock.lock()
            v = self.value
            group.leave()
//            lock.unlock(withValue: 1)
            return CallbackList()
        }
        group.wait()
//        lock.lock(whenValue: 1)
//        lock.unlock()

        switch(v!) {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }
}

extension Future {
    /// Returns a new `Future` that fires only when all the provided futures complete.
    ///
    /// This extension is only available when you have a collection of `Future`s that do not provide
    /// result data: that is, they are completion notifiers. In this case, you can wait for all of them. The
    /// returned `Future` will fail as soon as any of the futures fails: otherwise, it will succeed
    /// only when all of them do.
    ///
    /// - parameters:
    ///     - futures: An array of `Future<Void>` to wait for.
    ///     - eventLoop: The `DispatchQueue` on which the new `Future` callbacks will fire.
    /// - returns: A new `Future`.
    public static func andAll(_ futures: [Future<Void>], queue: DispatchQueue) -> Future<Void> {
        let p0: Promise<Void> = queue.newPromise()
        guard futures.count > 0 else {
            p0.succeed(result: ())
            return p0.futureResult
        }

        let body: Future<Void> = futures.reduce(p0.futureResult, { (f1: Future<Void>, f2: Future<Void>) in f1.and(f2).map({ (_ : ((), ())) in }) })
        p0.succeed(result: ())
        return body
    }
}

extension Future {
    /// Returns an `Future` that fires when this future completes, but executes its callbacks on the
    /// target dispatch queue instead of the original one.
    ///
    /// It is common to want to "hop" dispatch queues when you arrange some work: for example, you're closing one channel
    /// from another, and want to hop back when the close completes. This method lets you spell that requirement
    /// succinctly. It also contains an optimisation for the case when the loop you're hopping *from* is the same as
    /// the one you're hopping *to*, allowing you to avoid doing allocations in that case.
    ///
    /// - parameters:
    ///     - target: The `DispatchQueue` that the returned `Future` will run on.
    /// - returns: An `Future` whose callbacks run on `target` instead of the original loop.
    func hopTo(queue target: DispatchQueue) -> Future<T> {
        if target === self.queue {
            // We're already on that dispatch queue, nothing to do here. Save an allocation.
            return self
        }
        let hoppingPromise: Promise<T> = target.newPromise()
        self.cascade(promise: hoppingPromise)
        return hoppingPromise.futureResult
    }
}

/// Execute the given function and synchronously complete the given `Promise` (if not `nil`).
func executeAndComplete<T>(_ promise: Promise<T>?, _ body: () throws -> T) {
    do {
        let result = try body()
        promise?.succeed(result: result)
    } catch let e {
        promise?.fail(error: e)
    }
}
