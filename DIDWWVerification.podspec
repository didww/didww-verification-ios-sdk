Pod::Spec.new do |s|
  s.name             = 'DIDWWVerification'
  s.version          = '1.0.0'
  s.summary          = 'DIDWW phone-number verification SDK for iOS.'
  s.description      = <<-DESC
    A lean, dependency-free async/await Swift client for the DIDWW phone-number verification API
    (SMS, callout). Foundation only — no third-party runtime dependencies.
  DESC
  s.homepage         = 'https://github.com/didww/didww-verification-ios-sdk'

  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'DIDWW' => 'support@didww.com' }

  # Published to the CocoaPods trunk:
  #   pod 'DIDWWVerification', '~> 1.0'
  # NOTE (chicken-and-egg): the :tag below must exist as a real git tag before any consumer can
  # resolve it — create the tag at release time, matching s.version exactly (no `v` prefix).
  s.source           = { :git => 'https://github.com/didww/didww-verification-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_versions   = ['5.9']

  s.source_files     = 'Sources/DIDWWVerification/**/*.swift'
  s.frameworks       = 'Foundation'
end
