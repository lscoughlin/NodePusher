{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests
documentation: doc/design.md
notes:
  - json output tests
---
}
unit TestJson;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, FmtBCD, Pusher, Pusher.Types,
  Pusher.Sinks;

type
  TTestJson = class(TTestCase)
  published
    procedure ReadmeExample;
    procedure StringEscapes;
    procedure EmptyContainers;
    procedure PrettyOutput;
    procedure Numbers;
    procedure BigDecimal;
    procedure NonAscii;
    procedure DeepNesting;
  end;

implementation

const
  NL = LineEnding;

function NewPusher(out ASink: TStringSink; APretty: Boolean = False): TNodePusher;
begin
  ASink := TStringSink.Create(PushOptions(pfJSON, APretty, 2));
  Result := TNodePusher.Create(ASink);
end;

procedure TTestJson.ReadmeExample;
var
  S: TStringSink;
begin
  NewPusher(S)
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
  AssertEquals('{"name":"NodePusher","version":1,"tags":["json","yaml"]}', S.Text);
end;

procedure TTestJson.StringEscapes;
var
  S: TStringSink;
begin
  NewPusher(S).AddString('a"b\c' + #8#9#10#12#13 + #1#31 + '/').Flush;
  AssertEquals('"a\"b\\c\b\t\n\f\r\u0001\u001F/"', S.Text);
end;

procedure TTestJson.EmptyContainers;
var
  S: TStringSink;
begin
  NewPusher(S).OpenArray.OpenObject.CloseObject.OpenArray.CloseArray
    .CloseArray.Flush;
  AssertEquals('[{},[]]', S.Text);
end;

procedure TTestJson.PrettyOutput;
var
  S: TStringSink;
begin
  NewPusher(S, True)
    .OpenObject
      .PropertyInteger('a', 1)
      .PropertyName('b').OpenArray.AddInteger(1).AddInteger(2).CloseArray
      .PropertyName('c').OpenObject.CloseObject
    .CloseObject.Flush;
  AssertEquals('{' + NL + '  "a": 1,' + NL + '  "b": [' + NL + '    1,' + NL +
    '    2' + NL + '  ],' + NL + '  "c": {}' + NL + '}', S.Text);
end;

procedure TTestJson.Numbers;
var
  S: TStringSink;
  Third: Double;
begin
  Third := 1.0;
  Third := Third / 3.0;
  NewPusher(S)
    .OpenArray
      .AddNumber(0.1)
      .AddNumber(Third)
      .AddNumber(-2.5)
      .AddNumber(1E20)
      .AddNumber(1.5E-9)
      .AddNumber(1E300)
      .AddNumber(0.0)
      .AddNumber(123456.789)
      .AddInteger(Low(Int64))
      .AddInteger(High(Int64))
    .CloseArray.Flush;
  AssertEquals('[0.1,0.3333333333333333,-2.5,100000000000000000000,1.5E-9,1E300,0,123456.789,-9223372036854775808,' +
    '9223372036854775807]', S.Text);
end;

procedure TTestJson.BigDecimal;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyNumber('price', StrToBCD('12345678901234567890.123456789'))
    .CloseObject.Flush;
  AssertEquals('{"price":12345678901234567890.123456789}', S.Text);
end;

procedure TTestJson.NonAscii;
var
  S: TStringSink;
begin
  NewPusher(S).AddString('caf' + #$C3#$A9).Flush;
  AssertEquals('"caf' + #$C3#$A9 + '"', S.Text);
end;

procedure TTestJson.DeepNesting;
var
  S: TStringSink;
  P: TNodePusher;
  I: Integer;
begin
  P := NewPusher(S);
  for I := 1 to 10000 do
    P.OpenArray;
  for I := 1 to 10000 do
    P.CloseArray;
  P.Flush;
  AssertEquals(20000, Length(S.Text));
end;

initialization
  RegisterTest(TTestJson);

end.
