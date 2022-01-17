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


}
