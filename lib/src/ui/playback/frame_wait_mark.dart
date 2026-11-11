import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../native/app_kernels_ahead.dart';
import '../media/viewer_page_loading.dart';

/// A place frames are shown in ([FramePictureView]) that marks their waits
/// for the engine — its tools still to be opened, kernels a picture is laid
/// with still to be compiled — with ONE mark ([FrameWaitMark]), however
/// many views stand in it: the frame and its ghosts, the cuts of a track
/// stack.
///
/// 🗣️gpu-canonical-store-Q12 (유저 2026-11-10): 「캔버스 자리에 준비 중 표시를
/// 둔다」 — for the seconds, once a launch, in which a compile off the
/// frames' thread leaves the canvas with nothing of its frame to show, or
/// on the picture it showed.
///
/// ⛔Not for a frame that waits for its plugins (I-132-Q34 a): the answer
/// is of the engine's getting ready, and such a frame waits at every step
/// drawn on it.
class FrameWaitPlace extends StatefulWidget {
  const FrameWaitPlace({super.key, required this.child});

  final Widget child;

  /// The place [context]'s frame is shown in — null where it is shown in
  /// none that marks its waits.
  static FramesWaiting? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Place>()?.waiting;

  @override
  State<FrameWaitPlace> createState() => _FrameWaitPlaceState();
}

class _FrameWaitPlaceState extends State<FrameWaitPlace> {
  final FramesWaiting _waiting = FramesWaiting._();

  @override
  void dispose() {
    _waiting._dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _Place(waiting: _waiting, child: widget.child);
}

class _Place extends InheritedWidget {
  const _Place({required this.waiting, required super.child});

  final FramesWaiting waiting;

  @override
  bool updateShouldNotify(_Place oldWidget) =>
      !identical(oldWidget.waiting, waiting);
}

/// The mark of the place it stands in ([FrameWaitPlace]), at its own
/// middle, while a frame shown in that place waits — nothing where it
/// stands in none.
///
/// The app's mark for a page that is not there yet ([ViewerPageLoading],
/// F-315), with no words, and mounted only while a frame waits: nothing of
/// it turns once the frames are shown (🗣️관제 2026-11-10 23:05: 「준비가
/// 끝나면 표시가 프레임을 돌리지 않는다」).
///
/// ONE ring for the floor's panel, whatever it waits for: lying on the
/// floor ([ofTheFloor]) it stands the same one while the app gets its
/// engine ready ([appEngineGetsReady]) — the mark every docked panel's
/// place stands by its dock (`EngineReadyMark`, gpu-canonical-store-Q15),
/// seated here because the middle of the floor's own box is under the
/// panels lying on it.
class FrameWaitMark extends StatelessWidget {
  const FrameWaitMark({super.key, this.ofTheFloor = false});

  /// Whether the panel it stands in lies on the floor.
  final bool ofTheFloor;

  /// Test seam: whether a place stands its mark. A widget test's clock is
  /// pumped and opens no engine, so a canvas it stands would wait — and its
  /// mark turn — for as long as the test settles
  /// (`flutter_test_config.dart`).
  @visibleForTesting
  static bool debugStands = true;

  @override
  Widget build(BuildContext context) {
    final frames = FrameWaitPlace.of(context)?._any;
    final app = ofTheFloor ? appEngineGetsReady : null;
    if (frames == null && app == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: Listenable.merge([frames, app]),
      builder: (context, _) {
        final framesWait = (frames?.value ?? false) && debugStands;
        return framesWait || (app?.value ?? false)
            ? const ViewerPageLoading()
            : const SizedBox.shrink();
      },
    );
  }
}

/// The views of one place whose frame waits for the engine
/// ([FrameWaitPlace]).
class FramesWaiting {
  FramesWaiting._();

  final Set<Object> _views = Set.identity();
  final ValueNotifier<bool> _any = ValueNotifier(false);
  bool _owesItsWord = false;
  bool _gone = false;

  /// [view] says whether its frame [waits].
  ///
  /// 🚨HEARD AFTER THE FRAME BEING BUILT OR PAINTED: a view says it from
  /// its paint, where it meets the wait, and as it is taken down — neither
  /// a moment the mark can be built in.
  void says(Object view, {required bool waits}) {
    final moved = waits ? _views.add(view) : _views.remove(view);
    if (!moved || _owesItsWord) {
      return;
    }
    _owesItsWord = true;
    scheduleMicrotask(() {
      _owesItsWord = false;
      if (!_gone) {
        _any.value = _views.isNotEmpty;
      }
    });
  }

  void _dispose() {
    _gone = true;
    _any.dispose();
  }
}
