Pod::Spec.new do |s|
  s.name             = 'ABSmartlySwiftSDK'
  s.version          = '1.0.0'
  s.summary          = 'A/B Smartly Swift SDK'
  s.description      = <<-DESC
  A/B Smartly SDK
                       DESC

  s.homepage         = 'https://github.com/absmartly/swift-sdk'
  s.swift_versions   = '5'
  s.license          = { :type => 'Apache', :file => 'LICENSE' }
  s.author           = { 'sdk@absmartly.com' => 'sdk@absmartly.com' }
  s.source           = { :git => 'https://github.com/absmartly/swift-sdk.git', :tag => "v"+""s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.tvos.deployment_target  = "10.0"
  s.osx.deployment_target  = "10.14"
  s.watchos.deployment_target = "3.0"
  
  s.source_files = 'Sources/**/*.swift'
  s.requires_arc            = true
  s.framework               = "Foundation"
end
