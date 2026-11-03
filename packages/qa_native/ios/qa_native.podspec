require 'open3'

Pod::Spec.new do |s|
  s.name             = 'qa_native'
  s.version          = '0.0.1'
  s.summary          = 'Anicel native core (FFI).'
  s.description      = 'The portable C hot loops, compiled into the app.'
  s.homepage         = 'https://github.com/myoun99/anicel'
  s.license          = { :file => '../../../LICENSE' }
  s.author           = { 'PARK GUNWOO' => 'noreply@example.com' }
  s.source           = { :path => '.' }

  # Classes/ holds only a forwarder that includes ../src — see the note
  # in that file. The engine is STATICALLY linked into the app: iOS does
  # not allow loading a standalone dylib from the bundle, so Dart resolves
  # its symbols with DynamicLibrary.process().
  s.source_files     = 'Classes/**/*'
  # miniaudio needs the CoreAudio stack at LINK time (it dlopens nothing
  # on Apple); AVFoundation/CoreMedia/CoreVideo carry the video writer
  # (AUDIO-PRO R7); UIKit carries the pen ledger (H43).
  s.frameworks       = 'CoreFoundation', 'CoreAudio', 'AudioToolbox',
                       'AVFoundation', 'CoreMedia', 'CoreVideo',
                       'CoreGraphics', 'UIKit'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  # -ffp-contract=off must be repeated here, NOT only in
  # src/CMakeLists.txt: CocoaPods compiles this source through Xcode, so
  # the CMake flags never reach the shipped app. Without it clang fuses
  # `a*b + c` into an FMA that rounds ONCE where Dart rounds twice — the
  # exact defect #614 caught on Apple silicon (182 where the reference
  # says 181). CI's parity job builds the CMake standalone, which HAS the
  # flag, so a drift here would not show up there: the same .qap would
  # simply render different pixels on iPad than on Windows.
  #
  # The fx plugins' WebAssembly engine (I-132) — the same flags reason: the
  # CMake core's link never reaches this app, so the pod asks the same script
  # (src/wasmtime.cmake: its folder, then the library) as it installs. No
  # prebuilt library is published for iOS, so the script builds the pinned
  # source on this Mac, for the device and for an arm64 simulator — minutes
  # the first time, then kept. An Intel simulator has none and tells a .wasm
  # so, as any build without the engine does.
  qa_wasmtime = lambda do |target|
    script = File.join(__dir__, '..', 'src', 'wasmtime.cmake')
    out, err, status = Open3.capture3(
      'cmake', "-DQA_WASMTIME_TARGET=#{target}", '-P', script)
    raise "qa_native: Wasmtime for #{target}: #{err}" unless status.success?
    out.lines.map(&:chomp)
  end
  device_engine, device_library = qa_wasmtime.call('aarch64-ios')
  _, simulator_library = qa_wasmtime.call('aarch64-ios-sim')
  # As the CMake core's qa_link_wasmtime: empty, the static library's
  # symbols and not a DLL's imports.
  engine = '$(inherited) QA_FX_WASM=1 WASM_API_EXTERN= WASI_API_EXTERN='
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'OTHER_CFLAGS' => '$(inherited) -ffp-contract=off',
    'GCC_PREPROCESSOR_DEFINITIONS[sdk=iphoneos*]' => engine,
    'GCC_PREPROCESSOR_DEFINITIONS[sdk=iphonesimulator*][arch=arm64]' => engine,
    # One version, so one build's headers.
    'HEADER_SEARCH_PATHS' => "$(inherited) \"#{device_engine}/include\"",
    'OTHER_LDFLAGS[sdk=iphoneos*]' => "$(inherited) \"#{device_library}\"",
    'OTHER_LDFLAGS[sdk=iphonesimulator*][arch=arm64]' =>
      "$(inherited) \"#{simulator_library}\"",
  }
  s.swift_version = '5.0'
end
