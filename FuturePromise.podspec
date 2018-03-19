Pod::Spec.new do |s|
  s.name         = "FuturePromise"
  s.version      = "0.2.0"
  s.summary      = "Port of Apple's SwiftNIO implementation of Futures and Promises, based on DispatchQueue instead of EventLoop."

  s.description  = <<-DESC
  The goal of this project is to maintain an API-compatible port of SwiftNIO's Future and Promise implementation for use in iOS 
  (and macOS) projects, until Swift gets a superior form of concurrency, i.e. coroutines, or async await.

  Until then, SwiftNIO's implementation of Promises can be considered Apple's first and only santioned implementation of the 
  well-known concurrency pattern for Apple platforms.
                   DESC

  s.homepage     = "https://jarrroo.github.io/FuturePromise"
  s.license      = { :type => "Apache License, Version 2.0", :file => "LICENSE.txt" }
  s.author             = { "Alex Manarpies" => "alex@jarroo.com" }
  s.social_media_url   = "http://twitter.com/jarrroo"

  s.ios.deployment_target = "10.0"
  s.osx.deployment_target = "10.9"
  
  s.source       = { :git => "https://github.com/jarrroo/FuturePromise.git", :tag => "#{s.version}" }

  s.source_files  = "FuturePromise/Sources/**/*.swift"
end
