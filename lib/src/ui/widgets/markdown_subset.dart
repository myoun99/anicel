import 'dart:convert' show LineSplitter;

import 'package:flutter/material.dart';

import 'settings_rows.dart' show SettingsSectionHeading;

/// [source] drawn in the small part of Markdown the launch notice's files
/// are written in, and nothing more: `## ` headings, `- ` bullets,
/// paragraphs a blank line apart, and `**bold**` inside a paragraph or a
/// bullet.
///
/// ⚠️A SUBSET ON PURPOSE. The same files go to the public site as they are
/// (`LaunchNoticeSection`), so they are written in what both ends read
/// alike; anything else — a link, a picture, `#` or `###` — is shown as
/// the text it is, which is how a reader finds a file that used it.
class MarkdownSubset extends StatelessWidget {
  const MarkdownSubset(this.source, {super.key, this.leadingHeading = true});

  final String source;

  /// Whether the `## ` heading [source] opens with is drawn — off where a
  /// fold carries it as its own words ([leadingHeadingOf]).
  final bool leadingHeading;

  /// The `## ` heading [source] opens with, or null when it opens with
  /// anything else.
  static String? leadingHeadingOf(String source) {
    final blocks = _blocksOf(source);
    return blocks.isNotEmpty && blocks.first.kind == _BlockKind.heading
        ? blocks.first.text
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final all = _blocksOf(source);
    final blocks =
        !leadingHeading &&
            all.isNotEmpty &&
            all.first.kind == _BlockKind.heading
        ? all.sublist(1)
        : all;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) SizedBox(height: _gapBetween(blocks[i - 1], blocks[i])),
          _viewOf(blocks[i]),
        ],
      ],
    );
  }

  /// A list's items sit closer to each other than to what is around them.
  static double _gapBetween(_Block above, _Block below) =>
      above.kind == _BlockKind.bullet && below.kind == _BlockKind.bullet
      ? 4
      : 8;

  static Widget _viewOf(_Block block) => switch (block.kind) {
    // The words above a group, as the settings sections set theirs.
    _BlockKind.heading => SettingsSectionHeading(label: block.text),
    _BlockKind.bullet => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•'),
        const SizedBox(width: 6),
        Expanded(child: Text.rich(TextSpan(children: _spansOf(block.text)))),
      ],
    ),
    _BlockKind.paragraph => Text.rich(
      TextSpan(children: _spansOf(block.text)),
    ),
  };
}

enum _BlockKind { heading, bullet, paragraph }

/// A heading, a bullet or a paragraph, and its words.
class _Block {
  _Block(this.kind, String firstLine) : _lines = [firstLine];

  final _BlockKind kind;
  final List<String> _lines;

  /// A line that carries on the bullet or paragraph above it — joined with
  /// a space, as Markdown joins the lines of one paragraph.
  void carryOn(String line) => _lines.add(line);

  String get text => _lines.join(' ');
}

List<_Block> _blocksOf(String source) {
  final blocks = <_Block>[];
  // The bullet or paragraph a next line would carry on; a blank line or a
  // heading closes it.
  _Block? open;
  for (final line in const LineSplitter().convert(source)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      open = null;
    } else if (trimmed.startsWith('## ')) {
      blocks.add(_Block(_BlockKind.heading, trimmed.substring(3)));
      open = null;
    } else if (trimmed.startsWith('- ')) {
      blocks.add(open = _Block(_BlockKind.bullet, trimmed.substring(2)));
    } else if (open != null) {
      open.carryOn(trimmed);
    } else {
      blocks.add(open = _Block(_BlockKind.paragraph, trimmed));
    }
  }
  return blocks;
}

/// [text] with each `**…**` run in bold. A marker left without its pair is
/// a literal, as it is in Markdown.
List<TextSpan> _spansOf(String text) {
  final parts = text.split('**');
  // An even count of parts is an odd count of markers: the last one has no
  // pair.
  final paired = parts.length.isOdd ? parts.length : parts.length - 1;
  return [
    for (var i = 0; i < paired; i++)
      if (parts[i].isNotEmpty)
        TextSpan(text: parts[i], style: i.isOdd ? _bold : null),
    if (paired < parts.length) TextSpan(text: '**${parts.last}'),
  ];
}

const _bold = TextStyle(fontWeight: FontWeight.bold);
