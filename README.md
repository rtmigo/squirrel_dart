# [squirrel](https://github.com/rtmigo/squirrel_dart)

Persistent data storage for temporary accumulation of structured logs before sending them to the server.

## SquirrelStorage

```dart

void main() {
    SquirrelStorage squirrel = await SquirrelStorage.create(boxName: 'test2');

    // The arguments to addEvent and addContext are arbitrary data. It is only important that
    // they can be converted to JSON.

    await squirrel.root.addEvent({'type': 'info', 'text': 'First log entry'});
    await squirrel.root.addEvent({'type': 'warning', 'text': 'Oops', file: 'myfile.dart'});

    final context = await squirrel.root.addContext({'type': 'game', 'game_id': 123});
    await context.addEvent({'move': 'E2-E4'});
    await context.addEvent({'move': 'E7-E5'});
}
```

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
