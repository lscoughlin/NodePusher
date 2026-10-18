{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: emitter
documentation: doc/design.md
notes:
  - base class for text emitters and shared formatting
---
}
unit Pusher.Emitter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FmtBCD, Pusher.Types;

type
  { A text emitter formats tokens as text. It buffers the text and writes
    the buffer to a stream on Flush or when the buffer is full. The
    emitter does not own the stream. }
  TEmitter = class
  private
    FStream: TStream;
    FBuffer: PByte;
    FLength: Integer;
  protected
    FOptions: TPushOptions;
    procedure Put(const AText: UTF8String);
    procedure PutBuf(const ABuf; ALength: Integer);
    procedure PutChar(AChar: Char);
  public
    constructor Create(AStream: TStream; const AOptions: TPushOptions);
    destructor Destroy; override;
    procedure BeginObject; virtual; abstract;
    procedure EndObject; virtual; abstract;
    procedure BeginArray; virtual; abstract;
    procedure EndArray; virtual; abstract;
    procedure WriteName(const AName: UTF8String); virtual; abstract;
    procedure WriteString(const AValue: UTF8String); virtual; abstract;
    procedure WriteNumber(const AText: UTF8String); virtual; abstract;
    procedure WriteBoolean(AValue: Boolean); virtual; abstract;
    procedure WriteNull; virtual; abstract;
    procedure Flush;
  end;

{ Shortest text of a Double that reads back as the same value. }
function FormatDouble(AValue: Double): UTF8String;
{ Plain decimal text of a TBCD, with all digits and no exponent. }
function FormatBcd(const AValue: TBCD): UTF8String;

implementation

const
  BufferSize = 65536;

var
  InvariantSettings: TFormatSettings;

constructor TEmitter.Create(AStream: TStream; const AOptions: TPushOptions);
begin
  inherited Create;
  FStream := AStream;
  FOptions := AOptions;
  GetMem(FBuffer, BufferSize);
end;

destructor TEmitter.Destroy;
begin
  FreeMem(FBuffer);
  inherited Destroy;
end;

procedure TEmitter.Put(const AText: UTF8String);
begin
  if AText <> '' then
    PutBuf(AText[1], Length(AText));
end;

procedure TEmitter.PutChar(AChar: Char);
begin
  if FLength >= BufferSize then
    Flush;
  FBuffer[FLength] := Ord(AChar);
  Inc(FLength);
end;

procedure TEmitter.PutBuf(const ABuf; ALength: Integer);
begin
  if ALength <= 0 then
    Exit;
  if FLength + ALength > BufferSize then
  begin
    Flush;
    if ALength > BufferSize then
    begin
      FStream.WriteBuffer(ABuf, ALength);
      Exit;
    end;
  end;
  Move(ABuf, (FBuffer + FLength)^, ALength);
  Inc(FLength, ALength);
end;

procedure TEmitter.Flush;
begin
  if FLength > 0 then
  begin
    FStream.WriteBuffer(FBuffer^, FLength);
    FLength := 0;
  end;
end;

{ Str gives exactly Precision significant digits when the width is
  Precision + 7. The text is " d.dddE+eee". }
function DigitsText(AValue: Double; APrecision: Integer): UTF8String;
begin
  Str(AValue:(APrecision + 7), Result);
end;

function FormatDouble(AValue: Double): UTF8String;
var
  Precision, E, Point, I: Integer;
  Text, Mantissa, Digits, Sign: UTF8String;
begin
  Text := '';
  for Precision := 15 to 17 do
  begin
    Text := Trim(DigitsText(AValue, Precision));
    if StrToFloat(Text, InvariantSettings) = AValue then
      Break;
  end;
  I := Pos('E', Text);
  Mantissa := Copy(Text, 1, I - 1);
  E := StrToInt(Copy(Text, I + 1, MaxInt));
  Sign := '';
  if Mantissa[1] = '-' then
  begin
    Sign := '-';
    Delete(Mantissa, 1, 1);
  end;
  Digits := StringReplace(Mantissa, '.', '', []);
  while (Length(Digits) > 1) and (Digits[Length(Digits)] = '0') do
    SetLength(Digits, Length(Digits) - 1);
  Point := E + 1;  // count of digits before the decimal point
  if (E >= -7) and (E < 21) then
  begin
    if Point <= 0 then
      Result := '0.' + StringOfChar('0', -Point) + Digits
    else if Point >= Length(Digits) then
      Result := Digits + StringOfChar('0', Point - Length(Digits))
    else
      Result := Copy(Digits, 1, Point) + '.' + Copy(Digits, Point + 1, MaxInt);
  end
  else
  begin
    Result := Digits[1];
    if Length(Digits) > 1 then
      Result := Result + '.' + Copy(Digits, 2, MaxInt);
    Result := Result + 'E' + IntToStr(E);
  end;
  Result := Sign + Result;
end;

function FormatBcd(const AValue: TBCD): UTF8String;
begin
  Result := BCDToStr(AValue, InvariantSettings);
end;

initialization
  InvariantSettings := DefaultFormatSettings;
  InvariantSettings.DecimalSeparator := '.';
  InvariantSettings.ThousandSeparator := #0;

end.
