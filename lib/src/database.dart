import 'dart:io';

import 'package:jsontree/jsontree.dart';
//import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

// Future<File> dbPath({
//   String basename = "squirrel.sembast.db",
//   bool temp = false,
// }) async {
//   final dir = temp
//       ? await getTemporaryDirectory()
//       : await getApplicationDocumentsDirectory();
//   await dir.create(recursive: true);
//   return File('${dir.path}/$basename');
// }

class SquirrelDb {
  final Database database;

  SquirrelDb._(this.database);

  static final DatabaseFactory _dbFactory = databaseFactoryIo;

  static Future<SquirrelDb> create(File path) async =>
      SquirrelDb._(await _dbFactory.openDatabase(path.path));

  static Future<void> delete(File path) async {
    await _dbFactory.deleteDatabase(path.path);
  }

  Future<void> dispose() => this.database.close();

  //////////////////

  final _records = StoreRef("records");
  final _special = StoreRef("special");

  final _growingIdKey = "growingId";

  Future<int> _readGrowingId(Transaction txn) async {
    final x = await _special.record(_growingIdKey).get(txn);
    if (x==null) {
      return 0;
    } else {
      return x as int;
    }
  }

  Future<void> _writeGrowingId(Transaction txn, int id) async {
    await _special.record(_growingIdKey).put(txn, id);
  }

  Future<int> add(JsonNode data) async {
    late int id;
    await database.transaction((txn) async {
      id = await _readGrowingId(txn);
      if (id>=9223372036854775807) {
        throw Exception("Unexpectedly large id");
      }
      id++;
      await _writeGrowingId(txn, id);
      await _records.record(id).put(txn, data.toJson());
    });
    return id;
  }

  Future<int> length() async {
    return _records.count(this.database);
  }

  Future<void> deleteAll(Iterable<int> keys) async {
    await _records.records(keys).delete(database);
  }

  Future<List<int>> keys() async =>
      (await _records.findKeys(database)).map((e) => e as int).toList();

  Future<dynamic> get(int key) => _records.record(key).get(this.database);

  Future<void> clear() => _records.delete(database);
}
