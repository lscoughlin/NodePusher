{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests
documentation: doc/design.md
notes:
  - sink and tree tests
---
}
unit TestSinks;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  Classes, SysUtils, StreamEx, fpcunit, testregistry, fpjson, jsonparser, FmtBCD,
  Pusher, Pusher.Types, Pusher.Sinks;

type
  { TStreamWriter.Flush of FPC 3.2.4 passes the address of the buffer array
    to WriteBuffer, so the stream gets the bytes of a pointer. This class
    writes the contents of the buffer. }
  TFixedStreamWriter = class(TStreamWriter)
  public
    procedure Flush; override;
  end;

  TTestSinks = class(TTestCase)
  private
    procedure Build(var P: TNodePusher);
    procedure AssertBytes(const AExpected, AActual: UTF8String);
  published
    procedure StreamEqualsString;
    procedure StreamYamlEqualsString;
    procedure LargeStream;
    procedure NodeSinkBuildsTree;
    procedure NodeSinkTakeRootWhileOpenRaises;
    procedure NodeSinkFreedWithoutTakeRoot;
    procedure RoundTripTree;
    procedure RoundTripThroughJsonText;
    procedure WalkerQWord;
    procedure WalkerPropertyNode;
    procedure BigDecimalInNode;
    procedure Utf8StringPassesUnchanged;
    procedure Utf8TreePassesUnchanged;
    procedure UnicodeStringIsConverted;
    procedure TextHasUtf8CodePage;
    procedure FourByteCodePointPasses;
    procedure WriterUtf8EqualsString;
    procedure WriterYamlEqualsString;
    procedure WriterUtf16;
    procedure WriterUtf16LargeSplit;
    procedure WriterStreamSplitSequence;
  end;

implementation

procedure TFixedStreamWriter.Flush;
var
  Count: Integer;
begin
  if (BaseStream = nil) or (FBufferIndex = 0) then
    Exit;
  Count := FBufferIndex;
  FBufferIndex := 0;
  BaseStream.WriteBuffer(FBuffer[0], Count);
end;

{ AssertEquals can pick a UnicodeString overload and convert the bytes.
  This check compares the bytes as they are. }
procedure TTestSinks.AssertBytes(const AExpected, AActual: UTF8String);
var
  I: Integer;
  Hex: String;
begin
  Hex := '';
  for I := 1 to Length(AActual) do
    Hex := Hex + IntToHex(Ord(AActual[I]), 2) + ' ';
  AssertTrue('expected ' + IntToStr(Length(AExpected)) + ' bytes, got ' +
    IntToStr(Length(AActual)) + ' bytes: ' + Hex, AExpected = AActual);
end;

procedure TTestSinks.Build(var P: TNodePusher);
begin
  P.OpenObject
    .PropertyString('s', 'caf' + #$C3#$A9 + ' "q"')
    .PropertyInteger('i', -42)
    .PropertyNumber('f', 2.5)
    .PropertyBoolean('b', True)
    .PropertyNull('n')
    .PropertyName('list')
    .OpenArray
      .AddInteger(1)
      .OpenObject.PropertyString('k', 'v').CloseObject
      .OpenArray.CloseArray
    .CloseArray
    .PropertyName('o').OpenObject.CloseObject
  .CloseObject.Flush;
end;

procedure TTestSinks.StreamEqualsString;
var
  Str: TStringSink;
  Mem: TStringStream;
  P: TNodePusher;
begin
  Str := TStringSink.Create(pfJSON);
  P := TNodePusher.Create(Str);
  Build(P);
  Mem := TStringStream.Create('');
  try
    P := TNodePusher.Create(TStreamSink.Create(Mem, pfJSON));
    Build(P);
    AssertEquals(Str.Text, Mem.DataString);
  finally
    P := Default(TNodePusher);
    Mem.Free;
  end;
end;

procedure TTestSinks.StreamYamlEqualsString;
var
  Str: TStringSink;
  Mem: TStringStream;
  P: TNodePusher;
begin
  Str := TStringSink.Create(pfYAML);
  P := TNodePusher.Create(Str);
  Build(P);
  Mem := TStringStream.Create('');
  try
    P := TNodePusher.Create(TStreamSink.Create(Mem, pfYAML));
    Build(P);
    AssertEquals(Str.Text, Mem.DataString);
  finally
    P := Default(TNodePusher);
    Mem.Free;
  end;
end;

procedure TTestSinks.LargeStream;
var
  Mem: TMemoryStream;
  P: TNodePusher;
  I: Integer;
begin
  Mem := TMemoryStream.Create;
  try
    P := TNodePusher.Create(TStreamSink.Create(Mem, pfJSON));
    P.OpenArray;
    for I := 1 to 200000 do
      P.OpenObject.PropertyInteger('id', I).PropertyString('s', 'value').CloseObject;
    P.CloseArray.Flush;
    AssertTrue(Mem.Size > 4000000);
  finally
    P := Default(TNodePusher);
    Mem.Free;
  end;
end;

procedure TTestSinks.NodeSinkBuildsTree;
var
  Sink: TNodeSink;
  P: TNodePusher;
  Root: TJSONData;
begin
  Sink := TNodeSink.Create;
  P := TNodePusher.Create(Sink);
  Build(P);
  Root := Sink.TakeRoot;
  try
    AssertEquals(Ord(jtObject), Ord(Root.JSONType));
    AssertEquals(-42, TJSONObject(Root).Integers['i']);
    AssertEquals(3, TJSONObject(Root).Arrays['list'].Count);
  finally
    Root.Free;
  end;
end;

procedure TTestSinks.NodeSinkTakeRootWhileOpenRaises;
var
  Sink: TNodeSink;
  P: TNodePusher;
begin
  Sink := TNodeSink.Create;
  P := TNodePusher.Create(Sink);
  P.OpenArray;
  try
    Sink.TakeRoot;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestSinks.NodeSinkFreedWithoutTakeRoot;
var
  P: TNodePusher;
begin
  P := TNodePusher.Create(TNodeSink.Create);
  Build(P);
  P := Default(TNodePusher);  // heaptrc reports a leak if the tree stays
end;

procedure TTestSinks.RoundTripTree;
var
  Source, Copy: TJSONData;
  Sink: TNodeSink;
  P: TNodePusher;
begin
  Source := GetJSON('{"a":[1,2.5,"x",true,null,{"b":{}}],"c":[],"d":"café"}');
  try
    Sink := TNodeSink.Create;
    P := TNodePusher.Create(Sink);
    P.AddNode(Source).Flush;
    Copy := Sink.TakeRoot;
    try
      AssertEquals(Source.AsJSON, Copy.AsJSON);
    finally
      Copy.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestSinks.RoundTripThroughJsonText;
var
  Source, Copy: TJSONData;
  Str: TStringSink;
  P: TNodePusher;
begin
  Source := GetJSON('{"a":[1,{"b":2}],"c":"x"}');
  try
    Str := TStringSink.Create(pfJSON);
    P := TNodePusher.Create(Str);
    P.AddNode(Source).Flush;
    Copy := GetJSON(Str.Text);
    try
      AssertEquals(Source.AsJSON, Copy.AsJSON);
    finally
      Copy.Free;
    end;
  finally
    Source.Free;
  end;
end;

procedure TTestSinks.WalkerQWord;
var
  Node: TJSONData;
  Str: TStringSink;
  P: TNodePusher;
begin
  Node := TJSONQWordNumber.Create(18446744073709551615);
  try
    Str := TStringSink.Create(pfJSON);
    P := TNodePusher.Create(Str);
    P.AddNode(Node).Flush;
    AssertEquals('18446744073709551615', Str.Text);
  finally
    Node.Free;
  end;
end;

procedure TTestSinks.WalkerPropertyNode;
var
  Node: TJSONData;
  Str: TStringSink;
  P: TNodePusher;
begin
  Node := GetJSON('[1,2]');
  try
    Str := TStringSink.Create(pfJSON);
    P := TNodePusher.Create(Str);
    P.OpenObject.PropertyNode('x', Node).CloseObject.Flush;
    AssertEquals('{"x":[1,2]}', Str.Text);
  finally
    Node.Free;
  end;
end;

procedure TTestSinks.BigDecimalInNode;
var
  Sink: TNodeSink;
  P: TNodePusher;
  Root: TJSONData;
begin
  Sink := TNodeSink.Create;
  P := TNodePusher.Create(Sink);
  P.AddNumber(StrToBCD('1.5')).Flush;
  Root := Sink.TakeRoot;
  try
    AssertEquals(1.5, Root.AsFloat, 0.0);
  finally
    Root.Free;
  end;
end;

procedure TTestSinks.Utf8StringPassesUnchanged;
var
  Str: TStringSink;
  P: TNodePusher;
  Text: UTF8String;
begin
  Text := 'caf' + #$C3#$A9 + ' ' + #$E2#$82#$AC;
  Str := TStringSink.Create(pfJSON);
  P := TNodePusher.Create(Str);
  P.AddString(Text).Flush;
  AssertBytes('"caf' + #$C3#$A9 + ' ' + #$E2#$82#$AC + '"', Str.Text);
end;

procedure TTestSinks.Utf8TreePassesUnchanged;
var
  Node: TJSONObject;
  Key, Value: UTF8String;
  Str: TStringSink;
  P: TNodePusher;
begin
  // Built by hand. The parser of fpjson converts text with \u escapes
  // through the system code page, which is not the subject of this test.
  Key := 'k' + #$C3#$A9;
  Value := 'na' + #$C3#$AF + 've ' + #$E2#$82#$AC;
  Node := TJSONObject.Create;
  try
    Node.Add(Key, TJSONString.Create(Value));
    Str := TStringSink.Create(pfYAML);
    P := TNodePusher.Create(Str);
    P.AddNode(Node).Flush;
    AssertBytes('k' + #$C3#$A9 + ': na' + #$C3#$AF + 've ' + #$E2#$82#$AC + LineEnding, Str.Text);
  finally
    Node.Free;
  end;
end;

{$push}{$warn 4105 off}  // the implicit conversion is the subject of the test
procedure TTestSinks.UnicodeStringIsConverted;
var
  Str: TStringSink;
  P: TNodePusher;
  Value: UnicodeString;
begin
  Value := UTF8Decode('é€');
  Str := TStringSink.Create(pfJSON);
  P := TNodePusher.Create(Str);
  P.OpenObject.PropertyString(Value, Value).CloseObject.Flush;
  AssertBytes('{"' + #$C3#$A9#$E2#$82#$AC + '":"' + #$C3#$A9#$E2#$82#$AC + '"}',
    Str.Text);
end;

{$pop}

procedure TTestSinks.TextHasUtf8CodePage;
var
  Str: TStringSink;
  P: TNodePusher;
begin
  Str := TStringSink.Create(pfYAML);
  P := TNodePusher.Create(Str);
  P.AddString('abc').Flush;
  AssertEquals(CP_UTF8, Integer(StringCodePage(Str.Text)));
end;

procedure TTestSinks.FourByteCodePointPasses;
var
  Value: UTF8String;
  Json, Yaml: TStringSink;
  P: TNodePusher;
begin
  Value := UTF8Encode(UnicodeString(#$D83D#$DE00));
  Json := TStringSink.Create(pfJSON);
  P := TNodePusher.Create(Json);
  P.AddString(Value).Flush;
  AssertBytes('"' + #$F0#$9F#$98#$80 + '"', Json.Text);
  Yaml := TStringSink.Create(pfYAML);
  P := TNodePusher.Create(Yaml);
  P.AddString(Value).Flush;
  AssertBytes(#$F0#$9F#$98#$80 + LineEnding, Yaml.Text);
end;

procedure TTestSinks.WriterUtf8EqualsString;
var
  Str: TStringSink;
  Mem: TMemoryStream;
  W: TStreamWriter;
  P: TNodePusher;
  Got: UTF8String;
begin
  Str := TStringSink.Create(pfJSON);
  P := TNodePusher.Create(Str);
  Build(P);
  Mem := TMemoryStream.Create;
  W := TFixedStreamWriter.Create(Mem);
  try
    P := TNodePusher.Create(TWriterSink.Create(W, pfJSON));
    Build(P);
    P := Default(TNodePusher);
    SetLength(Got, Mem.Size);
    Move(Mem.Memory^, Got[1], Mem.Size);
    AssertBytes(Str.Text, Got);
  finally
    W.Free;
    Mem.Free;
  end;
end;

procedure TTestSinks.WriterYamlEqualsString;
var
  Str: TStringSink;
  Mem: TMemoryStream;
  W: TStreamWriter;
  P: TNodePusher;
  Got: UTF8String;
begin
  Str := TStringSink.Create(pfYAML);
  P := TNodePusher.Create(Str);
  Build(P);
  Mem := TMemoryStream.Create;
  W := TFixedStreamWriter.Create(Mem);
  try
    P := TNodePusher.Create(TWriterSink.Create(W, pfYAML));
    Build(P);
    P := Default(TNodePusher);
    SetLength(Got, Mem.Size);
    Move(Mem.Memory^, Got[1], Mem.Size);
    AssertBytes(Str.Text, Got);
  finally
    W.Free;
    Mem.Free;
  end;
end;

{ A UTF-16 writer receives UTF-16 code units, not UTF-8 bytes. }
procedure TTestSinks.WriterUtf16;
var
  Mem: TMemoryStream;
  W: TStreamWriter;
  P: TNodePusher;
  Units: array of Word;
  Expected: UnicodeString;
  I: Integer;
begin
  Expected := UnicodeString('["caf') + #$00E9 + #$D83D#$DE00 + '"]';
  Mem := TMemoryStream.Create;
  W := TFixedStreamWriter.Create(Mem, TEncoding.Unicode);
  try
    P := TNodePusher.Create(TWriterSink.Create(W, pfJSON));
    P.OpenArray.AddString(UTF8Encode(UnicodeString('caf') + #$00E9 + #$D83D#$DE00))
      .CloseArray.Flush;
    P := Default(TNodePusher);
    AssertEquals(Length(Expected) * 2, Integer(Mem.Size));
    SetLength(Units, Length(Expected));
    Move(Mem.Memory^, Units[0], Mem.Size);
    for I := 0 to High(Units) do
      AssertEquals(Ord(Expected[I + 1]), Units[I]);
  finally
    W.Free;
    Mem.Free;
  end;
end;

{ The emitter buffer ends in the middle of a character at some point. The
  output stays valid in the writer encoding. }
procedure TTestSinks.WriterUtf16LargeSplit;
var
  Mem: TMemoryStream;
  W: TStreamWriter;
  P: TNodePusher;
  Value: UTF8String;
  Units: array of WideChar;
  I, Count: Integer;
begin
  Value := UTF8Encode(UnicodeString(#$00E9#$20AC#$D83D#$DE00));
  Count := 30000;
  Mem := TMemoryStream.Create;
  W := TFixedStreamWriter.Create(Mem, TEncoding.Unicode);
  try
    P := TNodePusher.Create(TWriterSink.Create(W, pfJSON));
    P.OpenArray;
    for I := 1 to Count do
      P.AddString(Value);
    P.CloseArray.Flush;
    P := Default(TNodePusher);
    SetLength(Units, Mem.Size div 2);
    Move(Mem.Memory^, Units[0], Mem.Size);
    { each element is a quote, four code units, a quote, and a comma, except
      that the last element has no comma }
    AssertEquals(2 + Count * 7 - 1, Length(Units));
    for I := 0 to Count - 1 do
    begin
      AssertEquals(#$00E9, Units[1 + I * 7 + 1]);
      AssertEquals(#$20AC, Units[1 + I * 7 + 2]);
      AssertEquals(#$D83D, Units[1 + I * 7 + 3]);
      AssertEquals(#$DE00, Units[1 + I * 7 + 4]);
    end;
  finally
    W.Free;
    Mem.Free;
  end;
end;

{ A write that ends inside a UTF-8 sequence waits for the next bytes. }
procedure TTestSinks.WriterStreamSplitSequence;
var
  Mem: TMemoryStream;
  W: TStreamWriter;
  S: TWriterStream;
  Data: array[0..8] of Byte;
  Units: array[0..2] of Word;
  I: Integer;
begin
  { U+20AC, U+1F600, and U+00E9 }
  Data[0] := $E2; Data[1] := $82; Data[2] := $AC;
  Data[3] := $F0; Data[4] := $9F; Data[5] := $98; Data[6] := $80;
  Data[7] := $C3; Data[8] := $A9;
  Mem := TMemoryStream.Create;
  W := TFixedStreamWriter.Create(Mem, TEncoding.Unicode);
  S := TWriterStream.Create(W);
  try
    for I := 0 to High(Data) do
      S.WriteBuffer(Data[I], 1);
    W.Flush;
    AssertEquals(8, Integer(Mem.Size));
    Move(Mem.Memory^, Units[0], 6);
    AssertEquals($20AC, Units[0]);
    AssertEquals($D83D, Units[1]);
    AssertEquals($DE00, Units[2]);
    Move((Mem.Memory + 6)^, Units[0], 2);
    AssertEquals($00E9, Units[0]);
  finally
    S.Free;
    W.Free;
    Mem.Free;
  end;
end;

initialization
  RegisterTest(TTestSinks);

end.
