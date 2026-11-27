# Not published: 1.3.4 is the last ABSmartlySwiftSDK version on the CocoaPods trunk, and 1.x after
# 1.3.4 is distributed through Swift Package Manager only (see README). This file is kept because the
# release workflow and DefaultClientTest check that its version matches the tag and SDKVersion.
Pod::Spec.new do |spec|
  spec.name = 'ABSmartlySwiftSDK'
  spec.version = '1.6.0'
  spec.summary = 'A/B Smartly Swift SDK'
  spec.description = 'A/B Smartly SDK for iOS/tvOS/watchOS'

  spec.homepage = 'https://github.com/absmartly/swift-sdk'
  spec.swift_versions = '5'
  spec.license = { :type => 'Apache', :file => 'LICENSE' }
  spec.author = { 'ABSmartly' => 'sdk@absmartly.com' }
  spec.source = { :git => 'https://github.com/absmartly/swift-sdk.git', :tag => 'v'+spec.version.to_s }

  spec.ios.deployment_target = '10.0'
  spec.tvos.deployment_target = '10.0'
  spec.osx.deployment_target = '10.10'
  spec.watchos.deployment_target = '3.0'
  
  spec.module_name = 'ABSmartly'
  spec.source_files = 'Sources/ABSmartly/**/*.swift'
  spec.requires_arc = true
  spec.framework = 'Foundation'
  spec.dependency 'PromiseKit', '~> 6.8'
  spec.dependency 'SwiftAtomics', '~> 1.0.2'
  spec.dependency 'SwiftyJSON', '~> 5.0.0'
end
