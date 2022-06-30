// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:jsontree/jsontree.dart';
import 'package:squirrel/squirrel.dart';
import 'package:test/test.dart';

class NonJsonSerializable {

}


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

    await sq.add({'event': 'a'.jsonNode}.jsonNode);
    await sq.add({'event': 'b'.jsonNode}.jsonNode);
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
    expect(entries[0].value['T'] as int, lessThan(entries[1].value['T'] as int));
  });

  test("events are incrementing", () async {
    SquirrelStorage database = await SquirrelStorage.create(boxName: 'test');
    for (int i = 0; i < 5; ++i) {
      await database.add({"x": i.jsonNode}.jsonNode);
    }

    expect(database.entries().map((e) => e.value['D']['x']).toList(), [0, 1, 2, 3, 4]);
  });

  test("subcontexts", () async {
    SquirrelStorage sq = await SquirrelStorage.create(boxName: 'test2');
    expect(sq.length, 0);

    final context = await sq.add({'context': 'Ночь. Улица. Фонарь. Аптека.'.jsonNode}.jsonNode);

    await context.add({'event': 'a'.jsonNode}.jsonNode);
    await context.add({'event': 'b'.jsonNode}.jsonNode);
    final entries = sq.entries().toList();
    expect(entries.length, 3);

    // контекст содержит данные
    expect(entries[0].value['I'], context.id);
    expect(entries[0].value['P'], null);
    expect(entries[0].value['D'], {'context': 'Ночь. Улица. Фонарь. Аптека.'});

    // события ссылаются на контекст
    expect(entries[1].value['P'], context.id);
    expect(entries[2].value['P'], context.id);
  });

  test("handlers are assigned", () async {
    void sending() {}
    void modified() {}

    expect(sending, isNot(equals((modified))));

    SquirrelStorage sq = await SquirrelStorage.create(boxName: 'test2', onSendingTrigger: sending, onModified: modified);

    // checking that method `create` and the constructor correctly assigned the handlers
    // to fields
    expect(sq.onSendingTrigger, equals(sending));
    expect(sq.onModified, equals(modified));

    final e = await (await sq.add('sub'.jsonNode)).add('subsub'.jsonNode);

    // checking that child objects also received the correct handlers
    expect(e.onSendingTrigger, equals(sending));
    expect(e.onModified, equals(modified));
  });

  test("adding json-incompatible data throws error", () async {
    Squirrel squirrel = await Squirrel.create(boxName: 'test3');
    await squirrel.add(1.jsonNode);
    await squirrel.add(1.5.jsonNode);
    await squirrel.add('string'.jsonNode);
    await squirrel.add({'key': 123.jsonNode}.jsonNode);
    await squirrel.add([1.jsonNode, 2.jsonNode, 3.jsonNode].jsonNode);

    //expect(()=>squirrel.add(NonJsonSerializable()), throwsA(isA<JsonUnsupportedObjectError>()));
  });

  test("chunk get remove", () async {
    Squirrel sq = await Squirrel.create(boxName: 'test3');
    expect(sq.length, 0);

    for (int i = 0; i < 17; ++i) {
      await sq.add({"x": i.jsonNode}.jsonNode);
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
    Squirrel db = await Squirrel.create(boxName: 'test3', onModified: () => ++calls);

    //db.onModified.(() { ++calls; });
    await db.add({'a': 1.jsonNode}.jsonNode);
    await db.add({'b': 5.jsonNode}.jsonNode);
    expect(calls, 2);
    await db.add({'b': 5.jsonNode}.jsonNode);
    await db.add({'b': 5.jsonNode}.jsonNode);
    await db.add({'x': 55.jsonNode}.jsonNode);
    expect(calls, 5);
  });

  test("takeChunks list", () async {
    Squirrel database = await Squirrel.create(boxName: 'test');
    expect(database.length, 0);

    for (int i = 0; i < 17; ++i) {
      await database.add({"x": i.jsonNode}.jsonNode);
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
      await database.add({"x": i.jsonNode}.jsonNode);
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
      await database.add({"x": i.jsonNode}.jsonNode);
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
}