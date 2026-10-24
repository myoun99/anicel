import 'package:flutter/widgets.dart';

/// A field's controller over [text] with ALL of it selected — what a field
/// that edits a value already there opens on, so typing REPLACES the old
/// value: renaming is nearly always a replacement, and reaching for ctrl+A
/// first was friction.
///
/// 🗣️I-24-open-entry (유저 2026-10-01): 「기존 이름 편집같은건 이름편집열때
/// 기존이름있고, 그거 선택된상태로 있잖아. 그거 그대로 재사용해서 통일. 길이
/// 설정도 기존 길이 띄워둔다는뜻」 — the prompt windows, the inline number and
/// the count window open on this one controller. ↩️The first two spelled it
/// out each.
TextEditingController selectedTextController(String text) =>
    TextEditingController.fromValue(
      TextEditingValue(
        text: text,
        selection: TextSelection(baseOffset: 0, extentOffset: text.length),
      ),
    );
