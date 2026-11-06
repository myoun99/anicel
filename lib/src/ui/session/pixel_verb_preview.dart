import 'package:flutter/foundation.dart';

import '../../models/bitmap_surface.dart';
import '../../models/brush_frame_key.dart';
import '../../services/brush_frame_editing_coordinator.dart';
import '../../services/cel_pixel_overwrite.dart' show CelPixelVerb;

/// The colour edit list's PREVIEW: the cels the canvas shows as the row
/// whose preview is on would leave them, written nowhere.
///
/// 🗣️I-164 (유저 2026-11-05): 「색변환의 수치 지정해서 하는 버튼들. 삭제나
/// 남기기나 2치화. 그런거는 프리뷰버튼 두도록 … 누르면 프리뷰로 보임.
/// 프리뷰는 한번에 하나만 활성화 가능하고, 그 색 편집 앵커창 나가면
/// 사라짐. 즉 체크해제됨.」
///
/// ★ONE AT A TIME BY ITS SHAPE: [verb] is one value, so turning a row's on
/// turns the other's off.
///
/// The pictures are the row's own command, run and kept
/// ([previewOf] — `PixelVerbs.previewOf`): what shows is what lands. They
/// are made when the canvas asks for them ([cels]) and kept until what
/// they are made of moves ([inputs]: the knobs, and every write to a cel —
/// `BrushFrameStore.celPixelRevision`, the one signal every surface write
/// bumps, followed as the canvas follows it), so a drag of a knob makes
/// one a frame.
final class PixelVerbPreview extends ChangeNotifier {
  PixelVerbPreview({
    required Map<BrushFrameKey, BitmapSurface> Function(CelPixelVerb verb)
    previewOf,
    required Listenable inputs,
    required BrushFrameEditingCoordinator? Function() coordinator,
  }) : _previewOf = previewOf,
       _inputs = inputs,
       _coordinator = coordinator {
    _inputs.addListener(_inputsMoved);
  }

  final Map<BrushFrameKey, BitmapSurface> Function(CelPixelVerb verb)
  _previewOf;
  final Listenable _inputs;
  final BrushFrameEditingCoordinator? Function() _coordinator;

  /// What [verb]'s row would leave the shown cels as, until [_inputs] move.
  Map<BrushFrameKey, BitmapSurface>? _kept;

  /// The store the kept pictures are declared to, while they are held.
  BrushFrameEditingCoordinator? _declaredTo;

  CelPixelVerb? _verb;

  /// The row whose preview is on, or null.
  CelPixelVerb? get verb => _verb;

  set verb(CelPixelVerb? value) {
    if (value == _verb) {
      return;
    }
    _verb = value;
    _letGo();
    notifyListeners();
  }

  /// The cels the canvas shows as [verb]'s row would leave them — by the
  /// row each names; empty with no preview on.
  Map<BrushFrameKey, BitmapSurface> cels() {
    final verb = _verb;
    if (verb == null) {
      return const {};
    }
    return _kept ??= _keep(_previewOf(verb));
  }

  /// [made], declared to the store as a derived view: the store's memory
  /// discipline may take it back, and [cels] makes it again
  /// (`BrushFrameStore.holdReclaimableView` — the lift's hole's own law).
  Map<BrushFrameKey, BitmapSurface> _keep(
    Map<BrushFrameKey, BitmapSurface> made,
  ) {
    final coordinator = _coordinator();
    if (coordinator != null && made.isNotEmpty) {
      _declaredTo = coordinator;
      coordinator.frameStore.holdReclaimableView(
        this,
        bytes: () => made.entries.fold(
          0,
          (bytes, cel) =>
              bytes +
              cel.value.bytesNotSharedWith(
                coordinator.currentSurfaceOf(cel.key),
              ),
        ),
        reclaim: () => _kept = null,
      );
    }
    return made;
  }

  void _inputsMoved() {
    if (_verb == null) {
      return;
    }
    _letGo();
    notifyListeners();
  }

  void _letGo() {
    _kept = null;
    _declaredTo?.frameStore.releaseReclaimableView(this);
    _declaredTo = null;
  }

  @override
  void dispose() {
    _inputs.removeListener(_inputsMoved);
    _letGo();
    super.dispose();
  }
}
