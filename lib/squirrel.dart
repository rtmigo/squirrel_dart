// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:slugid/slugid.dart';
import 'package:synchronized/synchronized.dart';

class _MonotonicNow {
  final DateTime _startTime = DateTime.now().toUtc();
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Возвращает время, которым должно быть датировано событие, если оно произошло "прямо сейчас".
  /// В отличие от `DateTime.now()`, тут мы полагаемся на [Stopwatch] и поэтому надеемся
  /// на монотонное возрастание.
  DateTime now() {
    return this._startTime.add(this._stopwatch.elapsed);
  }
}


typedef SquirrelChunk = UnmodifiableMapView<int, dynamic>;
typedef VoidCallback = void Function();

class SquirrelStorage {
  SquirrelStorage._(this.box, {this.onModified}) {
    this.root = SquirrelContext(storage: this, contextId: null);
  }

  final VoidCallback? onModified;

  Box box;

  /// Перед вызовом этого метода нужно еще сделать `Hive.init` или `await Hive.initFlutter`.
  ///
  /// Здесь это не делается автоматически, поскольку база Hive едина для всего приложения
  /// (и в этом плане у меня выбора нет). Ее стоит инициализировать отдельно и осознанно:
  /// передавая ей путь, например.
  static Future<SquirrelStorage> create(
      {String boxName = 'squirrel', VoidCallback? onModified}) async {
    return SquirrelStorage._(await Hive.openBox(boxName), onModified: onModified);
  }

  Iterable<MapEntry<int, dynamic>> entries() sync* {
    for (final k in this.box.keys) {
      yield MapEntry<int, dynamic>(k, this.box.get(k));
    }
  }

  Future<void> clear() async {
    await this.box.clear();
  }

  int get length {
    return this.box.length;
  }

  SquirrelChunk getChunk([int n = 100]) {
    return UnmodifiableMapView(Map.fromEntries(this.entries().take(n)));
  }

  Future<void> removeChunk(SquirrelChunk chunk) {
    return this.box.deleteAll(chunk.keys);
  }

  /// Возвращает данные порциями. Каждый раз, когда мы запрашиваем новый элемент, все данные
  /// предыдущего элемента удаляются из базы.
  ///
  /// Перебрав все доступные элементы мы обычно запрашиваем "следующий" элемент, но получаем сигнал
  /// окончания итерации - прямо или косвенно. То есть, запрос происходит и после последнего
  /// элемента. А значит, если прокрутить полный цикл, вроде `takeChunks().toList()`, то в базе
  /// не останется буквально ни одного элемента.
  ///
  /// Метод может использоваться, чтобы выгрузить все данные из локальной базы в какое-то другое
  /// место, например, сервер.
  ///
  /// ```dart
  /// await for (var chunk in db.takeChunks()) {
  ///   await sendToServer(chunk);
  /// }
  /// ```
  Stream<SquirrelChunk> takeChunks({int itemsPerChunk = 100, int? maxItemsTotal}) async* {
    int itemsTaken = 0;
    for (;;) {
      int maxPerNextChunk = itemsPerChunk;
      if (maxItemsTotal != null) {
        maxPerNextChunk = min(maxPerNextChunk, maxItemsTotal - itemsTaken);
      }
      //print("max $maxPerNextChunk");

      final chunk = this.getChunk(maxPerNextChunk);
      if (chunk.isEmpty) {
        break;
      }
      yield chunk;
      itemsTaken += chunk.length;
      this.removeChunk(chunk);
    }
  }

  late final SquirrelContext root;
}

final _monoTime = _MonotonicNow();

class SquirrelContext {
  Box get box => storage.box;
  final String? contextId;
  final SquirrelStorage storage;

  SquirrelContext({required this.storage, required this.contextId});

  Future<String> _putRecordToDb(String? parentId, dynamic data) async {
    final String id = Slugid.v4().toString();
    final rec = {'I': id, 'T': _monoTime.now().microsecondsSinceEpoch, 'P': parentId, 'D': data};
    await this.box.add(rec);
    this.storage.onModified?.call();

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

  Future<String> addEvent(Map<String, dynamic> data) {
    return this._putRecordToDb(this.contextId, data);
  }

  Future<SquirrelContext> addContext(Map<String, dynamic> data) async {
    final subContextId = await this.addEvent(data); //this._putRecordToDb(null, data);
    return SquirrelContext(storage: this.storage, contextId: subContextId);
  }
}

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

  final Future<void> Function(List) send;
  final int chunkSize;
  final _lock = Lock();

  void handleOnModified(SquirrelStorage storage) async {
    if (storage.length >= chunkSize) {
      // мы будем отправлять не все элементы внутри storage, а ровно столько, сколько их сейчас.
      // Иначе могло бы случиться, что в ходе отправки появились новые элементы. Например,
      // chunkSize=100, к концу отправки их уже 102. И поэтому мы отправляем чанк размером всего
      // 2 элемента.
      int maxItemsTotal = storage.length;
      int gotItemsSum = 0;
      await _lock.synchronized(() async {
        await for (final chunk
            in storage.takeChunks(itemsPerChunk: chunkSize, maxItemsTotal: maxItemsTotal)) {
          assert((gotItemsSum += chunk.length) <= maxItemsTotal);
          await this.send(chunk.values.toList(growable: false));
        }
      });
    }
  }
}
