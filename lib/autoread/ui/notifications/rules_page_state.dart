/// §AUTOREAD.RULES_PAGE_STATE - what the Notifications page remembers for the rule rows while it is open:
/// which Ask first rows were sent to "Categorize later" (they then show as normal rows under To
/// categorize, until the page is left), and the category names (a number to a name for "Record as ...?").
/// The page owns one of these (create, dispose). Autoread build only.
library;

import 'package:flutter/foundation.dart';

import '../category_choices.dart';

class RulesPageState extends ChangeNotifier {
  final Set<String> _later = <String>{};
  Map<int, String> _names = const {};
  bool _disposed = false;

  /// True when this item was sent to Categorize later on this visit.
  bool isLater(String itemId) => _later.contains(itemId);

  void markLater(String itemId) {
    if (_later.add(itemId)) notifyListeners();
  }

  /// The name of category [id], or null while unknown (an Ask first row then shows as a normal row).
  String? nameOf(int id) => _names[id];

  /// Reads the names once. A failure keeps the names empty (Ask first rows show as normal rows).
  Future<void> load(CategoryChoices choices) async {
    try {
      final list = await choices.categories();
      if (_disposed) return;
      _names = {
        for (final c in list)
          if (int.tryParse(c.id) != null) int.parse(c.id): c.name
      };
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
