[![stability-experimental](https://img.shields.io/badge/stability-experimental-orange.svg)](https://github.com/mkenney/software-guides/blob/master/STABILITY-BADGES.md#experimental)

# [squirrel](https://github.com/rtmigo/squirrel_dart)

`Squirrel` is a FIFO queue. The queue is stored in the file system and persists
across application restarts.

Queue elements are any JSON-compatible objects (`Map`, `List`, `Set`, `String`,
`int`, `double`, `null`) wrapped to
[`JsonNode`](https://pub.dev/packages/jsontree). Also, each element of the queue
has a unique identifier, a timestamp, and an optional reference to the parent
element.

`Squirrel` is intended to be a temporary buffer for storing log data before
sending it to the server. Upon request, the object returns its elements grouped
into chunks. Iterators allow both simple reading of elements, and reading with
automatic deletion after sending.

## Adding entries

```dart
import 'package:squirrel/squirrel.dart';

void main() {
  final squirrel = await Squirrel.open(File("/path/to/db"));

  // The argument to addEvent is arbitrary data. It is only 
  // important that it can be converted to JSON.

  await squirrel.add('Text entry');

  await squirrel.add(['List entry'.jsonNode,
    1.jsonNode, 2.jsonNode, 3.jsonNode].jsonNode);

  await squirrel.add({'type': 'info'.jsonNode,
    'text': 'Structured entry'.jsonNode,
    'more': [1.jsonNode, 2.jsonNode, 3.jsonNode]
        .jsonNode});
}
```

## Adding child entries

Each entry can have a child entry.

```dart
import 'package:squirrel/squirrel.dart';

void main() {
  final squirrel = await Squirrel.open(File("/path/to/db"));

  final parentA = await squirrel.add({'game': 'chess'.jsonNode}.jsonNode);
  await parentA.add({'move': 'E2-E4'.jsonNode}.jsonNode);
  await parentA.add({'move': 'E7-E5'.jsonNode}.jsonNode);

  final parentB = await squirrel.add({'game': 'chess'.jsonNode}.jsonNode);
  await parentB.add({'move': 'D2-D4'.jsonNode}.jsonNode);
  await parentB.add({'move': 'D7-D5'.jsonNode}.jsonNode);
}
```

Child nodes can be nested. You can create a tree-like structure of any depth.

## Data format

### Entries as JSON data

```dart
storage.add({'mydata': 123.jsonNode}.
jsonNode);
```

The data generated by such calls will be something like this:

```dart
{
'I': 'U_sWAEJnR4epXu-TK0FCYA', // unique Slugid for each entry
'T': 194942647293470, // time in microseconds since epoch UTC
'D': {'mydata': 123}, // the data from argument
'P': null // parent context; null for root
}
```

We will essentially send a list of such records converted to JSON to the server.

When adding child entries, the child data gets a link to the parent entry.

```dart

final parent = await
squirrel.add({'mydata': 123.jsonNode}.
jsonNode);
await
parent.add('
child A
'
.
jsonNode);
await
parent.add('
child B
'
.
jsonNode);
```

```dart
// the parent is an ordinary entry
{
'I': 'U_sWAEJnR4epXu-TK0FCYA', // note this id
'T': 194942647293470,
'D': {'mydata': 123},
'P': null
},

// child entries contain a reference to the parent 
    {
'I': 'Fum-zBhASyO50rg3mtQcD',
'T': 194942647223453,
'D': 'child A',
'P': 'U_sWAEJnR4epXu-TK0FCYA' // link to the parent id
},

{
'I': 'a8_YezW8T7e1jLxG7evy-A',
'T': 194942647254428,
'D': 'child B',
'P': 'U_sWAEJnR4epXu-TK0FCYA' // link to the parent id
},
```

## SquirrelSender

`SquirrelSender` automates sending logs to an abstract server when the number of
records in the database exceeds a given limit (100 entries by default). It
handes to the`onModified` and `onSendingTrigger` events.

```dart
import 'package:squirrel/squirrel.dart';

Future<void> sendToServer(List<dynamic> chunk) async {
  // this function will receive data to be sent.
  // Each item of the list is convertible to JSON.

  // If the data cannot be sent (for example, due to connection errors),
  // the function should throw an exception.
}

void main
(
)

final squirrel = SquirrelSender.create(sendToServer);
// ...
// use Squirrel as usual
}
```

## License

Copyright © 2022 [Artёm IG](https://github.com/rtmigo). Released under
the [MIT License](LICENSE).