import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_photo.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/transform_pose.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/services/media/sheet_photo_edits.dart';
import 'package:anicel/src/ui/session/sheet_photo_hold.dart';

import '../../helpers/cel_photo_fixture.dart';
import '../../helpers/cel_text_fixture.dart';

/// I-97-Q3 · Q4: the ONE photo held on a sheet. A grab shows where it has
/// the photo and the cel keeps it where it stood until the hand lets go;
/// what lands — a move, a scale, a turn, the photo taken off — is ONE step
/// of the project's history, and a hand that changed nothing is no step.
void main() {
  const key = celTextTestKey;
  const second = (key: key, id: 2);
  final moved = TransformPose(
    center: CanvasPoint(x: 21, y: 13),
    scaleX: 0.5,
    scaleY: 2,
    rotationDegrees: 30,
  );

  late BrushFrameStore store;
  late HistoryManager history;
  late SheetPhotoHold hold;

  setUp(() {
    store = BrushFrameStore()
      ..storeBakedSurface(
        key,
        drawingOf(
          {},
        ).withPhotos([photoOf(1), photoOf(2, path: 'C:/pool/b.png')]),
      );
    history = HistoryManager();
    hold = SheetPhotoHold(
      edits: SheetPhotoEdits(() => [store]),
      history: history,
    );
  });

  List<CelPhoto> photos() => store.bakedSurfaceOrNull(key)!.photos;
  TransformPose poseOf(List<CelPhoto> photos, int id) =>
      photos.singleWhere((photo) => photo.id == id).reference.pose;

  test('a grab shows where it has the photo, and the cel keeps it where it '
      'stood until the hand lets go', () {
    final stood = poseOf(photos(), 2);
    hold
      ..take(second)
      ..show(second, moved);

    expect(poseOf(hold.shownOn(key, photos()), 2), moved);
    expect(poseOf(photos(), 2), stood, reason: 'not landed');
    expect(history.canUndo, isFalse);
    final other = BrushFrameKey(
      projectId: key.projectId,
      trackId: key.trackId,
      cutId: key.cutId,
      layerId: key.layerId,
      frameId: const FrameId('another'),
    );
    final there = photos();
    expect(
      identical(hold.shownOn(other, there), there),
      isTrue,
      reason: 'a grab on one cel shows nothing on another',
    );

    hold.dropShowing((key: key, id: 1));
    expect(poseOf(hold.shownOn(key, photos()), 2), moved, reason: 'not its');
    hold.dropShowing(second);
    final now = photos();
    expect(identical(hold.shownOn(key, now), now), isTrue);
  });

  test('it lands as ONE step and shows what landed — one undo stands it '
      'where it stood', () {
    final stood = poseOf(photos(), 2);
    hold
      ..take(second)
      ..show(second, moved)
      ..land(second, moved);

    expect(poseOf(photos(), 2), moved);
    expect(poseOf(photos(), 1), photoOf(1).reference.pose, reason: 'alone');
    expect(history.undoCount, 1);
    final now = photos();
    expect(identical(hold.shownOn(key, now), now), isTrue);
    expect(hold.held, second, reason: 'still held');

    history.undo();
    expect(poseOf(photos(), 2), stood);
  });

  test('the delete takes the photo held off its cel as ONE step and lets go '
      'of it — one undo puts it back', () {
    hold
      ..take(second)
      ..delete();

    expect([for (final photo in photos()) photo.id], [1]);
    expect(history.undoCount, 1);
    expect(hold.held, isNull);

    history.undo();
    expect([for (final photo in photos()) photo.id], [1, 2]);
  });

  test('🚨a hand that changed nothing makes no step — a pose it stands at '
      'already, a photo already gone', () {
    hold
      ..take(second)
      ..land(second, poseOf(photos(), 2));
    expect(history.canUndo, isFalse);

    hold
      ..take((key: key, id: 9))
      ..delete();
    expect(history.canUndo, isFalse);
    expect(hold.held, isNull, reason: 'let go all the same');
  });

  test('one photo is held: taking another lets go of the first, and letting '
      'go of one is of that one alone', () {
    hold
      ..take(second)
      ..take((key: key, id: 1));

    expect(hold.held, (key: key, id: 1));
    hold.letGoOf(second);
    expect(hold.held, (key: key, id: 1), reason: 'not the one held');
    hold.letGoOf((key: key, id: 1));
    expect(hold.held, isNull);
  });

  test('what a grab shows is the grab\'s: a photo let go of mid-grab shows '
      'where the hand has it until the grab ends', () {
    hold
      ..take(second)
      ..show(second, moved)
      ..letGo();
    expect(poseOf(hold.shownOn(key, photos()), 2), moved, reason: 'let go');

    hold.take((key: key, id: 1));
    expect(poseOf(hold.shownOn(key, photos()), 2), moved, reason: 'another');

    hold.dropShowing(second);
    final now = photos();
    expect(identical(hold.shownOn(key, now), now), isTrue);
  });
}
