{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: yaml emitter
documentation: doc/design.md
notes:
  - block-style YAML with delayed container headers
  - multi-line strings use literal block scalars
  - writes YAML 1.2 text; no %YAML directive is written
---
}
unit Pusher.Emitter.Yaml;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Pusher.Types, Pusher.Emitter;

type
  { One open container. A container is pending until its first child or
    its end. The header of a pending container is not yet written. This
    lets an empty container write in flow form (braces or brackets). }
  TYamlFrame = record
    IsObject: Boolean;
    Count: Integer;
    Indent: Integer;        // column of the items
    FirstInline: Boolean;   // first item continues the "- " of the parent
    Pending: Boolean;
    ParentKind: Integer;    // 0 root, 1 object, 2 array
    Key: UTF8String;            // key in the parent object
    LeadIndent: Integer;    // spaces before the header
  end;

  TYamlEmitter = class(TEmitter)
  private
    FFrames: array of TYamlFrame;
    FDepth: Integer;
    FKey: UTF8String;
    procedure PutIndent(ACount: Integer);
    procedure Materialize(var AFrame: TYamlFrame);
    function LineLead(const AFrame: TYamlFrame): Integer;
    procedure Open(AIsObject: Boolean);
    procedure Close;
    function BeginScalar: Integer;
    procedure Scalar(const AText: UTF8String);
    procedure PutQuoted(const AValue: UTF8String);
    procedure PutBlock(const AValue: UTF8String; AIndent: Integer);
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

{ Plain style when safe, double-quoted style otherwise. The rules follow
  YAML 1.2 (core schema). }
function YamlScalar(const AValue: UTF8String): UTF8String;

implementation

const
  HexDigits: array[0..15] of Char = '0123456789ABCDEF';
  Spaces = '                                                                ';
  Indicators = ['-', '?', ':', ',', '[', ']', '{', '}', '#', '&', '*', '!',
    '|', '>', '''', '"', '%', '@', '`', ' '];

{ The escape text of a character in a double-quoted scalar. }
function EscapeOf(C: Char): UTF8String;
begin
  case C of
    '"': Result := '\"';
    '\': Result := '\\';
    #9: Result := '\t';
    #10: Result := '\n';
    #13: Result := '\r';
  else
    Result := '\x' + HexDigits[Ord(C) shr 4] + HexDigits[Ord(C) and 15];
  end;
end;

function NeedsEscape(C: Char): Boolean; inline;
begin
  Result := (C < ' ') or (C = '"') or (C = '\') or (C = #127);
end;

{ YAML 1.2 does not allow some characters in a document, even escaped
  ones must be written as escapes: the C1 controls U+0080 to U+009F except
  U+0085, the byte order mark U+FEFF, and U+FFFE and U+FFFF. The function
  looks for them in UTF-8 text at position I. It returns the count of bytes
  of the character, or 0 when the character is allowed. }
function Utf8Special(const AValue: UTF8String; I: Integer;
  out AEscape: UTF8String): Integer;
var
  B1, B2: Byte;
begin
  Result := 0;
  B1 := Ord(AValue[I]);
  if (B1 <> $C2) and (B1 <> $EF) then
    Exit;
  if I >= Length(AValue) then
    Exit;
  B2 := Ord(AValue[I + 1]);
  if B1 = $C2 then
  begin
    if (B2 >= $80) and (B2 <= $9F) and (B2 <> $85) then
    begin
      AEscape := '\u00' + HexDigits[B2 shr 4] + HexDigits[B2 and 15];
      Result := 2;
    end;
  end
  else if (I + 1 < Length(AValue)) then
  begin
    if (B2 = $BB) and (AValue[I + 2] = #$BF) then
    begin
      AEscape := '\uFEFF';
      Result := 3;
    end
    else if (B2 = $BF) and (AValue[I + 2] in [#$BE, #$BF]) then
    begin
      if AValue[I + 2] = #$BE then
        AEscape := '\uFFFE'
      else
        AEscape := '\uFFFF';
      Result := 3;
    end;
  end;
end;

{ Used for keys. Values are written into the buffer by PutQuoted. }
function Quoted(const AValue: UTF8String): UTF8String;
var
  I, RunStart, Skip: Integer;
  Escape: UTF8String;
begin
  Result := '"';
  RunStart := 1;
  I := 1;
  while I <= Length(AValue) do
  begin
    Skip := 0;
    if NeedsEscape(AValue[I]) then
    begin
      Escape := EscapeOf(AValue[I]);
      Skip := 1;
    end
    else if AValue[I] >= #$C2 then
      Skip := Utf8Special(AValue, I, Escape);
    if Skip > 0 then
    begin
      Result := Result + Copy(AValue, RunStart, I - RunStart) + Escape;
      RunStart := I + Skip;
      Inc(I, Skip);
    end
    else
      Inc(I);
  end;
  Result := Result + Copy(AValue, RunStart, MaxInt) + '"';
end;

{ True when the text is a word that a YAML reader can read as a non-string:
  null, true, and false (core schema of YAML 1.2, in any case), and also
  the YAML 1.1 words yes, no, on, off, y, and n. The 1.1 words are not
  necessary for YAML 1.2, but a plain scalar with such a word breaks the
  many readers that still follow 1.1. The compare uses no temporary string. }
function IsReservedWord(const AValue: UTF8String): Boolean;
const
  Words: array[0..9] of UTF8String = ('null', '~', 'true', 'false', 'yes', 'no',
    'on', 'off', 'y', 'n');
var
  W, I: Integer;
  Match: Boolean;
begin
  Result := False;
  if Length(AValue) > 5 then
    Exit;
  for W := Low(Words) to High(Words) do
  begin
    if Length(Words[W]) <> Length(AValue) then
      Continue;
    Match := True;
    for I := 1 to Length(AValue) do
      if (Ord(AValue[I]) or $20) <> Ord(Words[W][I]) then
      begin
        Match := False;
        Break;
      end;
    if Match then
      Exit(True);
  end;
end;

{ A number-like text starts with a digit, a sign, or a dot. Those first
  characters are quoted, so no number parse is needed. }
function NeedsQuotes(const AValue: UTF8String): Boolean;
var
  I, N: Integer;
  C: Char;
  Escape: UTF8String;
begin
  Result := True;
  N := Length(AValue);
  if N = 0 then
    Exit;
  C := AValue[1];
  if (C in Indicators) or (C in ['0'..'9', '+', '.']) then
    Exit;
  if AValue[N] in [' ', ':'] then
    Exit;
  for I := 1 to N do
  begin
    C := AValue[I];
    if (C < ' ') or (C = #127) then
      Exit;
    if (C >= #$C2) and (Utf8Special(AValue, I, Escape) > 0) then
      Exit;
    if (C = '#') and (AValue[I - 1] = ' ') then
      Exit;
    if (C = ':') and (I < N) and (AValue[I + 1] = ' ') then
      Exit;
  end;
  Result := IsReservedWord(AValue);
end;

function YamlScalar(const AValue: UTF8String): UTF8String;
begin
  if NeedsQuotes(AValue) then
    Result := Quoted(AValue)
  else
    Result := AValue;
end;

{ A string can be a literal block scalar when it has a line break, its
  first non-empty line does not start with a space, it has no control
  characters except line feed and tab, and no line holds only blanks.
  Other strings use the double-quoted style. }
function CanBlock(const AValue: UTF8String): Boolean;
var
  I, N, LineStart: Integer;
  C: Char;
  HasText, LineHasText: Boolean;
  Escape: UTF8String;
begin
  Result := False;
  N := Length(AValue);
  HasText := False;
  LineHasText := False;
  LineStart := 1;
  for I := 1 to N + 1 do
  begin
    if (I = N + 1) or (AValue[I] = #10) then
    begin
      if (I > LineStart) and not LineHasText then
        Exit;  // a line of blanks only
      LineStart := I + 1;
      LineHasText := False;
      Continue;
    end;
    C := AValue[I];
    if ((C < ' ') and (C <> #9)) or (C = #127) then
      Exit;
    if (C >= #$C2) and (Utf8Special(AValue, I, Escape) > 0) then
      Exit;
    if (C <> ' ') and (C <> #9) then
    begin
      LineHasText := True;
      HasText := True;
    end
    else if (not HasText) and (C = ' ') and (I = LineStart) then
      Exit;  // the first text line starts with a space
  end;
  Result := HasText;
end;

procedure TYamlEmitter.PutIndent(ACount: Integer);
begin
  while ACount > Length(Spaces) do
  begin
    PutBuf(Spaces[1], Length(Spaces));
    Dec(ACount, Length(Spaces));
  end;
  PutBuf(Spaces[1], ACount);
end;

{ Writes the header of a pending container. }
procedure TYamlEmitter.Materialize(var AFrame: TYamlFrame);
begin
  if not AFrame.Pending then
    Exit;
  AFrame.Pending := False;
  case AFrame.ParentKind of
    1:
      begin
        PutIndent(AFrame.LeadIndent);
        Put(AFrame.Key);
        Put(':' + LineEnding);
      end;
    2:
      begin
        PutIndent(AFrame.LeadIndent);
        Put('- ');
      end;
  end;
end;

{ Spaces before an item line of a container. }
function TYamlEmitter.LineLead(const AFrame: TYamlFrame): Integer;
begin
  if AFrame.FirstInline and (AFrame.Count = 0) then
    Result := 0
  else
    Result := AFrame.Indent;
end;

procedure TYamlEmitter.Open(AIsObject: Boolean);
var
  Frame: TYamlFrame;
begin
  Frame.IsObject := AIsObject;
  Frame.Count := 0;
  Frame.Pending := True;
  Frame.Key := '';
  Frame.LeadIndent := 0;
  if FDepth = 0 then
  begin
    Frame.ParentKind := 0;
    Frame.Indent := 0;
    Frame.FirstInline := False;
  end
  else
  begin
    Materialize(FFrames[FDepth - 1]);
    with FFrames[FDepth - 1] do
    begin
      Frame.LeadIndent := LineLead(FFrames[FDepth - 1]);
      Frame.Indent := Indent + 2;
      if IsObject then
      begin
        Frame.ParentKind := 1;
        Frame.Key := FKey;
        Frame.FirstInline := False;
      end
      else
      begin
        Frame.ParentKind := 2;
        Frame.FirstInline := True;
      end;
      Inc(Count);
    end;
  end;
  if FDepth = Length(FFrames) then
    SetLength(FFrames, FDepth * 2 + 8);
  FFrames[FDepth] := Frame;
  Inc(FDepth);
end;

procedure TYamlEmitter.Close;
var
  Frame: TYamlFrame;
  Empty: UTF8String;
begin
  Dec(FDepth);
  Frame := FFrames[FDepth];
  if not Frame.Pending then
    Exit;
  if Frame.IsObject then
    Empty := '{}'
  else
    Empty := '[]';
  case Frame.ParentKind of
    0: Put(Empty + LineEnding);
    1:
      begin
        PutIndent(Frame.LeadIndent);
        Put(Frame.Key);
        Put(': ' + Empty + LineEnding);
      end;
    2:
      begin
        PutIndent(Frame.LeadIndent);
        Put('- ' + Empty + LineEnding);
      end;
  end;
end;

{ Writes the key or the dash of a scalar item. Returns the indent for the
  lines of a block scalar. }
function TYamlEmitter.BeginScalar: Integer;
begin
  if FDepth = 0 then
    Exit(2);
  Materialize(FFrames[FDepth - 1]);
  with FFrames[FDepth - 1] do
  begin
    PutIndent(LineLead(FFrames[FDepth - 1]));
    if IsObject then
    begin
      Put(FKey);
      Put(': ');
    end
    else
      Put('- ');
    Inc(Count);
    Result := Indent + 2;
  end;
end;

procedure TYamlEmitter.Scalar(const AText: UTF8String);
begin
  BeginScalar;
  Put(AText);
  Put(LineEnding);
end;

{ Writes a double-quoted scalar into the buffer. Each run of characters
  that need no escape is copied in one block. }
procedure TYamlEmitter.PutQuoted(const AValue: UTF8String);
var
  I, RunStart, Skip: Integer;
  Escape: UTF8String;
begin
  Put('"');
  RunStart := 1;
  I := 1;
  while I <= Length(AValue) do
  begin
    Skip := 0;
    if NeedsEscape(AValue[I]) then
    begin
      Escape := EscapeOf(AValue[I]);
      Skip := 1;
    end
    else if AValue[I] >= #$C2 then
      Skip := Utf8Special(AValue, I, Escape);
    if Skip > 0 then
    begin
      PutBuf(PChar(AValue)[RunStart - 1], I - RunStart);
      Put(Escape);
      RunStart := I + Skip;
      Inc(I, Skip);
    end
    else
      Inc(I);
  end;
  PutBuf(PChar(AValue)[RunStart - 1], Length(AValue) + 1 - RunStart);
  Put('"' + LineEnding);
end;

{ Writes a literal block scalar. The chomping indicator keeps the exact
  count of trailing line feeds: none (strip), one (clip), or more (keep). }
procedure TYamlEmitter.PutBlock(const AValue: UTF8String; AIndent: Integer);
var
  I, N, LineStart, Trailing: Integer;
begin
  N := Length(AValue);
  Trailing := 0;
  while (Trailing < N) and (AValue[N - Trailing] = #10) do
    Inc(Trailing);
  case Trailing of
    0: Put('|-' + LineEnding);
    1: Put('|' + LineEnding);
  else
    Put('|+' + LineEnding);
  end;
  if Trailing > 0 then
    Dec(N);  // the last line feed ends the last line
  LineStart := 1;
  for I := 1 to N + 1 do
    if (I = N + 1) or (AValue[I] = #10) then
    begin
      if I > LineStart then
      begin
        PutIndent(AIndent);
        PutBuf(PChar(AValue)[LineStart - 1], I - LineStart);
      end;
      Put(LineEnding);
      LineStart := I + 1;
    end;
end;

procedure TYamlEmitter.BeginObject;
begin
  Open(True);
end;

procedure TYamlEmitter.EndObject;
begin
  Close;
end;

procedure TYamlEmitter.BeginArray;
begin
  Open(False);
end;

procedure TYamlEmitter.EndArray;
begin
  Close;
end;

procedure TYamlEmitter.WriteName(const AName: UTF8String);
begin
  Materialize(FFrames[FDepth - 1]);
  FKey := YamlScalar(AName);
end;

procedure TYamlEmitter.WriteString(const AValue: UTF8String);
begin
  if (AValue <> '') and (IndexByte(PChar(AValue)^, Length(AValue), 10) >= 0) then
  begin
    if CanBlock(AValue) then
      PutBlock(AValue, BeginScalar)
    else
    begin
      BeginScalar;
      PutQuoted(AValue);
    end;
  end
  else if NeedsQuotes(AValue) then
  begin
    BeginScalar;
    PutQuoted(AValue);
  end
  else
    Scalar(AValue);
end;

procedure TYamlEmitter.WriteNumber(const AText: UTF8String);
begin
  Scalar(AText);
end;

procedure TYamlEmitter.WriteBoolean(AValue: Boolean);
begin
  if AValue then
    Scalar('true')
  else
    Scalar('false');
end;

procedure TYamlEmitter.WriteNull;
begin
  Scalar('null');
end;

end.
