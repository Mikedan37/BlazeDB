Pod::Spec.new do |s|
  s.name             = 'BlazeDBKMM'
  s.version          = '0.1.0'
  s.summary          = 'BlazeDB Kotlin Multiplatform iOS framework (integration scaffolding)'
  s.homepage         = 'https://github.com/Mikedan37/BlazeDB'
  s.license          = { :type => 'MIT' }
  s.author           = { 'BlazeDB' => 'https://github.com/Mikedan37/BlazeDB' }
  s.platform         = :ios, '15.0'
  s.source           = { :path => '.' }
  s.vendored_frameworks = 'BlazeDBKMM.xcframework'
  s.static_framework = true
  s.pod_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -lBlazeDBAndroidBridge',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../../.build/kmm-ios-bridge/iosArm64" "${PODS_TARGET_SRCROOT}/../../.build/kmm-ios-bridge/iosSimulatorArm64"',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -lBlazeDBAndroidBridge',
  }
  s.xcconfig = {
    'ENABLE_USER_SCRIPT_SANDBOXING' => 'NO',
  }
end
