# [squirrel](https://github.com/rtmigo/squirrel_dart)

`SquirrelStorage` accumulates structured log entries in a file-based local storage before sending
them to the server.

## addEvent

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

## addContext

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

## Data format

```dart
addEvent({'a': 1, 'b':2});
```

```dart
{
    'I':'U_sWAEJnR4epXu-TK0FCYA',  // totally unique Slugid for each entry
    'T': 194942647293470,          // time in microseconds since epoch UTC
    'D': {'a': 1, 'b':2},          // the actual data
    'P': null                      // parent context
}
```

```dart
var context = addContext({'name': 'my context'});
context.addEvent('my event');
```

```dart
[
    // the context is essentially an ordinary entry
    {
        'I': 'ti8C-AKGQsq3rDjSuXe94w', // unique context id
        'T': 194942647293470,
        'D': {'name': 'my context'},
        'P': null
    },

    // the child entry contains a reference to the parent context.
    {
        'I': 'Fum-zBhASyO50rg3mtQcD',
        'T': 194942647223453,
        'D': 'my event',
        'P': 'ti8C-AKGQsq3rDjSuXe94w'  // link to the context id
    }
]
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
