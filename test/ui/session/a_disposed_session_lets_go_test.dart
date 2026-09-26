import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// WHAT A DISPOSED SESSION HAS LET GO OF (round 8, G4).
///
/// `EditorSessionManager.dispose` used to be 43 hand-written steps; it is
/// one list (`_teardown`) and a loop now. A list is only as good as the
/// proof that nothing fell out of it, so every releasable this session
/// holds is NAMED here: add a notifier or a collaborator to the session
/// without adding it to that list and one of these goes red.
///
/// ⛔The last two cases are the ORDER, not the membership — a
/// `removeListener` that ran after the notifier it fed was disposed would
/// pass a membership check and still crash the app.
void main() {
  /// A [ChangeNotifier] that has been disposed refuses a new listener.
  void expectReleased(String name, void Function() addAListener) {
    expect(
      addAListener,
      throwsA(isA<FlutterError>()),
      reason: '$name was still live after dispose — is it in _teardown?',
    );
  }

  EditorSessionManager disposedSession() {
    final session = EditorSessionManager(initialProject: createDefaultProject())
      ..dispose();
    return session;
  }

  test('the flag is set, and it is set FIRST', () {
    // The one step whose position is written at the line: a bake sweep
    // suspended across an engine await reads this when it resumes.
    expect(disposedSession().disposed, isTrue);
  });

  test('every notifier the session owns is released', () {
    final session = disposedSession();
    final owned = <String, void Function()>{
      'currentRowListenable': () =>
          session.standing.currentRowListenable.addListener(() {}),
      'cutLocalLaneRangeSelection': () => session.cutLocalLaneRangeSelection
          .addListener(() {}),
      'revealSelectionTick': () => session.revealSelectionTick.addListener(
        () {},
      ),
      'memoryPressureTicks': () => session.memoryPressureTicks.addListener(
        () {},
      ),
      'visibilitySolo.soloedSeLayerIds': () => session
          .visibilitySolo
          .soloedSeLayerIds
          .addListener(() {}),
      'editingFrameCursor': () => session.editingFrameCursor.addListener(() {}),
      'frameSeekCommitted': () => session.frameSeekCommitted.addListener(() {}),
      'frameRangeSelection': () => session.frameRangeSelection.addListener(
        () {},
      ),
      'brushInputActive': () => session.brushInputActive.addListener(() {}),
      'dragPreview': () => session.dragPreview.addListener(() {}),
      'opacityVerbs.dragPreview': () => session.opacityVerbs.dragPreview
          .addListener(() {}),
      // The V row's preview sat beside the layer's for weeks and the list
      // above named only one of them — it was never released.
      'opacityVerbs.trackDragPreview': () => session
          .opacityVerbs
          .trackDragPreview
          .addListener(() {}),
      'trackFrameRangeSelection': () => session.trackFrameRangeSelection
          .addListener(() {}),
      'historyManager': () => session.historyManager.addListener(() {}),
      'audioConformStore': () => session.audioConformStore.addListener(() {}),
    };
    for (final entry in owned.entries) {
      expectReleased(entry.key, entry.value);
    }
  });

  test('the gap notifier is released even though only its verb is public', () {
    final session = disposedSession();
    expectReleased('gapGlobalFrame', () => session.gapGlobalFrame = 3);
  });

  test('every collaborator that holds something is told to let go', () {
    final session = disposedSession();
    expectReleased(
      'layerStack',
      () => session.layerStack.celTintRevision.addListener(() {}),
    );
    expectReleased(
      'rowSelectionVerbs',
      () => session.rowSelectionVerbs.rowSelection.addListener(() {}),
    );
    expectReleased(
      'voiceRecording',
      () => session.voiceRecording.isVoiceRecording.addListener(() {}),
    );
    expectReleased(
      'playbackRig',
      () => session.playbackRig.playback.globalFrameIndexListenable.addListener(
        () {},
      ),
    );
    expectReleased(
      'appSettings',
      () => session.appSettings.audioSyncSettings.addListener(() {}),
    );
    expectReleased(
      'onionSkin.settings',
      () => session.onionSkin.settings.addListener(() {}),
    );
    expectReleased(
      'onionSkin.layerIds',
      () => session.onionSkin.layerIds.addListener(() {}),
    );
    expectReleased(
      'frameScrub.active',
      () => session.frameScrub.active.addListener(() {}),
    );
    expectReleased(
      'frameScrub.outOfTerritory',
      () => session.frameScrub.outOfTerritory.addListener(() {}),
    );
    expectReleased(
      'cutVerbs.guidesDragPreview',
      () => session.cutVerbs.guidesDragPreview.addListener(() {}),
    );
  });

  test('the lane-range listener is dropped, and nothing reports an error', () {
    // 🚨THE ASSERTION HAS TO CATCH A *REPORTED* ERROR, not a thrown one:
    // `ChangeNotifier.notifyListeners` wraps every listener in try/catch and
    // hands the exception to `FlutterError.reportError`, so a listener that
    // writes into a disposed notifier fails SILENTLY in a plain `test()`.
    // `expect(…, returnsNormally)` here measured nothing (2026-09-08).
    final reported = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = reported.add;
    final session = disposedSession();
    // `_publishCutLocalLaneRange` writes into `cutLocalLaneRangeSelection`,
    // which the same list disposes — so the listener has to be gone.
    session.laneRangeSelection.value = TimelineLaneSelection(
      layerId: session.layers.first.id,
      laneId: 'position',
      startIndex: 0,
      endIndexExclusive: 1,
    );
    FlutterError.onError = previous;
    expect(
      reported.map((d) => d.exception.toString()),
      isEmpty,
      reason: 'a listener the teardown should have removed still fired',
    );
  });

  test('disposing does not throw on the listeners it removes', () {
    // The playback cursor and the three history listeners are removed
    // before `playbackRig` and `historyManager` are released. A reordering
    // that removed them afterwards would surface here.
    expect(disposedSession, returnsNormally);
  });
}
