extension StreamExt<T> on Stream<T> {
  Future<List<T>> readToList() async {
    final lst = <T>[];
    await for (final x in this) {
      lst.add(x);
    }
    return lst;
  }
}