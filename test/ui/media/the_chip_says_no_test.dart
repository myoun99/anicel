import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/ui/media/media_asset_drag_chip.dart';
import 'package:anicel/src/ui/media/media_asset_drag_data.dart';
import 'package:anicel/src/ui/media/media_asset_drop_target.dart';
import 'package:anicel/src/ui/media/media_asset_kind_icon.dart';
import 'package:anicel/src/ui/media/media_drop_verdict.dart';
import 'package:anicel/src/ui/media/media_pool_panel.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppColors;

/// 🚨THE CHIP SAYS NO, AND ONLY THE CHIP (유저 2026-09-11, 미디어 배치 라운드:
/// 「불가능 = 칩의 금지 표시(커서는 그대로)」 · 「가능할 때와 불가능할 때 — 칩
/// 하나로만 말한다」 · 「아이콘은 파일 종류를 따른다」).
void main() {
  test('each kind has its own picture — the one the pool row always showed', () {
    expect(mediaAssetKindIcon(MediaAssetKind.audio), Icons.music_note_outlined);
    expect(mediaAssetKindIcon(MediaAssetKind.image), Icons.image_outlined);
    expect(mediaAssetKindIcon(MediaAssetKind.video), Icons.movie_outlined);
    expect(
      mediaAssetKindIcon(MediaAssetKind.pdf),
      Icons.picture_as_pdf_outlined,
    );
  });

  group('the chip', () {
    Future<void> pumpChip(
      WidgetTester tester, {
      MediaAssetKind kind = MediaAssetKind.audio,
      ValueNotifier<bool?>? verdict,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MediaAssetDragChip(
              kind: kind,
              name: 'door_close.mp3',
              verdict: verdict,
            ),
          ),
        ),
      ),
    );

    testWidgets('its icon is the file\'s kind — the pool row\'s own', (
      tester,
    ) async {
      for (final kind in MediaAssetKind.values) {
        await pumpChip(tester, kind: kind);
        expect(
          tester.widget<Icon>(find.byType(Icon).first).icon,
          mediaAssetKindIcon(kind),
        );
      }
    });

    testWidgets('a NO wears the ban; a yes and no answer are the same chip', (
      tester,
    ) async {
      final verdict = ValueNotifier<bool?>(null);
      addTearDown(verdict.dispose);
      await pumpChip(tester, verdict: verdict);
      const ban = ValueKey<String>('drag-chip-ban');
      expect(find.byKey(ban), findsNothing);

      verdict.value = false;
      await tester.pump();
      expect(find.byKey(ban), findsOneWidget);
      OutlinedBorder ring() =>
          tester
                  .widget<Material>(
                    find.byKey(const ValueKey<String>('drag-chip-0')),
                  )
                  .shape!
              as OutlinedBorder;
      expect(ring().side.color, AppColors.danger);

      verdict.value = true;
      await tester.pump();
      expect(find.byKey(ban), findsNothing);
    });
  });

  group('the entrance answers for the file over it', () {
    Future<(ValueNotifier<bool?>, List<String>)> pumpEntrance(
      WidgetTester tester, {
      required bool Function(MediaAssetDragData data, Offset at)? accepts,
    }) async {
      final verdict = ValueNotifier<bool?>(null);
      addTearDown(verdict.dispose);
      final dropped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaDropVerdictScope(
              verdict: verdict,
              child: Column(
                children: [
                  Draggable<MediaAssetDragData>(
                    data: const MediaAssetDragData(
                      path: r'C:\snd\door.wav',
                      name: 'door.wav',
                    ),
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: const SizedBox(width: 8, height: 8),
                    child: Container(
                      key: const ValueKey<String>('source'),
                      width: 40,
                      height: 40,
                      color: const Color(0xFF888888),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: MediaAssetDropTarget(
                      key: const ValueKey<String>('entrance'),
                      accepts: accepts,
                      onDrop: (data, _) => dropped.add(data.path),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return (verdict, dropped);
    }

    Future<TestGesture> hover(WidgetTester tester) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>('source'))),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('entrance'))),
      );
      await tester.pump();
      return gesture;
    }

    testWidgets('a NO is said while it hovers, and letting go does nothing', (
      tester,
    ) async {
      final (verdict, dropped) = await pumpEntrance(
        tester,
        accepts: (_, _) => false,
      );
      final gesture = await hover(tester);
      expect(verdict.value, isFalse);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(dropped, isEmpty, reason: 'impossible means nothing happens');
      expect(verdict.value, isNull, reason: 'the drag is over');
    });

    testWidgets('a yes lands, and leaving takes the answer away', (
      tester,
    ) async {
      final (verdict, dropped) = await pumpEntrance(tester, accepts: null);
      var gesture = await hover(tester);
      expect(verdict.value, isTrue);

      await gesture.moveTo(
        tester.getCenter(find.byKey(const ValueKey<String>('source'))),
      );
      await tester.pump();
      expect(verdict.value, isNull);
      await gesture.up();
      await tester.pumpAndSettle();

      gesture = await hover(tester);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(dropped, [r'C:\snd\door.wav']);
    });
  });

  testWidgets('a pool row\'s icon and its chip are one answer, and the chip '
      'listens to the workspace\'s channel', (tester) async {
    final verdict = ValueNotifier<bool?>(null);
    addTearDown(verdict.dispose);
    final picture = MediaAsset(
      path: r'C:\art\bg.png',
      name: 'bg',
      kind: MediaAssetKind.image,
    );
    final sound = MediaAsset(path: r'C:\snd\door.wav', name: 'door');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaDropVerdictScope(
            verdict: verdict,
            child: MediaPoolPanel(
              assets: [picture, sound],
              usesOf: (_) => const [],
              onImportRequested: () {},
              onRenameAsset: (_, _) {},
              onRelinkAsset: (_, _, _) {},
              onRemoveAsset: (_) {},
              onPromoteAsset: (_) async => false,
              onExportAssetWav: (_) async => false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (final asset in [picture, sound]) {
      final row = find.byKey(ValueKey<String>('media-asset-row-${asset.path}'));
      final chip =
          tester.widget<Draggable<MediaAssetDragData>>(row).feedback
              as MediaAssetDragChip;
      expect(chip.kind, asset.kind);
      expect(chip.verdict, same(verdict));
      expect(
        tester
            .widget<Icon>(
              find.descendant(of: row, matching: find.byType(Icon)).first,
            )
            .icon,
        mediaAssetKindIcon(asset.kind),
      );
    }
  });
}
