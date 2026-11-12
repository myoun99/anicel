import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★WHAT IS DRAWN OVER AN EXPORT'S FRAME IS LAID ON THE ENGINE: NO FRAME
/// IS DRAWN ON A FLUTTER CANVAS ON ITS WAY TO A WRITER.
///
/// 🗣️gpu-export-path ① (관제 2026-11-11, the line it lands with): 「덧그림
/// 다섯 길 각각이 엔진에서 얹히는 핀」. The five: the SE rows' name tags over
/// a film's cut (`_nameTagsOver`), the guides and the camera over the
/// picture as shown (`_shownOver`), the cels tab's (`renderCelGroup`), a
/// layered file's rows (`celGroupRows`), and a track's names and veils over
/// the one under it (`_stackUnit`). Each is drawn by Flutter on nothing —
/// the letters are Flutter's (connection-round-checklist-Q30) — and laid
/// over the frame by the engine (`drawnOnTheEngine`, `layDrawnOver`).
///
/// ⛔What a behaviour test reads cannot hold this: a frame read back, drawn
/// under its overlay on a canvas and uploaded again shows the same
/// overlay. What differs is a readback and an upload a frame — what the
/// round took out. So the nail is this scan; that each overlay is THERE is
/// held where its road is: `a_saved_picture_shows_the_screen_test` (the
/// guides, the name tags), `a_film_frame_is_the_frame_playback_shows_test`
/// (a track's names, the stage's veils), and
/// `a_cel_wears_the_guides_laid_over_it_test` ·
/// `a_cel_wears_the_camera_work_laid_over_it_test` (the cels tab and its
/// file's rows).
///
/// 🧪It fires: on master as the round found it (`48604553a`) it finds three
/// — the renderer drew a track's pictures on a canvas (twice) and the shot
/// drew its frame under its overlay — and none now.
///
/// An overlay rastered only where it inks (`_rasterOf`, card
/// an-exports-overlay-raster-reads-back-the-whole-frame) lays its own
/// picture off the part's corner by a scene's offset, on no canvas and
/// over nothing: no frame is under it.
void main() {
  // A picture drawn on a canvas: what a frame composed by Flutter is. An
  // overlay's lines and letters are drawn on nothing, and match none.
  final drawn = RegExp(
    r'\.drawImage(?:Rect|Nine)?\(|\.drawPicture\(|\.draw(?:Raw)?Atlas\(',
  );

  test('🚨no frame is drawn on a canvas between the engine and a writer', () {
    final found = <String>[];
    for (final path in const [
      'lib/src/ui/export/export_frame_renderer.dart',
      'lib/src/ui/frame_shots.dart',
    ]) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        if (lines[i].trimLeft().startsWith('//')) {
          continue;
        }
        if (drawn.hasMatch(lines[i])) {
          found.add('$path:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(found, isEmpty);
  });
}
