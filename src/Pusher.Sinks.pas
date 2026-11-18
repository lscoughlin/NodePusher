{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: sinks
documentation: doc/design.md
notes:
  - stream, string, and tree sinks
---
}
unit Pusher.Sinks;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StreamEx, fpjson, FmtBCD, Pusher.Types, Pusher.Emitter,
  Pusher.Emitter.Json, Pusher.Emitter.Yaml;

type
  { Base of the text sinks. It forwards each token to an emitter. }
  TTextSink = class(TInterfacedObject, IPushSink)
  private
    FEmitter: TEmitter;
  protected
    procedure Setup(AStream: TStream; const AOptions: TPushOptions);
  public
    destructor Destroy; override;
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
    procedure Flush; virtual;
  end;

  { Writes text to a stream. The caller owns the stream. }
  TStreamSink = class(TTextSink)
  public
    constructor Create(AStream: TStream; AFormat: TPushFormat = pfJSON); overload;
    constructor Create(AStream: TStream; const AOptions: TPushOptions); overload;
  end;

  { A write-only stream that passes UTF-8 bytes to a TStreamWriter. The
    stream converts the bytes to the encoding of the writer. }
  TWriterStream = class(TStream)
  private
    FWriter: TStreamWriter;
    FUtf8: Boolean;
    FPending: array[0..2] of Byte;
    FPendingLength: Integer;
    procedure Put(const ABytes: TBytes);
  public
    constructor Create(AWriter: TStreamWriter);
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
  end;

  { Writes text through a TStreamWriter. The writer sets the encoding. The
    caller owns the writer and frees it after the sink. Flush also flushes
    the writer. }
  TWriterSink = class(TTextSink)
  private
    FStream: TWriterStream;
    FWriter: TStreamWriter;
  public
    constructor Create(AWriter: TStreamWriter; AFormat: TPushFormat = pfJSON); overload;
    constructor Create(AWriter: TStreamWriter; const AOptions: TPushOptions); overload;
    destructor Destroy; override;
    procedure Flush; override;
  end;

  { Writes text to an internal string. Text is complete after Flush. }
  TStringSink = class(TTextSink)
  private
    FStream: TStringStream;
    function GetText: UTF8String;
  public
    constructor Create(AFormat: TPushFormat = pfJSON); overload;
    constructor Create(const AOptions: TPushOptions); overload;
    destructor Destroy; override;
    property Text: UTF8String read GetText;
  end;

  { Builds a TJSONData tree. The caller owns the tree after TakeRoot. A
    TBCD value is stored as a TJSONFloatNumber and can lose precision. }
  TNodeSink = class(TInterfacedObject, IPushSink)
  private
    FRoot: TJSONData;
    FStack: array of TJSONData;
    FDepth: Integer;
    FName: UTF8String;
    procedure Add(ANode: TJSONData);
    procedure Push(ANode: TJSONData);
    procedure Pop;
  public
    destructor Destroy; override;
    function TakeRoot: TJSONData;
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

implementation

{ TTextSink }

procedure TTextSink.Setup(AStream: TStream; const AOptions: TPushOptions);
begin
  if AOptions.IndentWidth < 0 then
    raise EPushError.Create('IndentWidth must not be negative');
  case AOptions.Format of
    pfJSON: FEmitter := TJsonEmitter.Create(AStream, AOptions);
    pfYAML: FEmitter := TYamlEmitter.Create(AStream, AOptions);
  end;
end;

destructor TTextSink.Destroy;
begin
  FEmitter.Free;
  inherited Destroy;
end;

procedure TTextSink.BeginObject;
begin
  FEmitter.BeginObject;
end;

procedure TTextSink.EndObject;
begin
  FEmitter.EndObject;
end;

procedure TTextSink.BeginArray;
begin
  FEmitter.BeginArray;
end;

procedure TTextSink.EndArray;
begin
  FEmitter.EndArray;
end;

procedure TTextSink.WriteName(const AName: UTF8String);
begin
  FEmitter.WriteName(AName);
end;

procedure TTextSink.WriteString(const AValue: UTF8String);
begin
  FEmitter.WriteString(AValue);
end;

procedure TTextSink.WriteInteger(AValue: Int64);
begin
  FEmitter.WriteNumber(IntToStr(AValue));
end;

procedure TTextSink.WriteFloat(AValue: Double);
begin
  FEmitter.WriteNumber(FormatDouble(AValue));
end;

procedure TTextSink.WriteBcd(const AValue: TBCD);
begin
  FEmitter.WriteNumber(FormatBcd(AValue));
end;

procedure TTextSink.WriteBoolean(AValue: Boolean);
begin
  FEmitter.WriteBoolean(AValue);
end;

procedure TTextSink.WriteNull;
begin
  FEmitter.WriteNull;
end;

procedure TTextSink.Flush;
begin
  FEmitter.Flush;
end;

{ TStreamSink }

constructor TStreamSink.Create(AStream: TStream; AFormat: TPushFormat);
begin
  Create(AStream, PushOptions(AFormat));
end;

constructor TStreamSink.Create(AStream: TStream; const AOptions: TPushOptions);
begin
  inherited Create;
  Setup(AStream, AOptions);
end;

{ TWriterStream }

type
  { Gives access to the protected byte output of TStreamWriter. }
  TWriterAccess = class(TStreamWriter)
  public
    procedure PutBytes(const ABytes: TBytes);
  end;

procedure TWriterAccess.PutBytes(const ABytes: TBytes);
begin
  WriteBytes(ABytes);
end;

constructor TWriterStream.Create(AWriter: TStreamWriter);
begin
  inherited Create;
  FWriter := AWriter;
  FUtf8 := AWriter.Encoding.CodePage = CP_UTF8;
end;

procedure TWriterStream.Put(const ABytes: TBytes);
begin
  if Length(ABytes) > 0 then
    TWriterAccess(FWriter).PutBytes(ABytes);
end;

function TWriterStream.Read(var Buffer; Count: Longint): Longint;
begin
  raise EPushError.Create('A writer stream cannot be read');
  Result := 0;
end;

function TWriterStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  raise EPushError.Create('A writer stream cannot seek');
  Result := 0;
end;

{ The writer gets whole characters only. A write can end in the middle of a
  UTF-8 sequence, so the last bytes of an incomplete sequence wait for the
  next write. }
function TWriterStream.Write(const Buffer; Count: Longint): Longint;
var
  Data, Text: TBytes;
  Total, Keep, Back: Integer;
  U: UTF8String;
begin
  Result := Count;
  if Count <= 0 then
    Exit;
  Data := nil;
  if FUtf8 then
  begin
    SetLength(Data, Count);
    Move(Buffer, Data[0], Count);
    Put(Data);
    Exit;
  end;
  Total := FPendingLength + Count;
  SetLength(Data, Total);
  if FPendingLength > 0 then
    Move(FPending[0], Data[0], FPendingLength);
  Move(Buffer, Data[FPendingLength], Count);
  Keep := 0;
  Back := 1;
  while (Back <= 3) and (Back <= Total) do
  begin
    if Data[Total - Back] and $C0 <> $80 then
    begin
      { a lead byte: it starts an incomplete sequence when too few bytes follow }
      if ((Data[Total - Back] and $E0 = $C0) and (Back < 2)) or
         ((Data[Total - Back] and $F0 = $E0) and (Back < 3)) or
         ((Data[Total - Back] and $F8 = $F0) and (Back < 4)) then
        Keep := Back;
      Break;
    end;
    Inc(Back);
  end;
  FPendingLength := Keep;
  if Keep > 0 then
    Move(Data[Total - Keep], FPending[0], Keep);
  Dec(Total, Keep);
  if Total > 0 then
  begin
    SetLength(U, Total);
    Move(Data[0], U[1], Total);
    Text := FWriter.Encoding.GetBytes(UnicodeString(UTF8Decode(U)));
    Put(Text);
  end;
end;

{ TWriterSink }

constructor TWriterSink.Create(AWriter: TStreamWriter; AFormat: TPushFormat);
begin
  Create(AWriter, PushOptions(AFormat));
end;

constructor TWriterSink.Create(AWriter: TStreamWriter; const AOptions: TPushOptions);
begin
  inherited Create;
  FWriter := AWriter;
  FStream := TWriterStream.Create(AWriter);
  Setup(FStream, AOptions);
end;

destructor TWriterSink.Destroy;
begin
  inherited Destroy;  // frees the emitter first
  FStream.Free;
end;

procedure TWriterSink.Flush;
begin
  inherited Flush;
  FWriter.Flush;
end;

{ TStringSink }

constructor TStringSink.Create(AFormat: TPushFormat);
begin
  Create(PushOptions(AFormat));
end;

constructor TStringSink.Create(const AOptions: TPushOptions);
begin
  inherited Create;
  FStream := TStringStream.Create('');
  Setup(FStream, AOptions);
end;

destructor TStringSink.Destroy;
begin
  inherited Destroy;  // frees the emitter first
  FStream.Free;
end;

function TStringSink.GetText: UTF8String;
begin
  Flush;
  Result := FStream.DataString;
  SetCodePage(RawByteString(Result), CP_UTF8, False);
end;

{ TNodeSink }

destructor TNodeSink.Destroy;
begin
  FRoot.Free;
  inherited Destroy;
end;

function TNodeSink.TakeRoot: TJSONData;
begin
  if FDepth > 0 then
    raise EPushError.Create('TakeRoot: a container is still open');
  if FRoot = nil then
    raise EPushError.Create('TakeRoot: no root value was written');
  Result := FRoot;
  FRoot := nil;
end;

procedure TNodeSink.Add(ANode: TJSONData);
begin
  if FDepth = 0 then
    FRoot := ANode
  else if FStack[FDepth - 1] is TJSONObject then
    TJSONObject(FStack[FDepth - 1]).Add(FName, ANode)
  else
    TJSONArray(FStack[FDepth - 1]).Add(ANode);
end;

procedure TNodeSink.Push(ANode: TJSONData);
begin
  Add(ANode);
  if FDepth = Length(FStack) then
    SetLength(FStack, FDepth * 2 + 8);
  FStack[FDepth] := ANode;
  Inc(FDepth);
end;

procedure TNodeSink.Pop;
begin
  Dec(FDepth);
end;

procedure TNodeSink.BeginObject;
begin
  Push(TJSONObject.Create);
end;

procedure TNodeSink.EndObject;
begin
  Pop;
end;

procedure TNodeSink.BeginArray;
begin
  Push(TJSONArray.Create);
end;

procedure TNodeSink.EndArray;
begin
  Pop;
end;

procedure TNodeSink.WriteName(const AName: UTF8String);
begin
  FName := AName;
end;

procedure TNodeSink.WriteString(const AValue: UTF8String);
begin
  Add(TJSONString.Create(AValue));
end;

procedure TNodeSink.WriteInteger(AValue: Int64);
begin
  Add(TJSONInt64Number.Create(AValue));
end;

procedure TNodeSink.WriteFloat(AValue: Double);
begin
  Add(TJSONFloatNumber.Create(AValue));
end;

procedure TNodeSink.WriteBcd(const AValue: TBCD);
begin
  Add(TJSONFloatNumber.Create(BCDToDouble(AValue)));
end;

procedure TNodeSink.WriteBoolean(AValue: Boolean);
begin
  Add(TJSONBoolean.Create(AValue));
end;

procedure TNodeSink.WriteNull;
begin
  Add(TJSONNull.Create);
end;

procedure TNodeSink.Flush;
begin
end;

end.
