// In-memory CategoryChoices for the Categorize sheet tests. Invented names.
import 'package:mmogo/autoread/ui/category_choices.dart';

class FakeCategoryChoices implements CategoryChoices {
  FakeCategoryChoices([Iterable<String> names = const ['Food', 'Transport', 'Airtime', 'Rent']]) {
    for (final n in names) {
      _items.add(CategoryChoice(id: 'c${_next++}', name: n));
    }
  }

  final List<CategoryChoice> _items = [];
  int _next = 1;
  int createCalls = 0;

  @override
  Future<List<CategoryChoice>> categories() async => List.unmodifiable(_items);

  @override
  Future<CategoryChoice> create(String name) async {
    createCalls++;
    final v = checkNewCategoryName(name, _items.map((c) => c.name));
    final c = CategoryChoice(id: 'c${_next++}', name: v);
    _items.add(c);
    return c;
  }
}
