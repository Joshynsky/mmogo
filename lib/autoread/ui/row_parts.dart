/// §AUTOREAD.ROW_PARTS - two small pieces the Notifications lists share: the
/// section heading and the wrapper that scrolls a tapped row into view.
/// Autoread build only.
library;

import 'package:flutter/material.dart';


/// A section heading, with an optional widget beside it (the Parse all bar).
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: trailing == null
          ? title
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [title, trailing!],
            ),
    );
  }
}

/// Wraps the focused row: after the first frame it scrolls into view. No
/// outline or highlight.
class RowFocus extends StatefulWidget {
  const RowFocus({super.key, required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  State<RowFocus> createState() => _RowFocusState();
}

class _RowFocusState extends State<RowFocus> {
  @override
  void initState() {
    super.initState();
    if (widget.on) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Scrollable.ensureVisible(context, alignment: 0.3);
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
