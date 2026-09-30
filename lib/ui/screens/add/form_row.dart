import 'package:flutter/widgets.dart';

/// §ADD.FORM_ROW — one labelled form row ("Code", "When", "Business"…).
///
/// At the normal phone font size the label sits in a fixed-width column to
/// the left of the content. A fixed column breaks a label mid-word at a large
/// font size ("Busine / ss") and squeezes the content off the row, so from
/// [stackAbove] upwards the label goes on its own line above the content.
class AddFormRow extends StatelessWidget {
  const AddFormRow({
    super.key,
    required this.label,
    required this.labelStyle,
    required this.labelWidth,
    required this.child,
  });

  /// The text scale from which the label stacks above the content.
  static const stackAbove = 1.25;

  final String label;
  final TextStyle labelStyle;

  /// The label column's width when it sits beside the content.
  final double labelWidth;

  /// The row's content (a field, text, or a Row with a button).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= stackAbove;
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: labelStyle),
          const SizedBox(height: 4),
          child,
        ],
      );
    }
    return Row(
      children: [
        SizedBox(width: labelWidth, child: Text(label, style: labelStyle)),
        Expanded(child: child),
      ],
    );
  }
}
