// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:io';

import 'package:synchronized/synchronized.dart';

import 'entry_and_storage.dart';

typedef SendCallback = Future<void> Function(List<dynamic>);

/// Этот объект берет на себя обработку [SquirrelStorage.onModified]. Когда
/// внутри хранилища оказывается более либо равно чем [chunkSize] элементов, все
/// они порционно скармливаются функции [send], а после удачного её запуска -
/// удаляются.
///
/// Инициализируем как-то так:
/// ```dart
///   final sender = SquirrelSender(send: sendToServerFunc);
///   late SquirrelStorage squirrel;
///   squirrel = await SquirrelStorage.create(
///     onModified: () => sender.handleOnModified(squirrel));
/// ```
///
/// Важно, чтобы для конкретного экземпляра [SquirrelStorage] использовался один
/// и тот же объект [SquirrelSender] использовался при всех [onModified]. То
/// есть, не нужно создавать экзепляр [SquirrelSender] внутри обработчка
/// [onModified] каждый раз. Это коварно сработает во всем, кроме [Lock].
class SquirrelSender {
  SquirrelSender({this.chunkSize = 100, required this.send});

  final SendCallback send;
  final int chunkSize;

  // todo test we're not sending in parallel
  final _sendingLock = Lock();

  Future<void> _synchronizedSendAll(SquirrelStorage storage) async {
    await this._sendingLock.synchronized(() async {
      // мы будем отправлять не все элементы внутри storage, а ровно столько,
      // сколько их сейчас. Иначе могло бы случиться, что в ходе отправки
      // появились новые элементы. Например, chunkSize=100, к концу отправки их
      // уже 102. И поэтому мы отправляем чанк размером всего 2 элемента.
      final int maxItemsTotal = await storage.length();
      int gotItemsSum = 0;

      await for (final chunk in storage.popChunks(
          itemsPerChunk: chunkSize, maxItemsTotal: maxItemsTotal)) {
        assert((gotItemsSum += chunk.length) <= maxItemsTotal);
        await this.send(chunk.values.toList(growable: false));
      }
    });
  }

  Future<void> handleSendingTrigger(SquirrelStorage storage) =>
      _synchronizedSendAll(storage);

  void handleModified(SquirrelStorage storage) async {
    // работа этого метода может быть долгой и асинхронной. Предотвращаю
    // параллельные запуски todo протестировать случай, когда send выбрасывает
    // исключение
    if (this._sendingLock.locked) {
      // мы бы могли дождаться окончания lock, и далее обработать наше событие.
      // Но lock может быть занят долго. А событие onModified может происходить
      // очень часто. Становясь сейчас в очередь, мы бы рисковали создать
      // очередь из тысяч элементов. Когда лог освободится, тысячи элементов
      // придется обрабатывать, сильно тормозя приложение. Чтобы избежать
      // будущих тормозов, мы просто игнорируем событие.
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
    squirrel = await Squirrel.create(
      file,
      onModified: () => sender.handleModified(squirrel),
      onSendingTrigger: () => sender.handleSendingTrigger(squirrel),
    );
    return squirrel;
  }
}
