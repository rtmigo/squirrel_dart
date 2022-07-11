// SPDX-FileCopyrightText: (c) 2022 Artёm IG <github.com/rtmigo>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:io';


import 'package:jsontree/jsontree.dart';
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

  test("handleOnModified", () async {
    final cc = CallsCounting();
    tempStorage = await SquirrelStorage.create(
        tempFile!,
        onModified: () => cc.sender.handleModified(tempStorage));

    for (int i = 0; i < 55; ++i) {
      await tempStorage.add({'data': i.jsonNode}.jsonNode);
    }

    expect(cc.calls, 5);
    expect(cc.sent, 50);
  });

  test("handleTrigger", () async {
    final cc = CallsCounting();

    tempStorage = await SquirrelStorage.create(
        tempFile!,
        onSendingTrigger: () => cc.sender.handleSendingTrigger(tempStorage));

    for (int i = 0; i < 55; ++i) {
      await tempStorage.add({'data': i.jsonNode}.jsonNode);
    }

    expect(cc.calls, 0);
    expect(cc.sent, 0);

    await tempStorage.triggerSending();

    expect(cc.calls, 6);
    expect(cc.sent, 55);
  });

  test("handleTrigger and onModified", () async {
    final cc = CallsCounting();


    tempStorage = await SquirrelStorage.create(
        tempFile!,
        onModified: () => cc.sender.handleModified(tempStorage),
        onSendingTrigger: () => cc.sender.handleSendingTrigger(tempStorage));

    for (int i = 0; i < 55; ++i) {
      await tempStorage.add({'data': i.jsonNode}.jsonNode);
    }

    expect(cc.calls, 5);
    expect(cc.sent, 50);

    await tempStorage.triggerSending();

    expect(cc.calls, 6);
    expect(cc.sent, 55);
  });
}
