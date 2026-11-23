import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨EVERY PAINT OF A SCREEN'S TEXTURE THAT FLUTTER SUBMITS IS TOLD READ IN
/// THE END — the frames after it that do not paint it among them
/// (관제 2026-11-24, card the-galaxy-tab-canvas-went-slow-on-build-1095 ②:
/// 「안 그려진 프레임에도 『다 읽음』이 와야 한다」). A screen waits for that
/// word before it draws on a surface again (`ScreenTurns`): one paint never
/// told read holds it to the bound at every turn.
///
/// Patch 0007 tells it this way, and this reads that it does: the raster,
/// after each frame's submit, asks every texture registered — whether the
/// frame painted it or not (`TextureRegistry::OnFrameSubmitted`); a texture
/// with paints not yet told tells them submitted and hangs "read" on an
/// empty submit behind them — on any status, a failed one included.
void main() {
  const patch =
      'tool/flutter_engine/3.47.4/'
      '0007-android-a-hardware-buffer-texture-tells-its-producer-when-the-gpu-has-read-it.patch';
  const stack = 'tool/flutter_engine/android_patch';

  String added(String file) {
    final text = File(patch).readAsStringSync().replaceAll('\r\n', '\n');
    final at = text.indexOf('diff --git a/$file b/$file');
    expect(at, isNot(-1), reason: 'the patch changes $file');
    final end = text.indexOf('\ndiff --git ', at + 1);
    return text
        .substring(at, end == -1 ? text.length : end)
        .split('\n')
        .where((line) => line.startsWith('+') && !line.startsWith('+++'))
        .map((line) => line.substring(1).trim())
        .where((line) => !line.startsWith('//'))
        .join('\n');
  }

  test('the raster asks every texture after each frame\'s submit', () {
    final raster = added('engine/src/flutter/shell/common/rasterizer.cc');
    expect(
      raster,
      contains('compositor_context_->texture_registry()->OnFrameSubmitted();'),
    );
    final registry = added('engine/src/flutter/common/graphics/texture.cc');
    expect(
      registry,
      matches(
        RegExp(
          r'TextureRegistry::OnFrameSubmitted\(\) \{\s*'
          r'for \(auto& it : mapping_\) \{\s*'
          r'it\.second->OnFrameSubmitted\(\);',
        ),
      ),
      reason: 'every texture registered, painted this frame or not',
    );
  });

  test('a texture with paints not yet told tells them submitted, and read '
      'on whatever status the submit behind them ends with', () {
    final texture = added(
      'engine/src/flutter/shell/platform/android/'
      'image_external_texture_vk_impeller.cc',
    );
    expect(
      texture,
      contains('if (read_signal_ == nullptr || painted_ == submitted_) {'),
    );
    expect(texture, contains('signal(id, kReadSubmitted, through);'));
    expect(
      texture,
      matches(
        RegExp(
          r'Submit\(\s*\{buffer\},\s*\[signal, id, through\]'
          r'\(impeller::CommandBuffer::Status\) \{\s*'
          r'signal\(id, kReadDone, through\);\s*\}',
        ),
      ),
      reason: 'told read on every status: no status is looked at',
    );
  });

  test('the stack built is the one carrying the signal', () {
    expect(File(stack).readAsStringSync().trim(), '0007');
  });
}
