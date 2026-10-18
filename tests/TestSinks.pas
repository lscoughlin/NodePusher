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
  Classes, SysUtils, fpcunit, testregistry, fpjson, jsonparser, FmtBCD,
  Pusher, Pusher.Types, Pusher.Sinks;

type
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
  end;

implementation

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

initialization
  RegisterTest(TTestSinks);

end.
