# FuturePromise, a Swift promises implementation for iOS, ported from Apple's own SwiftNIO project

## Introduction 

In March 2018, **Apple** released and open-sourced its [SwiftNIO](https://github.com/apple/swift-nio) project, which is, in 
Apple's own words

> "A cross-platform asynchronous event-driven network application framework for rapid development of maintainable 
> high performance protocol servers & clients"
 
While this framework is primarily geared toward Swift on the (Linux) server, I noticed it **contained an implementation of
`Future`s and `Promise`s**. SwiftNIO (NIO = "Non-blocking Input Ouput") and its Promises implementation are based on 
EventLoops for concurrency, but it was straightforward to port it to use `DispatchQueue`s instead. 

This Github repo is the result of that effort. 


## Goal

The goal of this project is to maintain an API-compatible port of SwiftNIO's `Future` and `Promise` implementation for use in 
iOS (and macOS) projects, until Swift gets 
[a superior form of concurrency](https://gist.github.com/lattner/31ed37682ef1576b16bca1432ea9f782), 
i.e. coroutines, or `async await`.

Until then, SwiftNIO's implementation of Promises **can be considered Apple's first and only santioned implementation** of the 
well-known concurrency pattern.
