# NodePusher

NodePusher is a streaming writer library for Free Pascal and Lazarus. It
writes a JSON-shaped document one token at a time. The same calls produce
JSON text, YAML text, or an in-memory `TJSONData` tree.

The design follows the Jackson `JsonGenerator`. The caller does not build a
tree first. The caller opens objects and arrays, writes values, and closes
them. The sink writes each token at once. Memory use stays small for large
documents.

## Features

- Fluent API. Each method returns the pusher, so calls chain.
- One document model (JSON), several output formats.
- Pluggable sinks for streams, strings, and `TJSONData` trees.
- State checking. A misuse raises `EPushError`. Examples are a value
  without a property name inside an object, and a close that does not match
  the last open.
- Pretty printing is optional.

## Concepts

| Term | Meaning |
| --- | --- |
| Pusher | The `TNodePusher` record. It holds the caller API and the state stack. |
| Sink | An object that implements `IPushSink`. It receives tokens and writes them to a target. |
| Format | The text syntax a sink uses: `pfJSON` or `pfYAML`. |

The pusher checks the structure. The sink only formats and writes.

## Example

```pascal
uses
  Classes, Pusher, Pusher.Types, Pusher.Sinks;

var
  Stream: TFileStream;
  P: TNodePusher;
begin
  Stream := TFileStream.Create('out.json', fmCreate);
  try
    P := TNodePusher.Create(TStreamSink.Create(Stream, pfJSON));
    P
    .OpenObject
      .PropertyString('name', 'NodePusher')
      .PropertyInteger('version', 1)
      .PropertyName('tags')
      .OpenArray
        .AddString('json')
        .AddString('yaml')
      .CloseArray
    .CloseObject
    .Flush;
  finally
    Stream.Free;
  end;
end;
```

JSON output:

```json
{"name":"NodePusher","version":1,"tags":["json","yaml"]}
```

YAML output (`pfYAML`):

```yaml
name: NodePusher
version: 1
tags:
  - json
  - yaml
```

## API

The public types are in three units: `Pusher.Types` (types and the sink
interface), `Pusher` (`TNodePusher`), and `Pusher.Sinks` (the sinks).

```pascal
{ Pusher.Types }
type
  EPushError = class(Exception);
  TPushFormat = (pfJSON, pfYAML);   // pfYAML writes YAML 1.2

  TPushOptions = record
    Format: TPushFormat;
    Pretty: Boolean;        // JSON only. YAML is always block style.
    IndentWidth: Integer;   // Spaces per level when Pretty is true.
  end;

  { A sink receives one token per call. The pusher has already checked
    that the order of calls is valid. }
  IPushSink = interface
    procedure BeginObject;
    procedure EndObject;
    procedure BeginArray;
    procedure EndArray;
    procedure WriteName(const AName: UTF8String);
    procedure WriteString(const AValue: UTF8String);
    procedure WriteInteger(AValue: Int64);
    procedure WriteFloat(AValue: Double);
    procedure WriteBcd(const AValue: TBCD);
    procedure WriteBoolean(AValue: Boolean);
    procedure WriteNull;
    procedure Flush;
  end;

function PushOptions(AFormat: TPushFormat = pfJSON; APretty: Boolean = False;
  AIndentWidth: Integer = 2): TPushOptions;

{ Pusher }
type
  { The pusher is a record. Copies share the same sink and state. }
  TNodePusher = record
    constructor Create(const ASink: IPushSink);

    function OpenObject: TNodePusher;
    function CloseObject: TNodePusher;
    function OpenArray: TNodePusher;
    function CloseArray: TNodePusher;

    { Inside an object: write the name, then write exactly one value. }
    function PropertyName(const AName: UTF8String): TNodePusher;

    function PropertyString(const AName, AValue: UTF8String): TNodePusher;
    function PropertyInteger(const AName: UTF8String; AValue: Int64): TNodePusher;
    function PropertyNumber(const AName: UTF8String; AValue: Double): TNodePusher; overload;
    function PropertyNumber(const AName: UTF8String; const AValue: TBCD): TNodePusher; overload;
    function PropertyBoolean(const AName: UTF8String; AValue: Boolean): TNodePusher;
    function PropertyNull(const AName: UTF8String): TNodePusher;
    function PropertyNode(const AName: UTF8String; ANode: TJSONData): TNodePusher;

    { Inside an array, as the root value, or after PropertyName. }
    function AddString(const AValue: UTF8String): TNodePusher;
    function AddInteger(AValue: Int64): TNodePusher;
    function AddNumber(AValue: Double): TNodePusher; overload;
    function AddNumber(const AValue: TBCD): TNodePusher; overload;
    function AddBoolean(AValue: Boolean): TNodePusher;
    function AddNull: TNodePusher;
    function AddNode(ANode: TJSONData): TNodePusher;

    function Flush: TNodePusher;
  end;

{ Pusher.Sinks }
type
  { Writes text to a stream. The caller owns the stream. }
  TStreamSink = class(TTextSink)
    constructor Create(AStream: TStream; AFormat: TPushFormat = pfJSON); overload;
    constructor Create(AStream: TStream; const AOptions: TPushOptions); overload;
  end;

  { Writes text to an internal string. Text is complete after Flush. }
  TStringSink = class(TTextSink)
    constructor Create(AFormat: TPushFormat = pfJSON); overload;
    constructor Create(const AOptions: TPushOptions); overload;
    property Text: UTF8String read GetText;
  end;

  { Builds a TJSONData tree. The caller owns the tree after TakeRoot. }
  TNodeSink = class(TInterfacedObject, IPushSink)
    constructor Create;
    function TakeRoot: TJSONData;
  end;
```

### Design notes

- **Typed methods replace `Variant`.** `Variant` hides the type and
  makes the number and string rules unclear. Typed parameters let the
  compiler check each call.
- **Integers and floats are separate.** `PropertyInteger` and
  `PropertyNumber` keep 64-bit integers exact. A `Double` cannot hold all
  of them.
- **`AddNumber` and `PropertyNumber` accept a `TBCD`.** A `TBCD` (unit
  `FmtBCD`) holds a big decimal. The text sinks write every digit of the
  value with no rounding. `TNodeSink` has no big decimal node type. It
  stores the value as a `TJSONFloatNumber`, and the value can lose
  precision.
- **Text is `UTF8String`.** The text emitters copy the bytes. The compiler
  converts a `UnicodeString` or `WideString` argument to UTF-8. An
  `AnsiString` argument with another code page is not converted at the
  call.
- **A sink is an interface.** Reference counting frees the sink when the
  last pusher copy goes out of scope. The caller does not free it.
- **Sinks do not use `out` constructor parameters.** A constructor
  cannot keep an `out` parameter after it returns. A sink exposes its
  result through `Text` or `TakeRoot` instead.
- **The pusher records the document structure.** It keeps a stack of
  open containers and a flag that says if a property name is pending.
- **`PropertyNode` and `AddNode` walk a `TJSONData` tree** and push each
  token to the sink. The tree stays owned by the caller.

## Output rules

- A string is escaped for the chosen format. JSON uses the standard
  escapes. YAML uses plain style when this is safe, and double-quoted
  style otherwise.
- The YAML output is YAML 1.2. The pusher writes no `%YAML` directive,
  because many readers that use libyaml reject it.
- A YAML string with a line feed is written as a literal block scalar
  (`|`, `|-`, or `|+`, to keep the exact trailing line feeds).
- Text is UTF-8. Text parameters are `UTF8String`, and the pusher
  writes the bytes as given.
- `NaN` and infinite floats are not valid JSON. The pusher raises
  `EPushError` for them.
- A document has exactly one root value. A second root value raises
  `EPushError`.
- `Flush` pushes buffered data to the target. It raises `EPushError` if a
  container is still open.

## Migration from RawByteString

Text parameters had the type `RawByteString` in earlier revisions. They now
have the type `UTF8String`.

- A `UnicodeString` or `WideString` argument is converted to UTF-8 at the
  call. Before, the conversion used the system code page. On Unix, the
  program uses the unit `cwstring` for this conversion.
- A caller that holds UTF-8 bytes in an `AnsiString` or `RawByteString`
  declares the variable as `UTF8String`, or calls
  `SetCodePage(S, CP_UTF8, False)`. Without this, an assignment to a
  `UTF8String` can convert the bytes a second time.

## Build

The repository keeps a `Makefile` and Lazarus files in parity. Both build
the same units and the same tests. The minimum compiler is Free Pascal
3.2.2.

```
make          # build the library
make test     # build and run the tests
lazbuild tests/NodePusherTests.lpi
```

## License

SPDX identifier: `Apache-2.0`

Full name: Apache License, Version 2.0

Each Pascal file header uses the identifier from this section.
