import 'package:flutter/material.dart';
import 'theme.dart';

/// Renders the light markdown the model actually emits.
///
/// The agent writes things like "**SOP Rule at Stake:** ..." and "* bullet",
/// which were being displayed with the asterisks intact — on the approval
/// screen, which is the one a reviewer reads most closely.
///
/// Deliberately not a markdown package: the output uses a small, predictable
/// subset (bold spans, bullet lines, the occasional heading), and a ~100-line
/// renderer we control styles it to the theme without adding a dependency —
/// the last package pulled in for cosmetics is why this app vendors its font.
/// Anything unrecognised is shown as plain text rather than mangled.
class AgentText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const AgentText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final base = (style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(height: 1.45);

    final blocks = <Widget>[];
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        blocks.add(const SizedBox(height: 8));
        continue;
      }

      final bullet = _bulletPattern.firstMatch(line);
      if (bullet != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 9),
                child: Container(
                  width: 3.5,
                  height: 3.5,
                  decoration: const BoxDecoration(
                    color: AppTheme.textSecondary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Expanded(child: Text.rich(_inline(bullet.group(1)!, base))),
            ],
          ),
        ));
        continue;
      }

      final heading = _headingPattern.firstMatch(line);
      if (heading != null) {
        blocks.add(Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Text(
            heading.group(1)!,
            style: base.copyWith(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
        continue;
      }

      blocks.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text.rich(_inline(line, base)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );
  }
}

// "* item", "- item", "• item" — but NOT "**bold at line start**", which is
// the model's usual way of writing a heading.
final _bulletPattern = RegExp(r'^\s*(?:[-•]|\*(?!\*))\s+(.*)$');
final _headingPattern = RegExp(r'^\s*#{1,6}\s+(.*)$');
final _boldPattern = RegExp(r'\*\*(.+?)\*\*');

/// Splits a line into plain and **bold** spans.
TextSpan _inline(String line, TextStyle base) {
  final spans = <TextSpan>[];
  var index = 0;

  for (final m in _boldPattern.allMatches(line)) {
    if (m.start > index) {
      spans.add(TextSpan(text: line.substring(index, m.start), style: base));
    }
    spans.add(TextSpan(
      text: m.group(1),
      style: base.copyWith(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
    ));
    index = m.end;
  }
  if (index < line.length) {
    spans.add(TextSpan(text: line.substring(index), style: base));
  }
  if (spans.isEmpty) spans.add(TextSpan(text: line, style: base));

  return TextSpan(children: spans);
}

/// The same text flattened to one line, for previews and list rows where a
/// full render would be wrong. Strips the markers rather than showing them.
String plainAgentText(String text) {
  // Heading/bullet patterns are line-anchored, so they have to be applied per
  // line before the text is collapsed.
  final lines = text.split('\n').map((line) {
    final heading = _headingPattern.firstMatch(line);
    if (heading != null) return heading.group(1)!;
    final bullet = _bulletPattern.firstMatch(line);
    if (bullet != null) return bullet.group(1)!;
    return line;
  });

  return lines
      .join(' ')
      .replaceAllMapped(_boldPattern, (m) => m.group(1)!)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
