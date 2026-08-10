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

  // The sweep's subject is "rows that HAVE a picture opacity", which used
  // to be spelled "everything but the camera". It is not any more: the
  // TRANSITION row is read-only notation on the track's axis with no
  // picture of its own, so it keeps its value. Ask the predicate the setter
  // asks instead of a proxy for it, and the next such row is covered too.
  test('setAllLayersOpacity sets every picture-opacity layer', () {
    final s = session();
    s.setAllLayersOpacity(0.4);
    for (final layer in s.layers) {
      if (layerKindHasPictureOpacity(layer.kind)) {
        expect(layer.opacity, moreOrLessEquals(0.4, epsilon: 1e-9));
      } else {
        expect(layer.opacity, 1.0, reason: '${layer.kind} takes no bulk set');
      }
    }
    s.resetAllLayersOpacity();
    for (final layer in s.layers) {
      expect(layer.opacity, 1.0);
    }
  });
}
