import 'package:flutter/foundation.dart';

import '../../models/brush_frame_key.dart';
import '../../models/cel_photo.dart';
import '../../models/transform_pose.dart';
import '../../services/history_manager.dart';
import '../../services/history_run.dart';
import '../../services/media/sheet_photo_edits.dart';

/// A photo on a sheet: the ink it lies on and its id there.
typedef SheetPhotoAt = ({BrushFrameKey key, int id});

/// The ONE photo held on a sheet (I-97) — its box up and its pill under
/// it — where a grab of it shows it before it lets go, and what a hand
/// does to it: a move, a scale or a turn landed, or the photo taken off.
///
/// 🗣️유저 I-97-Q3 (2026-10-15): 「브러시 허용이면 어느 도구든 사진을 누르면
/// 집는다」 — 「사진 누르면 변형도구 상자 뜨고, 아래에 알약 공용화되있는거
/// 재사용해서 삭제버튼 추가」; I-97-Q4: 「그 칸 안은 회전, 칸 밖은 해제」.
///
/// The PROJECT's, as what is adjusted on the canvas is ([CanvasAdjust]):
/// Escape lets go of it and Delete takes it off wherever the key is
/// pressed (`HomePage`), and a sheet that stops showing it lets go.
class SheetPhotoHold extends ChangeNotifier {
  SheetPhotoHold({
    required SheetPhotoEdits edits,
    required HistoryManager history,
  }) : _edits = edits,
       _history = history;

  final SheetPhotoEdits _edits;
  final HistoryManager _history;

  SheetPhotoAt? _held;

  /// The grabs of the photo held: undo takes them back one at a time while
  /// it is held ([stepBack]), and they are ONE step once it is let go
  /// ([letGo]) — F-377 (유저 2026-10-17: 「변형 상태는 모두 기본적으로 그걸
  /// 따르도록」). ↩️Each grab stayed a step of its own: a photo moved,
  /// sized and turned took three undos once let go.
  late final HistoryRun _grabs = HistoryRun(_history.gestures);

  /// Where a grab has its photo — the GRAB's, and gone with the grab alone
  /// ([land], [dropShowing]). A photo let go of mid-grab (Escape, another
  /// pointer pressed past it) is still in the grab, which lands it where
  /// the hand lets go: dropped with the hold, the photo jumped back to
  /// where it stood until the hand moved again.
  ({SheetPhotoAt photo, TransformPose pose})? _showing;

  /// The photo held — null while none is.
  SheetPhotoAt? get held => _held;

  /// [photos] — the photos [key]'s ink carries — as they are shown: the one
  /// a grab has where it has it, before it lands; [photos] itself while no
  /// grab has one of them.
  List<CelPhoto> shownOn(BrushFrameKey key, List<CelPhoto> photos) {
    final showing = _showing;
    if (showing == null || showing.photo.key != key) {
      return photos;
    }
    return [
      for (final photo in photos)
        if (photo.id == showing.photo.id)
          photo.withReference(photo.reference.copyWith(pose: showing.pose))
        else
          photo,
    ];
  }

  /// Holds [photo] — and so lets go of whatever was held.
  void take(SheetPhotoAt photo) {
    if (_held == photo) {
      return;
    }
    _grabs.end(_transformed);
    _held = photo;
    _grabs.begin();
    notifyListeners();
  }

  /// Whether undo has a grab of the photo held to take back ([stepBack]).
  bool get canStepBack => _grabs.canTakeBack;

  /// Takes the last grab of the photo held back.
  void stepBack() => _grabs.takeBack();

  /// Where a grab has [photo], before it lets go.
  void show(SheetPhotoAt photo, TransformPose pose) {
    _showing = (photo: photo, pose: pose);
    notifyListeners();
  }

  /// A grab of [photo] let go with nothing to keep.
  void dropShowing(SheetPhotoAt photo) {
    if (_showing?.photo != photo) {
      return;
    }
    _showing = null;
    notifyListeners();
  }

  /// Lands [pose] on [photo] — ONE step — and what the grab showed with it.
  void land(SheetPhotoAt photo, TransformPose pose) {
    _grabs.write(
      () => _edits.edit(
        photo.key,
        description: _transformed,
        history: _history,
        photos: (photos) => _posed(photos, photo.id, pose),
      ),
    );
    dropShowing(photo);
  }

  /// Takes the photo held off its sheet — ONE step — and lets go of it:
  /// the pill's delete, and Delete.
  void delete() {
    final held = _held;
    if (held == null) {
      return;
    }
    // What the hand did to it before is one step, and taking it off
    // another.
    _grabs.end(_transformed);
    _edits.edit(
      held.key,
      description: 'Delete photo',
      history: _history,
      photos: (photos) => _without(photos, held.id),
    );
    letGo();
  }

  /// Lets go of what is held — its grabs ONE step from here on.
  void letGo() {
    if (_held == null) {
      return;
    }
    _grabs.end(_transformed);
    _held = null;
    notifyListeners();
  }

  /// What a grab's step — and the grabs of a hold folded — is called.
  static const String _transformed = 'Transform photo';

  /// Lets go of [photo] and of nothing else — a press another photo took
  /// first has already taken that one.
  void letGoOf(SheetPhotoAt photo) {
    if (_held == photo) {
      letGo();
    }
  }
}

/// [photos] with the one [id] names standing at [pose] — [photos] itself
/// when none does, or it stands there already, so a hand that moved
/// nothing makes no step.
List<CelPhoto> _posed(List<CelPhoto> photos, int id, TransformPose pose) =>
    photos.any((photo) => photo.id == id && photo.reference.pose != pose)
    ? [
        for (final photo in photos)
          if (photo.id == id)
            photo.withReference(photo.reference.copyWith(pose: pose))
          else
            photo,
      ]
    : photos;

/// [photos] without the one [id] names — [photos] itself when none does,
/// so a photo already gone makes no step.
List<CelPhoto> _without(List<CelPhoto> photos, int id) =>
    photos.any((photo) => photo.id == id)
    ? [
        for (final photo in photos)
          if (photo.id != id) photo,
      ]
    : photos;
