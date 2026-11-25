/// §AUTOREAD.CATEGORY_CHOICES — what the Categorize sheet needs from the
/// categories, as a small interface (pure Dart, no widgets).
///
/// The real implementation (a later slice) wraps the same repository the Add
/// screen's "+ New" pill uses, so a category made in the sheet is the same
/// category Add shows. The rules below match Add: the name is trimmed, at
/// most 100 characters (`classificationNameMaxLength`), and a name equal to an
/// existing one, ignoring upper/lower case, is a duplicate.
library;

/// Same limit as `classificationNameMaxLength` in
/// `lib/data/db/classification_dao.dart` (not imported: that file pulls in the
/// database layer).
const int kCategoryNameMaxLength = 100;

/// One category a waiting item can be saved under.
class CategoryChoice {
  final String id;
  final String name;
  const CategoryChoice({required this.id, required this.name});

  @override
  bool operator ==(Object other) => other is CategoryChoice && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);

  @override
  String toString() => 'CategoryChoice($id, $name)';
}

/// Why a new category name was refused.
enum CategoryNameReason { empty, duplicate, tooLong }

/// Thrown by [CategoryChoices.create] for a refused name.
class CategoryNameError implements Exception {
  final CategoryNameReason reason;
  const CategoryNameError(this.reason);

  @override
  String toString() => 'CategoryNameError(${reason.name})';
}

abstract class CategoryChoices {
  /// The categories to choose from, in display order.
  Future<List<CategoryChoice>> categories();

  /// Makes a new category and returns it. Throws [CategoryNameError] for an
  /// empty name (after trim), a name equal to an existing one (ignoring case,
  /// after trim), or a name over [kCategoryNameMaxLength] characters.
  Future<CategoryChoice> create(String name);
}

/// The shared name check, so every implementation refuses the same names.
/// Returns the trimmed name or throws [CategoryNameError].
String checkNewCategoryName(String name, Iterable<String> existing) {
  final v = name.trim();
  if (v.isEmpty) throw const CategoryNameError(CategoryNameReason.empty);
  if (v.length > kCategoryNameMaxLength) {
    throw const CategoryNameError(CategoryNameReason.tooLong);
  }
  final lower = v.toLowerCase();
  if (existing.any((e) => e.trim().toLowerCase() == lower)) {
    throw const CategoryNameError(CategoryNameReason.duplicate);
  }
  return v;
}

/// 0.2.2 Part 1: the Categorize sheet's two groups. [suggested] keeps only the chips that are in [all] (an
/// inactive or deleted category is dropped quietly), in the given order (left to right, most used last), at
/// most 2, no repeats. [rest] is every other category in its own order, so nothing shows twice.
({List<CategoryChoice> suggested, List<CategoryChoice> rest}) splitSuggested(
  List<CategoryChoice> all,
  List<CategoryChoice> chips,
) {
  final byId = {for (final c in all) c.id: c};
  final picked = <CategoryChoice>[];
  for (final c in chips) {
    final known = byId[c.id];
    if (known != null && picked.length < 2 && !picked.any((p) => p.id == c.id)) picked.add(known);
  }
  final ids = {for (final c in picked) c.id};
  return (suggested: picked, rest: [for (final c in all) if (!ids.contains(c.id)) c]);
}
