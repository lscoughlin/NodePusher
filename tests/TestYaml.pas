{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests
documentation: doc/design.md
notes:
  - yaml output tests
---
}
unit TestYaml;

{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, FmtBCD, Pusher, Pusher.Types,
  Pusher.Sinks;

type
  TTestYaml = class(TTestCase)
  published
    procedure ReadmeExample;
    procedure EmptyRoots;
    procedure EmptyNested;
    procedure ArrayOfObjects;
    procedure ArrayOfArrays;
    procedure ObjectInObject;
    procedure Quoting;
    procedure NoDirective;
    procedure Yaml12DisallowedCharacters;
    procedure MultiLineChomping;
    procedure MultiLineNested;
    procedure MultiLineRoot;
    procedure MultiLineFallsBackToQuotes;
    procedure KeysAreQuoted;
    procedure ScalarKinds;
    procedure BigDecimal;
    procedure DeepNesting;
  end;

implementation

const
  NL = LineEnding;

function NewPusher(out ASink: TStringSink): TNodePusher;
begin
  ASink := TStringSink.Create(pfYAML);
  Result := TNodePusher.Create(ASink);
end;

procedure TTestYaml.ReadmeExample;
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
  AssertEquals('name: NodePusher' + NL + 'version: 1' + NL + 'tags:' + NL +
    '  - json' + NL + '  - yaml' + NL, S.Text);
end;

procedure TTestYaml.EmptyRoots;
var
  S: TStringSink;
begin
  NewPusher(S).OpenObject.CloseObject.Flush;
  AssertEquals('{}' + NL, S.Text);
  NewPusher(S).OpenArray.CloseArray.Flush;
  AssertEquals('[]' + NL, S.Text);
end;

procedure TTestYaml.EmptyNested;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyName('a').OpenObject.CloseObject
      .PropertyName('b').OpenArray.CloseArray
      .PropertyName('c').OpenArray.OpenObject.CloseObject.OpenArray.CloseArray.CloseArray
    .CloseObject.Flush;
  AssertEquals('a: {}' + NL + 'b: []' + NL + 'c:' + NL + '  - {}' + NL +
    '  - []' + NL, S.Text);
end;

procedure TTestYaml.ArrayOfObjects;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray
      .OpenObject.PropertyInteger('a', 1).PropertyInteger('b', 2).CloseObject
      .OpenObject.PropertyInteger('c', 3).CloseObject
    .CloseArray.Flush;
  AssertEquals('- a: 1' + NL + '  b: 2' + NL + '- c: 3' + NL, S.Text);
end;

procedure TTestYaml.ArrayOfArrays;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray
      .OpenArray.AddInteger(1).AddInteger(2).CloseArray
      .OpenArray.AddInteger(3).CloseArray
    .CloseArray.Flush;
  AssertEquals('- - 1' + NL + '  - 2' + NL + '- - 3' + NL, S.Text);
end;

procedure TTestYaml.ObjectInObject;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyName('a')
      .OpenObject
        .PropertyName('b')
        .OpenObject.PropertyNull('c').CloseObject
        .PropertyBoolean('d', True)
      .CloseObject
      .PropertyBoolean('e', False)
    .CloseObject.Flush;
  AssertEquals('a:' + NL + '  b:' + NL + '    c: null' + NL + '  d: true' + NL +
    'e: false' + NL, S.Text);
end;

procedure TTestYaml.Quoting;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray
      .AddString('hello world')
      .AddString('')
      .AddString('true')
      .AddString('Null')
      .AddString('123')
      .AddString('1e3')
      .AddString('a: b')
      .AddString('a #b')
      .AddString('- x')
      .AddString('x:')
      .AddString('tab' + #9 + 'x')
      .AddString('cr' + #13 + 'x')
      .AddString('q"uote')
      .AddString('caf' + #$C3#$A9)
    .CloseArray.Flush;
  AssertEquals('- hello world' + NL + '- ""' + NL + '- "true"' + NL +
    '- "Null"' + NL + '- "123"' + NL + '- "1e3"' + NL + '- "a: b"' + NL +
    '- "a #b"' + NL + '- "- x"' + NL + '- "x:"' + NL +
    '- "tab\tx"' + NL + '- "cr\rx"' + NL + '- q"uote' + NL + '- caf' + #$C3#$A9 + NL, S.Text);
end;

procedure TTestYaml.NoDirective;
var
  S: TStringSink;
begin
  NewPusher(S).AddInteger(1).Flush;
  AssertEquals('1' + NL, S.Text);
end;

procedure TTestYaml.Yaml12DisallowedCharacters;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray
      .AddString('a' + #$C2#$80 + 'b')
      .AddString('a' + #$C2#$9F)
      .AddString('a' + #$C2#$85 + 'b')
      .AddString(#$EF#$BB#$BF + 'bom')
      .AddString('x' + #$EF#$BF#$BE#$EF#$BF#$BF)
      .AddString('a' + #10 + 'b' + #$C2#$90)
      .AddString('caf' + #$C3#$A9)
    .CloseArray.Flush;
  AssertEquals('- "a\u0080b"' + NL + '- "a\u009F"' + NL +
    '- a' + #$C2#$85 + 'b' + NL + '- "\uFEFFbom"' + NL +
    '- "x\uFFFE\uFFFF"' + NL + '- "a\nb\u0090"' + NL +
    '- caf' + #$C3#$A9 + NL, S.Text);
end;

procedure TTestYaml.MultiLineChomping;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyString('strip', 'a' + #10 + 'b')
      .PropertyString('clip', 'a' + #10 + 'b' + #10)
      .PropertyString('keep', 'a' + #10 + 'b' + #10#10)
      .PropertyString('gap', 'a' + #10#10 + 'b')
      .PropertyString('lead', #10 + 'a' + #10)
      .PropertyString('indented', 'a' + #10 + '  b' + #10)
    .CloseObject.Flush;
  AssertEquals('strip: |-' + NL + '  a' + NL + '  b' + NL +
    'clip: |' + NL + '  a' + NL + '  b' + NL +
    'keep: |+' + NL + '  a' + NL + '  b' + NL + NL +
    'gap: |-' + NL + '  a' + NL + NL + '  b' + NL +
    'lead: |' + NL + NL + '  a' + NL +
    'indented: |' + NL + '  a' + NL + '    b' + NL, S.Text);
end;

procedure TTestYaml.MultiLineNested;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyName('o').OpenObject
        .PropertyString('k', 'x' + #10 + 'y')
      .CloseObject
      .PropertyName('l').OpenArray
        .AddString('p' + #10 + 'q')
        .OpenArray.AddString('r' + #10 + 's').CloseArray
        .OpenObject.PropertyString('m', 't' + #10 + 'u').PropertyInteger('n', 1).CloseObject
      .CloseArray
    .CloseObject.Flush;
  AssertEquals('o:' + NL + '  k: |-' + NL + '    x' + NL + '    y' + NL +
    'l:' + NL + '  - |-' + NL + '    p' + NL + '    q' + NL +
    '  - - |-' + NL + '      r' + NL + '      s' + NL +
    '  - m: |-' + NL + '      t' + NL + '      u' + NL + '    "n": 1' + NL, S.Text);
end;

procedure TTestYaml.MultiLineRoot;
var
  S: TStringSink;
begin
  NewPusher(S).AddString('a' + #10 + 'b').Flush;
  AssertEquals('|-' + NL + '  a' + NL + '  b' + NL, S.Text);
end;

procedure TTestYaml.MultiLineFallsBackToQuotes;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray
      .AddString(#10)
      .AddString('a' + #10 + '   ' + #10 + 'b')
      .AddString('a' + #13#10 + 'b')
      .AddString('  a' + #10 + 'b')
      .AddString('a' + #10 + 'b' + #10 + ' ')
    .CloseArray.Flush;
  AssertEquals('- "\n"' + NL + '- "a\n   \nb"' + NL + '- "a\r\nb"' + NL +
    '- "  a\nb"' + NL + '- "a\nb\n "' + NL, S.Text);
end;

procedure TTestYaml.KeysAreQuoted;
var
  S: TStringSink;
begin
  NewPusher(S).OpenObject.PropertyInteger('a b', 1).PropertyInteger('yes', 2)
    .PropertyInteger('', 3).CloseObject.Flush;
  AssertEquals('a b: 1' + NL + '"yes": 2' + NL + '"": 3' + NL, S.Text);
end;

procedure TTestYaml.ScalarKinds;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenArray.AddNull.AddBoolean(True).AddNumber(1.5).AddInteger(-7).CloseArray
    .Flush;
  AssertEquals('- null' + NL + '- true' + NL + '- 1.5' + NL + '- -7' + NL, S.Text);
  NewPusher(S).AddString('x').Flush;
  AssertEquals('x' + NL, S.Text);
end;

procedure TTestYaml.BigDecimal;
var
  S: TStringSink;
begin
  NewPusher(S)
    .OpenObject
      .PropertyNumber('price', StrToBCD('12345678901234567890.123456789'))
    .CloseObject.Flush;
  AssertEquals('price: 12345678901234567890.123456789' + NL, S.Text);
end;

procedure TTestYaml.DeepNesting;
var
  S: TStringSink;
  P: TNodePusher;
  I: Integer;
begin
  P := NewPusher(S);
  for I := 1 to 2000 do
    P.OpenArray;
  P.AddInteger(1);
  for I := 1 to 2000 do
    P.CloseArray;
  P.Flush;
  AssertTrue(Length(S.Text) > 2000);
end;

initialization
  RegisterTest(TTestYaml);

end.
