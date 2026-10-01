import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/playback_quality.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

import '../../helpers/draw_on_current_frame.dart';

/// Ink drawn into a cel MOVES the address the session's playback cache
/// files that frame's composite under — or playback would answer with the
/// composite from before the stroke.
///
/// 🧪Pinned when the audit's eighteenth family (2026-09-28) moved the brush
/// key onto the project role: a mutant that handed the session's composite
/// cache a key naming another row survived every suite. The cache reads a
/// cel's revision through that key, so a wrong key reads no revision at all
/// and every stroke leaves the address where it was.
void main() {
  test('a stroke into the cel changes the frame\'s composite signature', () {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.selectFrameIndex(0);
    s.createDrawingAtCurrentFrame();
    Object signature() => s.renderCaches.cutFrameCompositeCache.signatureOf(
      cut: s.requireActiveCut,
      frameIndex: 0,
      quality: PlaybackQuality.full,
    );
    final blank = signature();

    inkTheCurrentCel(s);

    expect(signature(), isNot(blank));
  });
}
