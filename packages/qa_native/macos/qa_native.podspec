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
  # AudioToolbox carries the OS audio decoder. ↩️AVFoundation, CoreMedia,
  # CoreVideo and CoreGraphics carried the movie writer and reader
  # (AUDIO-PRO R7), until the connection round (connection-round-checklist
  # H, 2026-11-08) moved them to the Rust engine.
  s.frameworks       = 'CoreFoundation', 'AudioToolbox'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  # -ffp-contract=off must be repeated here, NOT only in
  # src/CMakeLists.txt: CocoaPods compiles this source through Xcode, so
  # the CMake flags never reach the shipped app. Without it clang fuses
  # `a*b + c` into an FMA that rounds ONCE where Dart rounds twice — the
  # exact defect #614 caught on Apple silicon (182 where the reference
  # says 181). CI's parity job builds the CMake standalone, which HAS the
  # flag, so a drift here would not show up there: the same .qap would
  # simply render different pixels on a Mac app build than on Windows.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_OPTIMIZATION_LEVEL' => '3',
    'OTHER_CFLAGS' => '$(inherited) -ffp-contract=off',
  }
  s.swift_version = '5.0'
end
