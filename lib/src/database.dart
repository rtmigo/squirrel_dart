import 'dart:io';

import 'package:jsontree/jsontree.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

class SquirrelDb {
  final Database database;

  SquirrelDb._(this.database);

  static final DatabaseFactory _dbFactory = databaseFactoryIo;

  static Future<SquirrelDb> open(File path) async =>
      SquirrelDb._(await _dbFactory.openDatabase(path.path));

  static Future<void> delete(File path) async {
    await _dbFactory.deleteDatabase(path.path);
  }

  Future<void> close() => this.database.close();

  final _records = StoreRef("records");

  Future<int> writeRecord(JsonNode data) async {
    // "If no key is provided, the object is inserted with an
    // auto-increment value"
    return await _records.add(database, data.toJson()) as int;
  }

  Future<int> readRecordsCount() async {
    return _records.count(this.database);
  }

  Future<void> deleteByKeys(Iterable<int> keys) async {
    await _records.records(keys).delete(database);
  }

  Future<List<int>> readKeys([Transaction? txn]) async =>
      (await _records.findKeys(txn ?? database)).map((e) => e as int).toList();

  Future<List<MapEntry<int, dynamic>>> readOldestRecords({int? limit}) async =>
      // сортируем ключи по возрастанию, берем limit первых элементов
      (await this._records.find(database,
              finder: Finder(
                  sortOrders: [SortOrder(Field.key, true)], limit: limit)))
          // мапим найденное в список
          .map((RecordSnapshot<dynamic, dynamic> snapshot) =>
              MapEntry(snapshot.key as int, snapshot.value))
          .toList(growable: false);

  Future<dynamic> read(int key) => _records.record(key).get(this.database);

  Future<void> deleteAll() => _records.delete(database);
}