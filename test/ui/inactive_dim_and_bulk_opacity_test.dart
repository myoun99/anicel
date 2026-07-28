import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// Numeric bulk opacity (session bulk setter). The R2 lighttable dim was
/// retired in UI-R5 (user: unnecessary) — the master opacity bar and the
/// visibility solo cover the "focus on my layer" workflows.
void main() {
  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  test('setAllLayersOpacity sets every non-camera layer', () {
    final s = session();
    s.setAllLayersOpacity(0.4);
    for (final layer in s.layers) {
      if (layer.kind != LayerKind.camera) {
        expect(layer.opacity, moreOrLessEquals(0.4, epsilon: 1e-9));
      }
    }
    s.resetAllLayersOpacity();
    for (final layer in s.layers) {
      if (layer.kind != LayerKind.camera) {
        expect(layer.opacity, 1.0);
      }
    }
  });
}
