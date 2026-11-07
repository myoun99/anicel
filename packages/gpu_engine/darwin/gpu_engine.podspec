Pod::Spec.new do |s|
  s.name             = 'gpu_engine'
  s.version          = '0.0.1'
  s.summary          = "The texture half of Anicel's GPU engine."
  s.description      = 'Shows the engine\'s CVPixelBuffers as Flutter textures.'
  s.homepage         = 'https://github.com/myoun99/anicel'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'PARK GUNWOO' => 'noreply@example.com' }
  s.source           = { :path => '.' }

  # The texture shim only (Classes/GpuEnginePlugin.m): the engine itself is
  # Rust, built by hook/build.dart and shipped as a code asset. One source
  # for iOS and macOS (pubspec.yaml, sharedDarwinSource).
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.frameworks       = 'CoreVideo'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  # As qa_native's pods.
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
