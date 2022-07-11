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
import 'package:synchronized/synchronized.dart';

const _defaultBoxName = 'squirrel';

class _MonotonicNow {
  final DateTime _startTime = DateTime.now().toUtc();
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Возвращает время, которым должно быть датировано событие, если оно
  /// произошло "прямо сейчас". В отличие от `DateTime.now()`, тут мы полагаемся
  /// на [Stopwatch] и поэтому надеемся на монотонное возрастание.
  DateTime now() {
    return this._startTime.add(this._stopwatch.elapsed);
  }
}

typedef SquirrelChunk = UnmodifiableMapView<int, dynamic>;
typedef VoidCallback = FutureOr<void> Function();

class SquirrelEntry {
  final SquirrelDb box;

  final String? id;

  @protected
  final VoidCallback? onModified;

  @protected
  final VoidCallback? onSendingTrigger;

  SquirrelEntry(
      {required this.box,
      required this.id,
      required this.onModified,
      required this.onSendingTrigger});

  Future<String> _putRecordToDb(String? parentId, JsonNode data) async {
    jsonEncode(data); // just checking the data can be encoded
    final String id = Slugid.v4().toString();
    final rec = {
      'I': id.jsonNode,
      'T': _monoTime.now().microsecondsSinceEpoch.jsonNode,
      'P': parentId == null ? JsonNull() : parentId.jsonNode,
      'D': data
    }.jsonNode;
    //jsonEncode(object)
    await this.box.add(rec);
    this.onModified?.call();

    return id;
  }

  // формат примерно такой:
  //    recordUuid: {
  //      'T': microsecondsSinceEpoch,
  //      'P': parentRecordId,
  //      'D': dynamicData
  //    }
  //
  // У каждой записи recordUuid - абсолютно уникальный идентификатор. Так что даже когда такие
  // записи соберутся на сервере, они по-прежнему будут идентифицироваться теми же uuid.
  //
  // 'p' позволяет задавать "родительские" узлы (контексты). Скорее всего, при запуске приложения
  // я задаю контекст. Например такой:
  // contextRecordUuid: {
  //    'T': microsecondsSinceEpoch,
  //    'P': null,
  //    'D' {
  //      'userName': ...,
  //      'androidVersion': ...,
  //      'appVersion': ...,
  //    }
  //
  // Остальные события далее будут ссылаться на этот контекст (по значению contextRecordUuid), но
  // не дублировать данные.

  Future<SquirrelEntry> add(JsonNode data) async {
    final String id = await this._putRecordToDb(this.id, data);
    return SquirrelEntry(
        box: this.box,
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

// @Deprecated("Use squirrel.add()") // since 2022-01
// Future<String> addEvent(Map<String, dynamic> data) async {
//   return (await add(data)).id!;
// }
//
// @Deprecated("Use context = squirrel.add()") // since 2022-01
// Future<SquirrelEntry> addContext(Map<String, dynamic> data) {
//   return add(data);
//   //final subContextId = await this.addEvent(data); //this._putRecordToDb(null, data);
//   //return SquirrelEntry(storage: this.storage, contextId: subContextId);
// }
}

extension StreamExt<T> on Stream<T> {
  Future<List<T>> readToList() async {
    final lst = <T>[];
    await for (final x in this) {
      lst.add(x);
    }
    return lst;
  }
}

class SquirrelStorage extends SquirrelEntry {
  SquirrelStorage._(SquirrelDb box,
      {VoidCallback? onModified, VoidCallback? onSendingTrigger})
      : super(
            box: box,
            id: null,
            onModified: onModified,
            onSendingTrigger: onSendingTrigger);

  /// Перед вызовом этого метода нужно еще сделать `Hive.init` или `await
  /// Hive.initFlutter`.
  ///
  /// Здесь это не делается автоматически, поскольку база Hive едина для всего
  /// приложения (и в этом плане у меня выбора нет). Ее стоит инициализировать
  /// отдельно и осознанно: передавая ей путь, например.
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

  Stream<MapEntry<int, dynamic>> entries() async* {
    for (final k in await this.box.keys()) {
      final dynamic entry = await this.box.get(k);
      yield MapEntry<int, dynamic>(k, entry);
    }
  }

  Future<void> clear() async {
    await this.box.clear();
  }

  Future<void> close() => this.box.database.close();

  Future<int> length() => this.box.length();

  Future<SquirrelChunk> getChunk([int n = 100]) async {
    // final lst = <MapEntry<String, dynamic>>[];
    // await for (final x in this.entries().take(n)) {
    //   lst.add(x);
    // }
    return UnmodifiableMapView(
        Map.fromEntries(await this.entries().take(n).readToList()));
  }

  Future<void> removeChunk(SquirrelChunk chunk) async {
    return this.box.deleteAll(chunk.keys);
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
  Stream<SquirrelChunk> takeChunks(
      {int itemsPerChunk = 100, int? maxItemsTotal}) async* {
    int itemsTaken = 0;
    for (;;) {
      int maxPerNextChunk = itemsPerChunk;
      if (maxItemsTotal != null) {
        maxPerNextChunk = min(maxPerNextChunk, maxItemsTotal - itemsTaken);
      }

      final chunk = await this.getChunk(maxPerNextChunk);
      if (chunk.isEmpty) {
        break;
      }
      yield chunk;
      itemsTaken += chunk.length;
      await this.removeChunk(chunk);
    }
  }

  @Deprecated(
      "Use object methods directly (squirrel.add instead squirrel.root.add)") // 2022-01
  SquirrelEntry get root => this;
}

typedef Squirrel = SquirrelStorage;

final _monoTime = _MonotonicNow();

typedef SendCallback = Future<void> Function(List<dynamic>);

/// Этот объект берет на себя обработку [SquirrelStorage.onModified]. Когда внутри хранилища
/// оказывается более либо равно чем [chunkSize] элементов, все они порционно скармливаются
/// функции [send], а после удачного её запуска - удаляются.
///
/// Инициализируем как-то так:
/// ```dart
///   final sender = SquirrelSender(send: sendToServerFunc);
///   late SquirrelStorage squirrel;
///   squirrel = await SquirrelStorage.create(
///     onModified: () => sender.handleOnModified(squirrel));
/// ```
///
/// Важно, чтобы для конкретного экземпляра [SquirrelStorage] использовался один и тот же объект
/// [SquirrelSender] использовался при всех [onModified]. То есть, не нужно создавать экзепляр
/// [SquirrelSender] внутри обработчка [onModified] каждый раз. Это коварно сработает во всем,
/// кроме [Lock].
class SquirrelSender {
  SquirrelSender({this.chunkSize = 100, required this.send});

  final SendCallback send;
  final int chunkSize;

  // todo test we're not sending in parallel
  final _sendingLock = Lock();

  Future<void> _synchronizedSendAll(SquirrelStorage storage) async {
    await this._sendingLock.synchronized(() async {
      // мы будем отправлять не все элементы внутри storage, а ровно столько, сколько их сейчас.
      // Иначе могло бы случиться, что в ходе отправки появились новые элементы. Например,
      // chunkSize=100, к концу отправки их уже 102. И поэтому мы отправляем чанк размером всего
      // 2 элемента.
      final int maxItemsTotal = await storage.length();
      int gotItemsSum = 0;

      await for (final chunk in storage.takeChunks(
          itemsPerChunk: chunkSize, maxItemsTotal: maxItemsTotal)) {
        assert((gotItemsSum += chunk.length) <= maxItemsTotal);
        await this.send(chunk.values.toList(growable: false));
      }
    });
  }

  Future<void> handleSendingTrigger(SquirrelStorage storage) =>
      _synchronizedSendAll(storage);

  void handleModified(SquirrelStorage storage) async {
    // работа этого метода может быть долгой и асинхронной. Предотвращаю параллельные запуски
    // todo протестировать случай, когда send выбрасывает исключение
    if (this._sendingLock.locked) {
      // мы бы могли дождаться окончания lock, и далее обработать наше событие.
      // Но lock может быть занят долго. А событие onModified может происходить очень часто.
      // Становясь сейчас в очередь, мы бы рисковали создать очередь из тысяч элементов.
      // Когда лог освободится, тысячи элементов придется обрабатывать, сильно тормозя приложение.
      // Чтобы избежать будущих тормозов, мы просто игнорируем событие.
      return;
    }

    if (await storage.length() >= chunkSize) {
      await this._synchronizedSendAll(storage);
    }
  }

  /// Creates a [Squirrel] instance with handlers assigned to a [SquirrelSender].
  static Future<Squirrel> create(
      File file,
      SendCallback sendToServer,
      ) async {
    // todo test this function
    final sender = SquirrelSender(send: sendToServer);
    late Squirrel squirrel;
    squirrel = await Squirrel.create(file,
        onModified: () => sender.handleModified(squirrel),
        onSendingTrigger: () => sender.handleSendingTrigger(squirrel),
        //boxName: boxName // todo test this param
        );
    return squirrel;
  }
}
