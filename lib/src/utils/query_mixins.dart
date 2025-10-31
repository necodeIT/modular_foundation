import 'package:modular_foundation/modular_foundation.dart';

mixin QueryByIdMixin<T, ID> on Repo<List<T>> {
  Future<T?> queryById(ID id) async {
    log('Querying item by ID: $id');

    final allItems = state.requireData;

    try {
      return allItems.firstWhere((item) => getId(item) == id);
    } catch (e) {
      return null;
    }
  }

  ID getId(T item);
}
