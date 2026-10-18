{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: json emitter
documentation: doc/design.md
notes:
  - compact and pretty JSON
---
}
unit Pusher.Emitter.Json;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pusher.Types, Pusher.Emitter;

type
  TJsonEmitter = class(TEmitter)
  private
    FIsObject: array of Boolean;
    FCount: array of Integer;
    FDepth: Integer;
    FAfterName: Boolean;
    procedure Newline;
    procedure PutQuoted(const AValue: UTF8String);
    procedure BeforeValue;
    procedure Push(AIsObject: Boolean);
    procedure Pop;
  public
    procedure BeginObject; override;
    procedure EndObject; override;
    procedure BeginArray; override;
    procedure EndArray; override;
    procedure WriteName(const AName: UTF8String); override;
    procedure WriteString(const AValue: UTF8String); override;
    procedure WriteNumber(const AText: UTF8String); override;
    procedure WriteBoolean(AValue: Boolean); override;
    procedure WriteNull; override;
  end;

implementation

const
  HexDigits: array[0..15] of Char = '0123456789ABCDEF';

{ Copies each run of characters that need no escape in one block. The loop
  reads through a PChar. Indexing a UTF8String is much slower. }
procedure TJsonEmitter.PutQuoted(const AValue: UTF8String);
var
  Text, Run: PChar;
  Stop: PChar;
  C: Char;
begin
  PutChar('"');
  Text := PChar(AValue);
  Run := Text;
  Stop := Text + Length(AValue);
  while Text < Stop do
  begin
    C := Text^;
    if (C >= ' ') and (C <> '"') and (C <> '\') then
    begin
      Inc(Text);
      Continue;
    end;
    PutBuf(Run^, Text - Run);
    Inc(Text);
    Run := Text;
    case C of
      '"': Put('\"');
      '\': Put('\\');
      #8: Put('\b');
      #9: Put('\t');
      #10: Put('\n');
      #12: Put('\f');
      #13: Put('\r');
    else
      Put('\u00' + HexDigits[Ord(C) shr 4] + HexDigits[Ord(C) and 15]);
    end;
  end;
  PutBuf(Run^, Stop - Run);
  PutChar('"');
end;

procedure TJsonEmitter.Newline;
begin
  if FOptions.Pretty then
    Put(LineEnding + StringOfChar(' ', FDepth * FOptions.IndentWidth));
end;

{ Writes the separator that belongs before a value. A value after a name
  needs none, because WriteName already wrote it. }
procedure TJsonEmitter.BeforeValue;
begin
  if FAfterName then
    FAfterName := False
  else if FDepth > 0 then
  begin
    if FCount[FDepth - 1] > 0 then
      Put(',');
    Inc(FCount[FDepth - 1]);
    Newline;
  end;
end;

procedure TJsonEmitter.Push(AIsObject: Boolean);
begin
  if FDepth = Length(FIsObject) then
  begin
    SetLength(FIsObject, FDepth * 2 + 8);
    SetLength(FCount, FDepth * 2 + 8);
  end;
  FIsObject[FDepth] := AIsObject;
  FCount[FDepth] := 0;
  Inc(FDepth);
end;

procedure TJsonEmitter.Pop;
var
  Had: Boolean;
begin
  Dec(FDepth);
  Had := FCount[FDepth] > 0;
  if Had then
    Newline;
end;

procedure TJsonEmitter.BeginObject;
begin
  BeforeValue;
  Put('{');
  Push(True);
end;

procedure TJsonEmitter.EndObject;
begin
  Pop;
  Put('}');
end;

procedure TJsonEmitter.BeginArray;
begin
  BeforeValue;
  Put('[');
  Push(False);
end;

procedure TJsonEmitter.EndArray;
begin
  Pop;
  Put(']');
end;

procedure TJsonEmitter.WriteName(const AName: UTF8String);
begin
  if FCount[FDepth - 1] > 0 then
    Put(',');
  Inc(FCount[FDepth - 1]);
  Newline;
  PutQuoted(AName);
  if FOptions.Pretty then
    Put(': ')
  else
    Put(':');
  FAfterName := True;
end;

procedure TJsonEmitter.WriteString(const AValue: UTF8String);
begin
  BeforeValue;
  PutQuoted(AValue);
end;

procedure TJsonEmitter.WriteNumber(const AText: UTF8String);
begin
  BeforeValue;
  Put(AText);
end;

procedure TJsonEmitter.WriteBoolean(AValue: Boolean);
begin
  BeforeValue;
  if AValue then
    Put('true')
  else
    Put('false');
end;

procedure TJsonEmitter.WriteNull;
begin
  BeforeValue;
  Put('null');
end;

end.
