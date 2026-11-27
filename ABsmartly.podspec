Pod::Spec.new do |spec|
  spec.name = 'ABsmartly'
  spec.version = '2.1.0'
  spec.summary = 'ABsmartly Swift SDK'
  spec.description = 'ABsmartly A/B testing SDK for iOS, macOS, tvOS, watchOS and visionOS: async/await, Swift 6 strict concurrency, no third-party dependencies.'

  spec.homepage = 'https://github.com/absmartly/swift-sdk'
  spec.swift_versions = ['6.0']
  spec.license = { :type => 'Apache', :file => 'LICENSE' }
  spec.author = { 'ABsmartly' => 'sdk@absmartly.com' }
  spec.source = { :git => 'https://github.com/absmartly/swift-sdk.git', :tag => 'v' + spec.version.to_s }

  spec.ios.deployment_target = '15.0'
  spec.tvos.deployment_target = '15.0'
  spec.osx.deployment_target = '12.0'
  spec.watchos.deployment_target = '8.0'
  spec.visionos.deployment_target = '1.0'

  spec.module_name = 'ABsmartly'
  spec.default_subspecs = 'Core'
  spec.framework = 'Foundation'

  spec.subspec 'Core' do |core|
    core.source_files = 'Sources/ABsmartly/**/*.swift'
  end

  # The SwiftUI property wrappers, the `ABsmartlyUI` product in SwiftPM. CocoaPods builds one module,
  # so with this subspec they are part of `import ABsmartly`.
  spec.subspec 'UI' do |ui|
    ui.dependency 'ABsmartly/Core'
    ui.source_files = 'Sources/ABsmartlyUI/**/*.swift'
    ui.framework = 'SwiftUI'
    # Same module as Core here, so the sources skip their `import ABsmartly`.
    ui.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) ABSMARTLY_SINGLE_MODULE' }
  end
end
