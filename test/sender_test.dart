// SPDX-FileCopyrightText: (c) 2022 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:squirrel/squirrel.dart';
import 'package:test/test.dart';

class CallsCounting {
  int sent = 0;
  int calls = 0;
  late SquirrelSender sender;

  CallsCounting() {
    this.sender = SquirrelSender(
        send: (chunk) async {
          calls++;
          sent += chunk.length;
        },
        chunkSize: 10);
  }
}

void main() {
  setUp(() {
    Hive.init(Directory.systemTemp.createTempSync().path);
  });

  tearDown(() {
    Hive.close();
  });

  test("handleOnModified", () async {
    final cc = CallsCounting();
    late SquirrelStorage database;
    database = await SquirrelStorage.create(
        boxName: 'test', onModified: () => cc.sender.handleModified(database));

    for (int i = 0; i < 55; ++i) {
      await database.add({'data': i});
    }

    expect(cc.calls, 5);
    expect(cc.sent, 50);
  });

  test("handleTrigger", () async {
    final cc = CallsCounting();

    late SquirrelStorage database;
    database = await SquirrelStorage.create(
        boxName: 'test', onSendingTrigger: () => cc.sender.handleSendingTrigger(database));

    for (int i = 0; i < 55; ++i) {
      await database.add({'data': i});
    }

    expect(cc.calls, 0);
    expect(cc.sent, 0);

    await database.triggerSending();

    expect(cc.calls, 6);
    expect(cc.sent, 55);
  });

  test("handleTrigger and onModified", () async {
    final cc = CallsCounting();

    late SquirrelStorage database;
    database = await SquirrelStorage.create(
        boxName: 'test',
        onModified: () => cc.sender.handleModified(database),
        onSendingTrigger: () => cc.sender.handleSendingTrigger(database));

    for (int i = 0; i < 55; ++i) {
      await database.add({'data': i});
    }

    expect(cc.calls, 5);
    expect(cc.sent, 50);

    await database.triggerSending();

    expect(cc.calls, 6);
    expect(cc.sent, 55);
  });
}
