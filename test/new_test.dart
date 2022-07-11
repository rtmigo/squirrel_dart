// SPDX-FileCopyrightText: (c) 2021 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT


import 'dart:io';

import 'package:jsontree/jsontree.dart';
import 'package:squirrel/squirrel.dart';
import 'package:test/test.dart';

class NonJsonSerializable {}

void main() {
  File? tempFile;
  late SquirrelStorage tempStorage;
  setUp(() {
    tempFile = File("temp/_temp_test_${DateTime.now().microsecondsSinceEpoch}.db");
  });

  tearDown(() async {
    await tempStorage.close();
    try {
      tempFile!.deleteSync();
    } on FileSystemException {
      // pass
    }
    tempFile = null;
  });

  test("first", () async {
    tempStorage = await SquirrelStorage.create(tempFile!);
    expect(await tempStorage.length(), 0);

    await tempStorage.add({'event': 'a'.jsonNode}.jsonNode);
    await tempStorage.add({'event': 'b'.jsonNode}.jsonNode);
    final entries = await tempStorage.readEntries().readToList();
    expect(entries.length, 2);



    for (final e in entries) {
      print(e);
      print(e.value);
      expect(e.key, isA<int>());
      expect(e.value['I'], isA<String>());
      expect(e.value['I'].length, '3cka5hc3QRCTB61W8dDoag'.length);
      expect(e.value['T'], isA<int>());
      expect(e.value['P'], isNull);
    }


    // данные конкретно такие
    expect(entries[0].value['D'], {'event': 'a'});
    expect(entries[1].value['D'], {'event': 'b'});

    // время идет по возрастанию
    expect(
        entries[0].value['T'] as int, lessThan(entries[1].value['T'] as int));
  });

  test("events are incrementing", () async {
    tempStorage =
        await SquirrelStorage.create(tempFile!);
    for (int i = 0; i < 5; ++i) {
      await tempStorage.add({"x": i.jsonNode}.jsonNode);
    }

    expect((await tempStorage.readEntries().readToList()).map((e) => e.value['D']['x']).toList(),
        [0, 1, 2, 3, 4]);
  });

  test("subcontexts", () async {
    tempStorage =
        await SquirrelStorage.create(tempFile!);
    expect(await tempStorage.length(), 0);

    final context = await tempStorage
        .add({'context': 'Ночь. Улица. Фонарь. Аптека.'.jsonNode}.jsonNode);

    await context.add({'event': 'a'.jsonNode}.jsonNode);
    await context.add({'event': 'b'.jsonNode}.jsonNode);
    final entries = await tempStorage.readEntries().toList();
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

    tempStorage = await SquirrelStorage.create(tempFile!,
        onSendingTrigger: sending,
        onModified: modified);

    // checking that method `create` and the constructor correctly assigned the handlers
    // to fields
    expect(tempStorage.onSendingTrigger, equals(sending));
    expect(tempStorage.onModified, equals(modified));

    final e = await (await tempStorage.add('sub'.jsonNode)).add('subsub'.jsonNode);

    // checking that child objects also received the correct handlers
    expect(e.onSendingTrigger, equals(sending));
    expect(e.onModified, equals(modified));
  });

  test("adding json-incompatible data throws error", () async {
    tempStorage =
        await Squirrel.create(tempFile!);
    await tempStorage.add(1.jsonNode);
    await tempStorage.add(1.5.jsonNode);
    await tempStorage.add('string'.jsonNode);
    await tempStorage.add({'key': 123.jsonNode}.jsonNode);
    await tempStorage.add([1.jsonNode, 2.jsonNode, 3.jsonNode].jsonNode);

    //expect(()=>squirrel.add(NonJsonSerializable()), throwsA(isA<JsonUnsupportedObjectError>()));
  });

  test("chunk get remove", () async {
    tempStorage = await Squirrel.create(tempFile!);
    expect(await tempStorage.length(), 0);

    for (int i = 0; i < 17; ++i) {
      await tempStorage.add({"x": i.jsonNode}.jsonNode);
    }

    // убедимся, что данные не удаляются, когда мы просто get
    for (int i = 0; i < 3; ++i) {
      final stub = await tempStorage.readChunk(10);
      expect(stub.length, 10);
    }

    final chunk1 = await tempStorage.readChunk(10);
    expect(chunk1.length, 10);
    await tempStorage.deleteChunk(chunk1);

    final chunk2 = await tempStorage.readChunk(10);
    expect(chunk2.length, 7);
    await tempStorage.deleteChunk(chunk2);

    final chunk3 = await tempStorage.readChunk(10);
    expect(chunk3.length, 0);
    await tempStorage.deleteChunk(chunk3);
  });

  test("onModified", () async {
    int calls = 0;
    tempStorage = await Squirrel.create(tempFile!, onModified: () => ++calls);

    //db.onModified.(() { ++calls; });
    await tempStorage.add({'a': 1.jsonNode}.jsonNode);
    await tempStorage.add({'b': 5.jsonNode}.jsonNode);
    expect(calls, 2);
    await tempStorage.add({'b': 5.jsonNode}.jsonNode);
    await tempStorage.add({'b': 5.jsonNode}.jsonNode);
    await tempStorage.add({'x': 55.jsonNode}.jsonNode);
    expect(calls, 5);
  });

  test("takeChunks list", () async {
    tempStorage =
        await Squirrel.create(tempFile!);
    expect(await tempStorage.length(), 0);

    for (int i = 0; i < 17; ++i) {
      await tempStorage.add({"x": i.jsonNode}.jsonNode);
    }

    //await Future.delayed(const Duration(milliseconds: 500));

    expect(await tempStorage.length(), 17);

    final chunks = await tempStorage.readChunks(itemsPerChunk: 10).toList();
    expect(chunks.length, 2);
    expect(chunks[0].length, 10);
    expect(chunks[1].length, 7);

    expect(await tempStorage.length(), 0);
  });

  test("takeChunks maxTotal", () async {
    tempStorage = await SquirrelStorage.create(tempFile!);
    expect(await tempStorage.length(), 0);

    for (int i = 0; i < 50; ++i) {
      await tempStorage.add({"x": i.jsonNode}.jsonNode);
    }

    expect(await tempStorage.length(), 50);

    final chunks = await tempStorage
        .readChunks(itemsPerChunk: 10, maxItemsTotal: 42)
        .toList();
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

    expect(await tempStorage.length(), 8);
  });

  test("takeChunks removes only after next chunk is requested", () async {
    tempStorage =
        await SquirrelStorage.create(tempFile!);
    expect(await tempStorage.length(), 0);

    for (int i = 0; i < 27; ++i) {
      await tempStorage.add({"x": i.jsonNode}.jsonNode);
    }

    int i = 0;
    await for (final chunk in tempStorage.readChunks(itemsPerChunk: 10)) {
      switch (i) {
        case 0:
          expect(await tempStorage.length(), 27);
          expect(chunk.length, 10);
          break;
        case 1:
          expect(await tempStorage.length(), 17);
          expect(chunk.length, 10);
          break;
        case 2:
          expect(await tempStorage.length(), 7);
          expect(chunk.length, 7);
          break;
        default:
          fail("oops");
      }

      ++i;
    }
    expect(await tempStorage.length(), 0);
    expect(i, 3);
  });
}
