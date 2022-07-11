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

  Future<List<MapEntry<int, dynamic>>> readOldestRecords(int n) async {
    // todo maybe we can just iterate records (and keys will be sorted?)
    late List<int> keys;
    late List<dynamic> records;
    await this.database.transaction((transaction) async {
      keys = ((await readKeys(transaction))..sort())
          .take(n)
          .toList(growable: false);
      records = await _records.records(keys).get(this.database);
    });
    
    assert(keys.length == records.length);
    final result = <MapEntry<int, dynamic>>[];
    for (int i = 0; i < keys.length; ++i) {
      result.add(MapEntry(keys[i], records[i]));
    }
    return result;
  }

  Future<dynamic> read(int key) => _records.record(key).get(this.database);

  Future<void> deleteAll() => _records.delete(database);
}
