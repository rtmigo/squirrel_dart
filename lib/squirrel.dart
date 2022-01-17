// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:collection';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:slugid/slugid.dart';


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

class SquirrelEntry {
  final Box box;
  final String? id;
  final VoidCallback? onModified;

  SquirrelEntry({required this.box, required this.id, this.onModified});

  Future<String> _putRecordToDb(String? parentId, dynamic data) async {
    final String id = Slugid.v4().toString();
    final rec = {'I': id, 'T': _monoTime.now().microsecondsSinceEpoch, 'P': parentId, 'D': data};
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


  Future<SquirrelEntry> add(Map<String, dynamic> data) async {
    String id = await this._putRecordToDb(this.id, data);
    return SquirrelEntry(box: this.box, id: id, onModified: this.onModified);
  }

  @Deprecated("Use squirrel.add()")  // since 2022-01
  Future<String> addEvent(Map<String, dynamic> data) async {
    return (await add(data)).id!;
  }

  @Deprecated("Use context = squirrel.add()")  // since 2022-01
  Future<SquirrelEntry> addContext(Map<String, dynamic> data) {
    return add(data);
    //final subContextId = await this.addEvent(data); //this._putRecordToDb(null, data);
    //return SquirrelEntry(storage: this.storage, contextId: subContextId);
  }
}

class SquirrelStorage extends SquirrelEntry {
  SquirrelStorage._(Box box, {VoidCallback? onModified}): super(box: box, id: null, onModified: onModified);

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

      final chunk = this.getChunk(maxPerNextChunk);
      if (chunk.isEmpty) {
        break;
      }
      yield chunk;
      itemsTaken += chunk.length;
      this.removeChunk(chunk);
    }
  }

  @Deprecated("Use object methods directly (squirrel.add instead squirrel.root.add)")  // 2022-01
  SquirrelEntry get root => this;
}

typedef Squirrel = SquirrelStorage;

final _monoTime = _MonotonicNow();



class _IgnoreParallelCalls {
  bool _running = false;
  Future<void> callAsync(Future<void> Function() func) async {
    if (_running) {
      return;
    }
    try {
      _running = true;
      await func();
    } finally {
      _running = false;
    }
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


  final _ignoreParallel = _IgnoreParallelCalls();
  
  void handleOnModified(SquirrelStorage storage) async {
    // работа этого метода может быть долгой и асинхронной. Предотвращаю параллельные запуски
    // todo протестировать случай, когда send выбрасывает исключение
    await _ignoreParallel.callAsync(() async {
      if (storage.length >= chunkSize) {
        // мы будем отправлять не все элементы внутри storage, а ровно столько, сколько их сейчас.
        // Иначе могло бы случиться, что в ходе отправки появились новые элементы. Например,
        // chunkSize=100, к концу отправки их уже 102. И поэтому мы отправляем чанк размером всего
        // 2 элемента.
        int maxItemsTotal = storage.length;
        int gotItemsSum = 0;

        await for (final chunk
        in storage.takeChunks(itemsPerChunk: chunkSize, maxItemsTotal: maxItemsTotal)) {
          assert((gotItemsSum += chunk.length) <= maxItemsTotal);
          await this.send(chunk.values.toList(growable: false));
        }
    }});
  }
}

