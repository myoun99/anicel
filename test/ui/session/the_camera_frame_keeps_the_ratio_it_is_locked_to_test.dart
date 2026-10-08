import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/ui/session/canvas_adjust.dart';

/// I-80: the camera's frame adjusted on the canvas. A drag scales it about
/// its middle as the transform box's two scales do (I-80-Q1: 「가운데가
/// 그대로 — 크기만 바뀐다」), and the ratio the pill's list locks it to
/// holds through every drag (I-80-Q2) — the side the drag moved leading.
void main() {
  const fhd = CanvasSize(width: 1920, height: 1080);

  group('the ratio list', () {
    test('a screen\'s ratio keeps the width and brings the height to it', () {
      final draft = const CameraSizeDraft(
        size: CanvasSize(width: 1920, height: 1000),
      ).locked(CameraRatioLock.wide);

      expect(draft.size, fhd);
      expect(draft.lock, CameraRatioLock.wide);
      expect(draft.ratio, 16 / 9);
    });

    // 🗣️I-80-Q2 note (유저 2026-10-08): 「비율 프리셋은 영화나 tv나 그런곳에서
    // 사용하는 공식적인 비율 그대로 사용. 21:9가 시네마스코프 공식비율이면
    // 문제없음」 — the scope's is 2.39:1.
    test('🚨the scope is 2.39:1, the ratio film calls it by — not 21:9', () {
      expect(CameraRatioLock.scope.fixed, 2.39);
      expect(
        const CameraSizeDraft(size: fhd).locked(CameraRatioLock.scope).size,
        const CanvasSize(width: 1920, height: 803),
      );
    });

    test('the screens\' ratios are the ones they are named by', () {
      expect(
        {for (final lock in CameraRatioLock.values) lock: lock.fixed},
        {
          CameraRatioLock.free: null,
          CameraRatioLock.current: null,
          CameraRatioLock.wide: 16 / 9,
          CameraRatioLock.scope: 2.39,
          CameraRatioLock.standard: 4 / 3,
          CameraRatioLock.square: 1.0,
        },
      );
    });

    test('「지금 비율」 keeps the ratio the frame has, the size untouched', () {
      final draft = const CameraSizeDraft(
        size: CanvasSize(width: 1000, height: 400),
      ).locked(CameraRatioLock.current);

      expect(draft.size, const CanvasSize(width: 1000, height: 400));
      expect(draft.ratio, 2.5);
    });

    test('「자유」 keeps nothing', () {
      final draft = const CameraSizeDraft(
        size: fhd,
      ).locked(CameraRatioLock.square).locked(CameraRatioLock.free);

      expect(draft.size, const CanvasSize(width: 1920, height: 1920));
      expect(draft.ratio, isNull);
      expect(
        draft.scaled(1.5, 0.5).size,
        const CanvasSize(width: 2880, height: 960),
      );
    });
  });

  group('a drag', () {
    test('a free frame takes the two scales as they come', () {
      expect(
        const CameraSizeDraft(size: fhd).scaled(0.5, 2).size,
        const CanvasSize(width: 960, height: 2160),
      );
    });

    test('🚨an edge across moves the width, and the height follows the '
        'ratio', () {
      final draft = const CameraSizeDraft(
        size: fhd,
      ).locked(CameraRatioLock.wide).scaled(1.5, 1);

      expect(draft.size, const CanvasSize(width: 2880, height: 1620));
    });

    test('🚨an edge down moves the height, and the width follows the '
        'ratio', () {
      final draft = const CameraSizeDraft(
        size: fhd,
      ).locked(CameraRatioLock.wide).scaled(1, 0.5);

      expect(draft.size, const CanvasSize(width: 960, height: 540));
    });

    test('a corner moves both by one factor', () {
      final locked = const CameraSizeDraft(
        size: fhd,
      ).locked(CameraRatioLock.standard);
      expect(
        locked.size,
        const CanvasSize(width: 1920, height: 1440),
        reason: '⛔전제: 4:3, the width kept',
      );

      expect(
        locked.scaled(0.5, 0.5).size,
        const CanvasSize(width: 960, height: 720),
      );
    });

    test('an edge carried past the middle grows the frame again — a size '
        'has no flip', () {
      expect(
        const CameraSizeDraft(size: fhd).scaled(-0.5, 1).size,
        const CanvasSize(width: 960, height: 1080),
      );
    });

    test('the frame is never less than one pixel', () {
      expect(
        const CameraSizeDraft(size: fhd).scaled(0, 0).size,
        const CanvasSize(width: 1, height: 1),
      );
      expect(
        const CameraSizeDraft(
          size: fhd,
        ).locked(CameraRatioLock.scope).scaled(0.0001, 1).size,
        const CanvasSize(width: 1, height: 1),
      );
    });

    test('the lock is kept through the drag', () {
      final draft = const CameraSizeDraft(
        size: fhd,
      ).locked(CameraRatioLock.square).scaled(2, 1);

      expect(draft.lock, CameraRatioLock.square);
      expect(draft.ratio, 1);
      expect(draft.size, const CanvasSize(width: 3840, height: 3840));
    });
  });

  group('the one slot', () {
    late CanvasAdjust adjust;
    setUp(() => adjust = CanvasAdjust());
    tearDown(() => adjust.dispose());

    test('🚨opening one closes the other — the canvas holds one box', () {
      adjust.begin(const CameraSizeDraft(size: fhd));
      adjust.begin(CanvasEdgesDraft.of(const CutId('c'), fhd));

      expect(adjust.draft, isA<CanvasEdgesDraft>());
      expect(adjust.cameraSizeShown, isNull);
    });

    test('the camera\'s frame is every cut\'s; a canvas\'s edges are its '
        'own', () {
      adjust.begin(const CameraSizeDraft(size: fhd));
      expect(adjust.isOpenOn(const CutId('a')), isTrue);
      expect(adjust.isOpenOn(null), isTrue);

      adjust.begin(CanvasEdgesDraft.of(const CutId('a'), fhd));
      expect(adjust.isOpenOn(const CutId('a')), isTrue);
      expect(adjust.isOpenOn(const CutId('b')), isFalse);
    });

    test('the frame stands where the hand has it, and goes back where the '
        'grab began when the grab goes away', () {
      const grabbed = CameraSizeDraft(size: fhd);
      adjust
        ..begin(grabbed)
        ..show(grabbed.scaled(0.5, 0.5));
      expect(adjust.cameraSizeShown, const CanvasSize(width: 960, height: 540));
      expect((adjust.draft! as CameraSizeDraft).size, fhd);

      adjust.dropShowing();
      expect(adjust.cameraSizeShown, fhd);
    });
  });
}
