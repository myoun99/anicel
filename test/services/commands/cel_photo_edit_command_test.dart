import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/commands/cel_photo_edit_command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

/// I-97: a pool photo put on a sheet's ink is ONE step of history — the
/// picture before and after, its pixels untouched — so an undo takes the
/// photo off and a redo puts the very picture back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = celTextTestKey;
  final a = TileCoord(x: 0, y: 0);
  final ink = tileOf({
    (1, 1): [9, 9, 9, 255],
  });

  test('a photo goes on top of the photos the picture carries, under an id '
      'one past the largest — and the drawing is the tiles it was', () {
    final coordinator = editingStackOn(
      drawingOf({a: ink}).withPhotos([photoOf(4), photoOf(2)]),
    );
    final drawing = coordinator.currentSurfaceOf(key).tileAt(a);
    final placed = photoOf(0, path: 'C:/pool/new.png').reference;

    HistoryManager().execute(
      CelPhotoEditCommand.put(
        coordinator: coordinator,
        frameKey: key,
        reference: placed,
      ),
    );

    final after = coordinator.currentSurfaceOf(key);
    expect(after.photos, [
      photoOf(4),
      photoOf(2),
      CelPhoto(id: 5, reference: placed),
    ]);
    expect(after.tileAt(a), same(drawing));
  });

  test('🚨one undo takes it off and one redo puts it back — the very '
      'pictures, under the step\'s own name', () {
    final coordinator = editingStackOn(drawingOf({a: ink}));
    final history = HistoryManager();
    final before = coordinator.currentSurfaceOf(key);
    final command = CelPhotoEditCommand.put(
      coordinator: coordinator,
      frameKey: key,
      reference: photoOf(0).reference,
    );

    history.execute(command);
    final after = coordinator.currentSurfaceOf(key);
    expect(after.photos, [photoOf(1)], reason: '⛔fixture');
    expect(history.undoCount, 1);
    expect(command.description, 'Place photo');

    history.undo();
    expect(coordinator.currentSurfaceOf(key), before);

    history.redo();
    expect(coordinator.currentSurfaceOf(key), after);
  });
}
