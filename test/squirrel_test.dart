// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:hive/hive.dart';
import 'package:squirrel/squirrel.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    Hive.init(Directory.systemTemp.createTempSync().path);
  });

  tearDown(() {
    Hive.close();
  });

  test("first", () async {
    SquirrelStorage sq = await SquirrelStorage.create(boxName: 'test1');
    expect(sq.length, 0);

    await sq.root.addEvent({'event': 'a'});
    await sq.root.addEvent({'event': 'b'});
    var entries = sq.entries().toList();
    expect(entries.length, 2);

    for (final e in entries) {
      expect(e.key, isA<int>());
      expect(e.value['I'], isA<String>());
      expect(e.value['I'].length, '3cka5hc3QRCTB61W8dDoag'.length);
      expect(e.value['T'], isA<int>());
      expect(e.value['P'], isNull);
    }

    //entries.sort((a,b) => a.value["T"].compareTo(b.value['T']));

    // данные конкретно такие
    expect(entries[0].value['D'], {'event': 'a'});
    expect(entries[1].value['D'], {'event': 'b'});

    // время идет по возрастанию
    expect(entries[0].value['T'], lessThan(entries[1].value['T']));
  });

  test("events are incrementing", () async {
    SquirrelStorage database = await SquirrelStorage.create(boxName: 'test');
    for (int i = 0; i < 5; ++i) {
      database.root.addEvent({"x": i});
    }

    expect(database.entries().map((e) => e.value['D']['x']).toList(), [0, 1, 2, 3, 4]);
  });

  test("subcontexts", () async {
    SquirrelStorage sq = await SquirrelStorage.create(boxName: 'test2');
    expect(sq.length, 0);

    final context = await sq.root.addContext({'context': 'Ночь. Улица. Фонарь. Аптека.'});

    await context.addEvent({'event': 'a'});
    await context.addEvent({'event': 'b'});
    final entries = sq.entries().toList();
    expect(entries.length, 3);

    // контекст содержит данные
    expect(entries[0].value['I'], context.contextId);
    expect(entries[0].value['P'], null);
    expect(entries[0].value['D'], {'context': 'Ночь. Улица. Фонарь. Аптека.'});

    // события ссылаются на контекст
    expect(entries[1].value['P'], context.contextId);
    expect(entries[2].value['P'], context.contextId);
  });

  test("chunk get remove", () async {
    SquirrelStorage sq = await SquirrelStorage.create(boxName: 'test3');
    expect(sq.length, 0);

    for (int i = 0; i < 17; ++i) {
      sq.root.addEvent({"x": i});
    }

    // убедимся, что данные не удаляются, когда мы просто get
    for (int i = 0; i < 3; ++i) {
      final stub = sq.getChunk(10);
      expect(stub.length, 10);
    }

    final chunk1 = sq.getChunk(10);
    expect(chunk1.length, 10);
    await sq.removeChunk(chunk1);

    final chunk2 = sq.getChunk(10);
    expect(chunk2.length, 7);
    await sq.removeChunk(chunk2);

    final chunk3 = sq.getChunk(10);
    expect(chunk3.length, 0);
    await sq.removeChunk(chunk3);
  });

  test("onModified", () async {
    int calls = 0;
    SquirrelStorage db = await SquirrelStorage.create(boxName: 'test3', onModified: () => ++calls);

    //db.onModified.(() { ++calls; });
    await db.root.addEvent({'a': 1});
    await db.root.addEvent({'b': 5});
    expect(calls, 2);
    await db.root.addContext({'b': 5});
    await db.root.addEvent({'b': 5});
    await db.root.addContext({'x': 55});
    expect(calls, 5);
  });

  test("takeChunks list", () async {
    SquirrelStorage database = await SquirrelStorage.create(boxName: 'test');
    expect(database.length, 0);

    for (int i = 0; i < 17; ++i) {
      await database.root.addEvent({"x": i});
    }

    //await Future.delayed(const Duration(milliseconds: 500));

    expect(database.length, 17);

    final chunks = await database.takeChunks(itemsPerChunk: 10).toList();
    expect(chunks.length, 2);
    expect(chunks[0].length, 10);
    expect(chunks[1].length, 7);

    expect(database.length, 0);
  });

  test("takeChunks maxTotal", () async {
    SquirrelStorage database = await SquirrelStorage.create(boxName: 'test');
    expect(database.length, 0);

    for (int i = 0; i < 50; ++i) {
      await database.root.addEvent({"x": i});
    }

    expect(database.length, 50);

    final chunks = await database.takeChunks(itemsPerChunk: 10, maxItemsTotal: 42).toList();
    expect(chunks.length, 5);
    int sum = 0;
    for (var c in chunks) {
      sum += c.length;
    }
    expect(sum, 42);

    expect(chunks[0].length, 10);
    expect(chunks[1].length, 10);
    expect(chunks[2].length, 10);
    expect(chunks[3].length, 10);
    expect(chunks[4].length, 2);

    expect(database.length, 8);
  });

  test("takeChunks removes only after next chunk is requested", () async {
    SquirrelStorage database = await SquirrelStorage.create(boxName: 'test');
    expect(database.length, 0);

    for (int i = 0; i < 27; ++i) {
      database.root.addEvent({"x": i});
    }

    int i = 0;
    await for (final chunk in database.takeChunks(itemsPerChunk: 10)) {
      switch (i) {
        case 0:
          expect(database.length, 27);
          expect(chunk.length, 10);
          break;
        case 1:
          expect(database.length, 17);
          expect(chunk.length, 10);
          break;
        case 2:
          expect(database.length, 7);
          expect(chunk.length, 7);
          break;
        default:
          fail("oops");
      }

      ++i;
    }
    expect(database.length, 0);
    expect(i, 3);
  });

  test("SquirrelSender", () async {
    int sent = 0;
    int calls = 0;
    late SquirrelStorage sq;

    final sender = SquirrelSender(
        send: (chunk) async {
          //print("CALL");
          calls++;
          sent += chunk.length;
        },
        chunkSize: 10);
    late SquirrelStorage database;
    database = await SquirrelStorage.create(
        boxName: 'test', onModified: () => sender.handleOnModified(database));

    for (int i = 0; i < 55; ++i) {
      await database.root.addEvent({'data': i});
    }
    // поскольку все асинхронно, то на константы я не рассчитываю
    // (хоть и получаю одни и те же значения, это может быть случайностью)
    expect(calls, 5);
    expect(sent, 50);
  });
}
