---
title: NodePusher Design
status: draft
audience: library maintainers and library users
language: Free Pascal, Lazarus
keywords:
  - streaming writer
  - json
  - yaml
  - sink
related: README.md
---

# NodePusher Design

## Purpose

NodePusher is a streaming writer library. A caller pushes tokens of a
JSON-shaped document into a pusher. The pusher checks the token order and
passes each token to a sink. The sink writes the token to a target. The
target is a stream, a string, or a `TJSONData` tree.

The design follows the Jackson `JsonGenerator`. No full document tree is
necessary in memory.

## Architecture

### Layers

```
caller code
    |  fluent calls
    v
TNodePusher        structure checking, state stack
    |  IPushSink token calls
    v
IPushSink          token interface
    |
    +-- TStreamSink   JSON or YAML text to a TStream
    +-- TStringSink   JSON or YAML text to a UTF8String
    +-- TNodeSink     TJSONData tree
```

### Units

| Unit | Content |
| --- | --- |
| `Pusher.Types` | `EPushError`, `TPushFormat`, `TPushOptions`, `IPushSink` |
| `Pusher.State` | The state object used by `TNodePusher` |
| `Pusher.Emitter` | The emitter base class, the output buffer, and the number formatters |
| `Pusher.Emitter.Json` | The JSON emitter |
| `Pusher.Emitter.Yaml` | The YAML emitter |
| `Pusher.Sinks` | `TStreamSink`, `TStringSink`, `TNodeSink` |
| `Pusher` | `TNodePusher` and the tree walker |

Each unit holds one concept. A unit stays under 2000 lines.

### TNodePusher

`TNodePusher` is an advanced record. It holds a reference to the sink and
a reference to a shared state object. A copy of the record shares both
references. Therefore a fluent chain can pass the record by value without
loss of state.

The state object holds:

- a stack of open containers (object or array),
- a flag that shows a pending property name,
- a flag that shows a completed root value.

Each call is checked against the state before the sink receives the token.

| Context | Valid calls |
| --- | --- |
| Start of document | any value call, `OpenObject`, `OpenArray` |
| Inside an object, no pending name | `PropertyName`, `Property*`, `CloseObject` |
| Inside an object, pending name | one value call, `OpenObject`, `OpenArray` |
| Inside an array | any value call, `OpenObject`, `OpenArray`, `CloseArray` |
| After the root value | `Flush` only |

A call that is not valid in the current context raises `EPushError`. The
sink never receives an invalid token sequence.

### IPushSink

`IPushSink` is a token interface. It has one method for each token kind:
`BeginObject`, `EndObject`, `BeginArray`, `EndArray`, `WriteName`,
`WriteString`, `WriteInteger`, `WriteFloat`, `WriteBcd`, `WriteBoolean`, `WriteNull`,
and `Flush`.

Sinks are reference counted. The last release of the last pusher copy frees
the sink.

### Format emitters

`TStreamSink` and `TStringSink` delegate the syntax to a format emitter.
The emitter for `pfJSON` writes compact or pretty JSON. The emitter for
`pfYAML` writes block-style YAML 1.2. The YAML emitter writes no `%YAML`
directive and no document start marker. Many readers that use libyaml
reject a `%YAML 1.2` directive, and the text is valid YAML 1.2 without it.

Both emitters write into a fixed 64 KB buffer of raw memory. They write
the buffer to the stream when it is full and on `Flush`. A string value is
copied into the buffer in runs. Only the characters that need an escape
are handled one by one.

The YAML emitter needs one token of look-ahead state. An empty object
writes as `{}` and an empty array writes as `[]`. The emitter therefore
delays the output of a container header until the first child or the close
token arrives.

### Sinks

| Sink | Target | Result access |
| --- | --- | --- |
| `TStreamSink` | `TStream` owned by the caller | the stream |
| `TStringSink` | internal string buffer | `Text` property after `Flush` |
| `TNodeSink` | `TJSONData` tree | `TakeRoot` function |

`TNodeSink` keeps a stack of open `TJSONObject` and `TJSONArray` nodes.
`TakeRoot` transfers ownership of the tree to the caller. If the sink is
freed before `TakeRoot`, the sink frees the tree.

### Tree input

`AddNode` and `PropertyNode` accept a `TJSONData` tree. `AddNode` in unit
`Pusher` visits the tree in document order and issues the same calls that a caller
could issue by hand. The state checks therefore apply to tree input. The
caller keeps ownership of the tree.

## Data rules

- Integers and floats use separate methods. A 64-bit integer keeps its
  exact value.
- `AddNumber` and `PropertyNumber` have an overload for `TBCD` (unit
  `FmtBCD`). The text emitters convert the value with `BCDToStr` and write
  all digits without rounding. The output uses plain decimal notation with
  no exponent. YAML writes the value as a plain number. A `TBCD` has no
  null state: an all-zero record is the value zero.
- `TNodeSink` has no big decimal node type. It stores a `TBCD` value as a
  `TJSONFloatNumber`, and the value can lose precision.
- A `Double` is written with the fewest digits (15 to 17) that read back
  as the same value. The text uses plain notation for decimal exponents
  from -7 to 20 and exponent notation outside that range. A `QWord` node
  value that exceeds `Int64` is written as an exact decimal.
- `NaN` and infinite floats raise `EPushError`, because JSON cannot
  represent them.
- JSON strings use the standard escapes. Control characters below `#x20`
  use `\u00XX`.
- YAML strings use plain style when this is safe. Otherwise they use
  double-quoted style. The emitter quotes a string that is empty, starts
  with an indicator character, a digit, a sign, or a dot, ends with a
  space or a colon, contains `: ` or ` #`, or contains a control
  character. Strings that read as null, true, or false in the YAML 1.2
  core schema are quoted in any letter case. The words yes, no, on, off,
  y, and n are quoted also. YAML 1.2 does not need this, but readers that
  follow YAML 1.1 read these words as booleans. Keys follow the same rules.
- A YAML string with a line feed uses a literal block scalar (`|`). The
  chomping indicator keeps the exact count of trailing line feeds: `|-`
  for none, `|` for one, and `|+` for more. The lines are indented two
  spaces more than their item. The string uses double-quoted style instead
  when a literal block cannot hold it: the string has a carriage return or
  another control character (a tab is allowed), has a line of blanks only,
  has no character except line feeds, or has a first text line that starts
  with a space.
- YAML 1.2 does not allow some characters in a document. The YAML emitter
  writes the C1 controls U+0080 to U+009F (except U+0085), U+FEFF, U+FFFE,
  and U+FFFF as `\uXXXX` escapes in double-quoted style.
- Property order is the order of the calls. Duplicate names are not
  detected.
- Text is UTF-8. Text parameters, the `Text` property, and the string
  methods of `IPushSink` have the type `UTF8String`. The library writes
  the bytes as given. It does not check that the bytes are valid UTF-8.
- The compiler converts a `UnicodeString` or `WideString` argument to
  UTF-8 at the call. On Unix, this conversion needs the unit `cwstring`
  in the program. An `AnsiString` argument with another code page is not
  converted at the call, because the parameter is a `const` reference.
  The conversion occurs when the value is assigned to a `UTF8String`
  variable.
- `TJSONData.AsString` has the type `UTF8String` in `fpjson`. Tree text
  passes with no conversion. On Unix, the parser of `fpjson` converts
  text through the system code page when the program sets none. A program
  that parses JSON with `fpjson` sets the code page to UTF-8 at start
  (`SetMultiByteConversionCodePage(CP_UTF8)` or the unit `cwstring`).
- The output buffer holds raw bytes. The emitters scan the text byte by
  byte through a `PAnsiChar`.

## Error handling

All errors are `EPushError`. The message names the failed call and the
context. After an error, the pusher state is undefined and the pusher is
not used again.

`Flush` raises `EPushError` when a container is open or when no root value
was written.

## Usage

### Write JSON to a stream

```pascal
var
  Stream: TFileStream;
  Pusher: TNodePusher;
begin
  Stream := TFileStream.Create('out.json', fmCreate);
  try
    Pusher := TNodePusher.Create(TStreamSink.Create(Stream, pfJSON));
    Pusher
      .OpenObject
        .PropertyString('name', 'NodePusher')
        .PropertyInteger('major', 1)
      .CloseObject
      .Flush;
  finally
    Stream.Free;
  end;
end;
```

### Write YAML to a string

```pascal
var
  Sink: TStringSink;
  Pusher: TNodePusher;
begin
  Sink := TStringSink.Create(pfYAML);
  Pusher := TNodePusher.Create(Sink);
  Pusher
    .OpenArray
      .AddString('a')
      .AddBoolean(True)
      .AddNull
    .CloseArray
    .Flush;
  WriteLn(Sink.Text);
end;
```

The pusher holds the sink through the `IPushSink` interface. The code keeps
a class reference to read `Text`. The variable type must therefore be an
interface reference too, or the code must keep the pusher alive until the
read is complete.

### Build a TJSONData tree

```pascal
var
  Sink: TNodeSink;
  Pusher: TNodePusher;
  Root: TJSONData;
begin
  Sink := TNodeSink.Create;
  Pusher := TNodePusher.Create(Sink);
  Pusher.OpenObject.PropertyNull('x').CloseObject.Flush;
  Root := Sink.TakeRoot;   // the caller now owns Root
  try
    // use Root
  finally
    Root.Free;
  end;
end;
```

### Name and value in separate calls

`PropertyName` followed by a value call gives the same result as one
`Property*` call. The two-call form lets a value be an object or an array.

```pascal
Pusher
  .OpenObject
    .PropertyName('items')
    .OpenArray
      .AddInteger(1)
      .AddInteger(2)
    .CloseArray
  .CloseObject
  .Flush;
```

### Write a big decimal

```pascal
Pusher
  .OpenObject
    .PropertyNumber('price', StrToBCD('12345678901234567890.123456789'))
  .CloseObject
  .Flush;
```

JSON output: `{"price":12345678901234567890.123456789}`

### Copy an existing tree

```pascal
Pusher.OpenObject.PropertyNode('config', ConfigNode).CloseObject.Flush;
```

## Testing

Tests cover these areas:

- valid and invalid call sequences for each context in the state table,
- string escaping for JSON and YAML, literal block scalars, and the
  characters that YAML 1.2 does not allow,
- identical token streams written through all three sinks,
- round trip: `TNodeSink` output equals the input tree,
- empty containers and nested containers in both formats.

## Build

The `Makefile` and the Lazarus files (`NodePusher.lpk` and
`tests/NodePusherTests.lpi`) build the library and the tests. They list the
same units and stay in parity. `make test` builds the tests with range,
overflow, stack, and heap checks.

## Open points

- Pretty-print options for YAML, such as the indent width. The YAML
  emitter uses an indent of two spaces.
- Support for YAML multi-document streams.
- A `%YAML 1.2` directive as an option, for readers that accept it.
- Validation of UTF-8 input.
