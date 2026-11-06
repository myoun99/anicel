import 'dart:async';

import 'package:flutter/widgets.dart';

import 'dialogs/app_progress_dialog.dart' show AppWaitWindow;
import 'dialogs/behind_the_wait_window.dart';
import 'dialogs/frame_name_conflict_dialog.dart';
import 'editor_session_manager.dart';
import 'session/frame_clipboard.dart' show ClipboardPlace, LinkedPasteJoins;
import 'text/app_strings.dart';
import 'text/place_lines.dart' show drawingPlaceLines, rowPlaceLines;

/// 링크 붙여넣기, asking first where it would link by NAME.
///
/// 🗣️I-71 (유저 2026-10-05): 「그 외에도 그냥 다른레이어에 붙여넣을때
/// 독립붙여넣기밖에 안되는데, 링크붙여넣기 가능하게. 동작은 말한대로 이름
/// 유지되는붙여넣기. 해당행동시 기존에 이름 존재한다면 링크시킬지 묻는것도
/// 띄우고」.
///
/// The press IS the question, so nothing is asked before the paste: it
/// lands at once unless a name it carries is already held on a row it lands
/// on. Then nothing is written and the link window asks ONCE, listing the
/// row's own frames the pasted blocks would show ([offerLink] — the
/// rename's own guard). Link pastes joined to them, as one undo; Cancel
/// writes nothing.
///
/// 🗣️F-551 (유저 2026-11-04): the paste is tried behind the wait [window],
/// and the join behind it again — the question asks between the two, never
/// over the wait window. Each where it lays down more than one drawing
/// (F-566, `reachesManyBlocks`).
///
/// [place] is where the pressing panel stands ([ClipboardPlace]) — asked
/// again when the answer comes, as the press itself would be.
///
/// The keys a band's copy carries beside its blocks (one-band-no-lane-tail-
/// Q1) ask in the same window, listed as the keys' own paste lists them
/// ([pasteLinkedKeysAskingFirst]) — one question for the one press.
Future<void> pasteLinkedAskingFirst(
  BuildContext context,
  EditorSessionManager session, {
  required ClipboardPlace? Function() place,
  required AppWaitWindow window,
}) async {
  LinkedPasteJoins? joins;
  await takeBehindTheWaitWindow(
    context,
    () => joins = session.clipboard.pasteLinkedAt(place()),
    window: window,
    blocks: session.clipboard.drawingsPastedAt(place()),
  );
  final asked = joins;
  if (asked == null || !context.mounted) {
    return;
  }
  await offerLink<LinkedPasteJoins>(
    context,
    asked,
    notice: asked.any((row) => row.held.isNotEmpty)
        ? AppText.strings.linkedPasteConflictBody
        : null,
    onConflict: (
      lines: (joins) => [
        for (final row in joins) ...[
          ...drawingPlaceLines(
            session.repository.requireProject(),
            row.layerId,
            row.held,
            framePlace: session.framePlaceLabel,
          ),
          if (row.keyNames.isNotEmpty)
            ...rowPlaceLines(session.repository.requireProject(), row.layerId),
        ],
      ],
      join: (_) {
        if (context.mounted) {
          unawaited(
            takeBehindTheWaitWindow(
              context,
              () => session.clipboard.pasteLinkedAt(
                place(),
                joinTakenNames: true,
              ),
              window: window,
              blocks: session.clipboard.drawingsPastedAt(place()),
            ),
          );
        }
      },
      decline: null,
    ),
  );
}

/// The KEYS' 링크 붙여넣기 (F-388), asking first as the frames' does: the
/// keys land at once unless a name they carry already means another value
/// on the lane they land on. Then nothing is written and the link window
/// asks ONCE, listing what the key window's rename lists for the same
/// question — the row the keys sit on. Joined, the pasted keys take what
/// their names hold there, as one undo; Cancel writes nothing.
///
/// No wait window: keys are no block's (F-566 — 「대상이 한 블록이면
/// 안띄움」, and these reach none).
Future<void> pasteLinkedKeysAskingFirst(
  BuildContext context,
  EditorSessionManager session,
) async {
  final asked = session.keyClipboard.pasteLinked();
  final lane = session.laneVerbs.laneVerbRange;
  if (asked == null || lane == null || !context.mounted) {
    return;
  }
  await offerLink<Set<String>>(
    context,
    asked,
    onConflict: (
      lines: (_) =>
          rowPlaceLines(session.repository.requireProject(), lane.layerId),
      join: (_) => session.keyClipboard.pasteLinked(joinTakenNames: true),
      decline: null,
    ),
  );
}
