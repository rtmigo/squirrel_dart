// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:jsontree/jsontree.dart';
import 'package:meta/meta.dart';
import 'package:slugid/slugid.dart';
import 'package:squirrel/src/database.dart';
import 'package:squirrel/src/mono_now.dart';

typedef SquirrelChunk = UnmodifiableMapView<int, dynamic>;
typedef VoidCallback = FutureOr<void> Function();

class SquirrelEntry {
  final SquirrelDb _db;

  final String? id;

  @protected
  final VoidCallback? onModified;

  @protected
  final VoidCallback? onSendingTrigger;

  SquirrelEntry(
      {required SquirrelDb db,
      required this.id,
      required this.onModified,
      required this.onSendingTrigger})
      : _db = db;

  Future<String> _putRecordToDb(String? parentId, JsonNode data) async {
    jsonEncode(data); // just checking the data can be encoded
    final String slugid = Slugid.v4().toString();
    final rec = {
      'I': slugid.jsonNode,
      'T': monoTime.now().microsecondsSinceEpoch.jsonNode,
      'P': parentId == null ? JsonNull() : parentId.jsonNode,
      'D': data
    }.jsonNode;
    //jsonEncode(object)
    await this._db.writeRecord(rec);
    this.onModified?.call();

    return slugid;
  }

  // формат примерно такой:
  //    recordUuid: {
  //      'T': microsecondsSinceEpoch,
  //      'P': parentRecordId,
  //      'D': dynamicData
  //    }
  //
  // У каждой записи recordUuid - абсолютно уникальный идентификатор. Так что
  // даже когда такие записи соберутся на сервере, они по-прежнему будут
  // идентифицироваться теми же uuid.
  //
  // 'p' позволяет задавать "родительские" узлы (контексты). Скорее всего, при
  // запуске приложения я задаю контекст. Например такой:
  //
  // contextRecordUuid: {
  //    'T': microsecondsSinceEpoch,
  //    'P': null,
  //    'D' {
  //      'userName': ...,
  //      'androidVersion': ...,
  //      'appVersion': ...,
  //    }
  //
  // Остальные события далее будут ссылаться на этот контекст (по значению
  // contextRecordUuid), но не дублировать данные.

  Future<SquirrelEntry> add(JsonNode data) async {
    final String id = await this._putRecordToDb(this.id, data);
    return SquirrelEntry(
        db: this._db,
        id: id,
        onModified: this.onModified,
        onSendingTrigger: this.onSendingTrigger);
  }

  /// Calls [onSendingTrigger] handler.
  FutureOr<void> triggerSending() {
    if (this.onSendingTrigger != null) {
      return this.onSendingTrigger?.call();
    }
  }
}

class SquirrelStorage extends SquirrelEntry {
  SquirrelStorage._(SquirrelDb box,
      {VoidCallback? onModified, VoidCallback? onSendingTrigger})
      : super(
            db: box,
            id: null,
            onModified: onModified,
            onSendingTrigger: onSendingTrigger);

  static Future<SquirrelStorage> create(
    File file, {
    VoidCallback? onModified,
    VoidCallback? onSendingTrigger,
    //bool temp = false
  }) async {
    return SquirrelStorage._(await SquirrelDb.create(file),
        // Hive.openBox(boxName),
        onModified: onModified,
        onSendingTrigger: onSendingTrigger);
  }

  Stream<MapEntry<int, dynamic>> readEntries() async* {
    for (final k in (await this._db.readKeys())..sort()) {
      yield MapEntry<int, dynamic>(k, await this._db.read(k));
    }
  }

  Future<void> clear() async {
    await this._db.deleteAll();
  }

  Future<void> close() => this._db.database.close();

  Future<int> length() => this._db.readRecordsCount();

  Future<SquirrelChunk> readChunk([int n = 100]) async {
    //  .readEntries().take(n).readToList()
    return UnmodifiableMapView(
        Map.fromEntries(await this._db.readFirstRecords(n)));
  }

  Future<void> deleteChunk(SquirrelChunk chunk) async {
    return this._db.deleteByKeys(chunk.keys);
  }

  /// Возвращает данные порциями. Каждый раз, когда мы запрашиваем новый
  /// элемент, все данные предыдущего элемента удаляются из базы.
  ///
  /// Перебрав все доступные элементы мы обычно запрашиваем "следующий" элемент,
  /// но получаем сигнал окончания итерации - прямо или косвенно. То есть,
  /// запрос происходит и после последнего элемента. А значит, если прокрутить
  /// полный цикл, вроде `takeChunks().toList()`, то в базе не останется
  /// буквально ни одного элемента.
  ///
  /// Метод может использоваться, чтобы выгрузить все данные из локальной базы в
  /// какое-то другое место, например, сервер.
  ///
  /// ```dart
  /// await for (var chunk in db.takeChunks()) {
  ///   await sendToServer(chunk);
  /// }
  /// ```
  Stream<SquirrelChunk> readChunks(
      {int itemsPerChunk = 100, int? maxItemsTotal}) async* {
    int itemsTaken = 0;
    for (;;) {
      int maxPerNextChunk = itemsPerChunk;
      if (maxItemsTotal != null) {
        maxPerNextChunk = min(maxPerNextChunk, maxItemsTotal - itemsTaken);
      }

      final chunk = await this.readChunk(maxPerNextChunk);
      if (chunk.isEmpty) {
        break;
      }
      yield chunk;
      itemsTaken += chunk.length;
      await this.deleteChunk(chunk);
    }
  }

  @Deprecated(
      "Use object methods directly (squirrel.add instead squirrel.root.add)") // 2022-01
  SquirrelEntry get root => this;
}

typedef Squirrel = SquirrelStorage;
