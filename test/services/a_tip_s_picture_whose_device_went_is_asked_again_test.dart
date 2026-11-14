import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gpu_engine/gpu_engine.dart' show GpuReadFailed;
import 'package:anicel/src/models/brush_tip_mask.dart';
import 'package:anicel/src/native/app_gpu_engine.dart';
import 'package:anicel/src/services/brush_tip_thumbnails.dart';

import '../helpers/the_apps_engine_let_go.dart';

/// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「장치를 잃으면 앱은 꺼지지
/// 않고 새 장치를 열어 사본으로 되살린다」 — a tip's picture on its way as
/// the app's device goes is asked again of the next engine, WHENEVER the
/// word of its failing comes back: whether its device went is asked of the
/// engine its making began on ([BrushTipThumbnails]).
///
/// ↩️It was asked of the engine the app had by then, and a failure that
/// came back after the app let the gone one go — a turn after it first
/// hears of it — was said as an error and left its cell empty for the run
/// (board `a-tip-thumbnail-read-as-its-device-went-stays-empty`).
///
/// How a picture is made is stood in for ([BrushTipThumbnails.debugMake]),
/// each in the test's own time; one made on the engine is pinned where it
/// lands (`a_tip_s_picture_is_made_once_the_engine_is_open_test.dart`).
///
/// On the app's own engine, which two of these lose: the one after finds
/// the next. ⚠️And on the app's one line of pictures
/// ([BrushTipThumbnails.instance]): a scene that fails leaves it mid-way,
/// and those after it fail with it — the first red is the one to read.
void main() {
  late List<({BrushTipMask of, Completer<Uint8List> made})> making;
  late List<Object> said;
  List<BrushTipMask> asked() => [for (final one in making) one.of];

  setUp(() {
    making = [];
    said = [];
    BrushTipThumbnails.debugMake = (mask) {
      final made = Completer<Uint8List>();
      making.add((of: mask, made: made));
      return made.future;
    };
    final reported = FlutterError.onError;
    FlutterError.onError = (details) => said.add(details.exception);
    addTearDown(() {
      BrushTipThumbnails.debugMake = null;
      FlutterError.onError = reported;
      // No test leaves the app on a device that is gone.
      letTheGoneAppGpuEngineGo();
    });
  });

  test('🚨a picture whose making fails after the app let its engine go — '
      'the word of it late, as a worker\'s is — is asked again of the '
      'next, ahead of what waits behind it: nothing said, no cell left '
      'empty', () async {
    await openAppGpuEngine();
    final (late, behind) = (_mask('late'), _mask('behind'));
    final picture = BrushTipThumbnails.instance.of(late);
    BrushTipThumbnails.instance.of(behind);
    expect(asked(), [late], reason: '⛔premise: one after another');

    theAppsEngineLostAndLetGo();
    await openAppGpuEngine();
    expect(asked(), [late], reason: '⛔premise: the one on its way is waited');
    making.single.made.completeError(GpuReadFailed('a read'));
    await pumpEventQueue();

    expect(said, isEmpty);
    expect(asked(), [late, late]);
    final made = Uint8List.fromList([7]);
    making.last.made.complete(made);
    await pumpEventQueue();
    expect(picture.value, same(made));
    expect(asked(), [late, late, behind]);
    making.last.made.complete(Uint8List(1));
    await pumpEventQueue();
  });

  test('a picture whose making fails on a device that is gone, the engine '
      'the app\'s still, waits for the next the app opens — asked no more '
      'of the one that is gone, nor while none is open', () async {
    await openAppGpuEngine();
    final picture = BrushTipThumbnails.instance.of(_mask('held'));

    theAppsEngineLost();
    making.single.made.completeError(GpuReadFailed('a read'));
    await pumpEventQueue();
    expect(said, isEmpty);
    expect(making, hasLength(1), reason: 'not of an engine that is gone');

    letTheGoneAppGpuEngineGo();
    await pumpEventQueue();
    expect(making, hasLength(1), reason: 'nor of none');

    await openAppGpuEngine();
    expect(making, hasLength(2));
    final made = Uint8List.fromList([9]);
    making.last.made.complete(made);
    await pumpEventQueue();
    expect(picture.value, same(made));
  });

  test('a picture the engine would not make, its device there, is said and '
      'its cell left empty — what waits behind it made all the same', () async {
    await openAppGpuEngine();
    final (refused, behind) = (_mask('refused'), _mask('after'));
    final picture = BrushTipThumbnails.instance.of(refused);
    BrushTipThumbnails.instance.of(behind);

    final why = StateError('would not');
    making.single.made.completeError(why);
    await pumpEventQueue();

    expect(said, [same(why)]);
    expect(picture.value, isNull);
    expect(asked(), [refused, behind], reason: 'not asked again');
    making.last.made.complete(Uint8List(1));
    await pumpEventQueue();
  });
}

BrushTipMask _mask(String id) =>
    BrushTipMask(id: id, size: 4, alpha: Uint8List(16));
