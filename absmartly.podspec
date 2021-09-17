#
# Be sure to run `pod lib lint absmartly.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'absmartly'
  s.version          = '1.0.0'
  s.summary          = 'SDK for A\B testing.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/absmartly/ios-sdk'
  s.swift_versions   = '5'
  s.license          = { :type => 'Apache', :file => 'LICENSE' }
  s.author           = { 'odyshewroman@gmail.com' => 'roman.odyshew@quantumsoft.ru' }
  s.source           = { :git => 'https://github.com/absmartly/ios-sdk.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'

  s.source_files = 'absmartly/Classes/**/*'
  
  # s.resource_bundles = {
  #   'absmartly' => ['absmartly/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  # s.dependency 'AFNetworking', '~> 2.3'
end
