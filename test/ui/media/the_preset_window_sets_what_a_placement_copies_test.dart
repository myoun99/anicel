import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_preset_window.dart';

/// 🗣️asset-placement-presets Q4 · Q6 (유저 2026-11-17 「시안대로」): the
/// 배치 프리셋 window sets what every placement of a file copies — a
/// sound's name tag and words, a picture's name and fit, one picture's
/// kind, and the span inside the file — and the pool keeps the answer as
/// one undo step.
void main() {
  final door = MediaAsset(path: 'C:/snd/door.wav', name: 'door');
  final cloud = MediaAsset(
    path: 'C:/pic/cloud.png',
    name: 'cloud',
    kind: MediaAssetKind.image,
  );
  final walk = MediaAsset(
    path: 'C:/mov/walk.mp4',
    name: 'walk',
    kind: MediaAssetKind.video,
    frameCount: 48,
  );

  /// Opens the window over [asset] and answers what it hands back.
  Future<MediaPresetAnswer? Function()> open(
    WidgetTester tester,
    MediaAsset asset, {
    MediaSpanEditor? spanEditor,
  }) async {
    MediaPresetAnswer? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                answer = await showDialog<MediaPresetAnswer>(
                  context: context,
                  builder: (_) => MediaPresetWindow(
                    asset: asset,
                    canvas: const CanvasSize(width: 1920, height: 1080),
                    picture: const CanvasSize(width: 640, height: 360),
                    spanEditor: spanEditor,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => answer;
  }

  Future<void> ok(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('instance-edit-ok-button')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String button, String choice) async {
    await tester.tap(find.byKey(ValueKey<String>(button)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey<String>(choice)));
    await tester.pumpAndSettle();
  }

  testWidgets('a sound starts from its block as it is born, and keeps '
      'unset what was left as born', (tester) async {
    final answer = await open(tester, door);
    TextField field(String key) =>
        tester.widget<TextField>(find.byKey(ValueKey<String>(key)));
    expect(field('media-preset-name').controller!.text, 'SE');
    expect(field('media-preset-words').controller!.text, 'door');

    await tester.enterText(
      find.byKey(const ValueKey<String>('media-preset-words')),
      'slam',
    );
    await ok(tester);

    final preset = answer()!.preset;
    expect(preset.dialogue, 'slam');
    expect(preset.seName, isNull, reason: 'left as born');
    expect(answer()!.name, 'door');
  });

  testWidgets('one picture picks its kind and its fit, and has no span',
      (tester) async {
    final answer = await open(
      tester,
      cloud,
      spanEditor: (_, _, _) => const SizedBox(key: ValueKey<String>('span')),
    );
    expect(find.byKey(const ValueKey<String>('span')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('media-preset-fit-preview')),
      findsOneWidget,
    );

    await pick(
      tester,
      'media-preset-kind',
      'media-preset-kind-${LayerKind.animation.jsonValue}',
    );
    await pick(tester, 'media-preset-fit', 'media-preset-fit-contain');
    await tester.enterText(
      find.byKey(const ValueKey<String>('media-preset-name')),
      'sky',
    );
    await ok(tester);

    expect(answer()!.preset.pictureKind, LayerKind.animation);
    expect(answer()!.preset.fit, MediaFitMode.contain);
    expect(answer()!.name, 'sky');
  });

  testWidgets('a movie sets its span in the editor it is handed, and asks '
      'no kind', (tester) async {
    final answer = await open(
      tester,
      walk,
      spanEditor: (inFrame, outFrame, onChanged) => TextButton(
        key: const ValueKey<String>('span'),
        onPressed: () => onChanged(inFrame + 2, 30),
        child: Text('$inFrame-$outFrame'),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('media-preset-kind')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey<String>('span')));
    await tester.pumpAndSettle();
    expect(find.text('2-30'), findsOneWidget);
    await ok(tester);

    expect(answer()!.preset.inFrame, 2);
    expect(answer()!.preset.outFrame, 30);
  });

  testWidgets('the pool keeps the answer as one undo step', (tester) async {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutCommandCoordinator.updateMediaAssets([
      walk,
    ], description: 'Pool the walk');

    s.mediaPool.editMediaPreset(
      walk.path,
      name: 'run',
      preset: const MediaPreset(inFrame: 4, fit: MediaFitMode.stretch),
    );
    final edited = s.repository.requireProject().mediaAssetByPath(walk.path)!;
    expect(edited.name, 'run');
    expect(edited.preset.inFrame, 4);
    expect(edited.preset.fit, MediaFitMode.stretch);

    s.historyManager.undo();
    final undone = s.repository.requireProject().mediaAssetByPath(walk.path)!;
    expect(undone.name, 'walk');
    expect(undone.preset.inFrame, 0);
  });
}
