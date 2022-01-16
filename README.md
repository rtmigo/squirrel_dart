# [squirrel](https://github.com/rtmigo/squirrel_dart)

Persistent data storage for temporary accumulation of structured logs before sending them to the server.

## SquirrelStorage

```dart
import 'package:squirrel/squirrel.dart';

void main() {
    SquirrelStorage squirrel = await SquirrelStorage.create(boxName: 'test2');

    // The argument to addEvent is arbitrary data. It is only important that
    // is can be converted to JSON.

    await squirrel.root.addEvent('Text entry');
    await squirrel.root.addEvent({'type': 'info', 'text': 'Structured entry'});
    await squirrel.root.addEvent(['List entry', 1, 2, 3]);
}
```

# Contexts

The entries can be grouped into "contexts".

```dart
import 'package:squirrel/squirrel.dart';

void main() {
    SquirrelStorage squirrel = await SquirrelStorage.create(boxName: 'test2');

    final someGameContext = await squirrel.root.addContext({'game': 'chess'});
    await someGameContext.addEvent({'move': 'E2-E4'});
    await someGameContext.addEvent({'move': 'E7-E5'});

    final otherGameContext = await squirrel.root.addContext({'game': 'chess'});
    await otherGameContext.addEvent({'move': 'D2-D4'});
    await otherGameContext.addEvent({'move': 'D7-D5'});
}
```

When we create an event inside a context, the string ID of the corresponding context is appended
to the event entry. The server may restore the tree structure along with the contexts if needed.

## SquirrelSender

SquirrelSender automates sending logs to an abstract server when the number of records in the
database exceeds a given limit. It binds to the `onModified` handler.

```dart
import 'package:squirrel/squirrel.dart';

Future<void> sendToServer(List<dynamic> chunk) await {
  // this function will receive data to be sent.
  // If the data cannot be sent (for example, due to connection errors),
  // the function should throw an exception.
}

void main()
   final sender = SquirrelSender(send: sendToServer);
   late SquirrelStorage squirrel;
   squirrel = await SquirrelStorage.create(
     onModified: () => sender.handleOnModified(squirrel));
   ...
   // use Squirrel as usual
}
```
