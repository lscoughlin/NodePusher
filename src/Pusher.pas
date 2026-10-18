{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: pusher
documentation: doc/design.md
notes:
  - fluent streaming writer
---
}
unit Pusher;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  SysUtils, Math, fpjson, FmtBCD, Pusher.Types, Pusher.State;

type
  { The pusher is a record. Copies share the same sink and state. }
  TNodePusher = record
  private
    FSink: IPushSink;
    FState: IPushState;
    procedure Need(const ACall: UTF8String);
    procedure CheckFloat(const ACall: UTF8String; AValue: Double);
  public
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

implementation

constructor TNodePusher.Create(const ASink: IPushSink);
begin
  if ASink = nil then
    raise EPushError.Create('Create: the sink is nil');
  FSink := ASink;
  FState := TPushState.Create;
end;

procedure TNodePusher.Need(const ACall: UTF8String);
begin
  if FState = nil then
    raise EPushError.CreateFmt('%s: the pusher is not created', [ACall]);
end;

procedure TNodePusher.CheckFloat(const ACall: UTF8String; AValue: Double);
begin
  if IsNan(AValue) or IsInfinite(AValue) then
    raise EPushError.CreateFmt('%s: NaN and infinity are not valid numbers', [ACall]);
end;

function TNodePusher.OpenObject: TNodePusher;
begin
  Need('OpenObject');
  FState.Open(True, 'OpenObject');
  FSink.BeginObject;
  Result := Self;
end;

function TNodePusher.CloseObject: TNodePusher;
begin
  Need('CloseObject');
  FState.Close(True, 'CloseObject');
  FSink.EndObject;
  Result := Self;
end;

function TNodePusher.OpenArray: TNodePusher;
begin
  Need('OpenArray');
  FState.Open(False, 'OpenArray');
  FSink.BeginArray;
  Result := Self;
end;

function TNodePusher.CloseArray: TNodePusher;
begin
  Need('CloseArray');
  FState.Close(False, 'CloseArray');
  FSink.EndArray;
  Result := Self;
end;

function TNodePusher.PropertyName(const AName: UTF8String): TNodePusher;
begin
  Need('PropertyName');
  FState.Name('PropertyName');
  FSink.WriteName(AName);
  Result := Self;
end;

function TNodePusher.PropertyString(const AName, AValue: UTF8String): TNodePusher;
begin
  Result := PropertyName(AName).AddString(AValue);
end;

function TNodePusher.PropertyInteger(const AName: UTF8String; AValue: Int64): TNodePusher;
begin
  Result := PropertyName(AName).AddInteger(AValue);
end;

function TNodePusher.PropertyNumber(const AName: UTF8String; AValue: Double): TNodePusher;
begin
  CheckFloat('PropertyNumber', AValue);
  Result := PropertyName(AName).AddNumber(AValue);
end;

function TNodePusher.PropertyNumber(const AName: UTF8String; const AValue: TBCD): TNodePusher;
begin
  Result := PropertyName(AName).AddNumber(AValue);
end;

function TNodePusher.PropertyBoolean(const AName: UTF8String; AValue: Boolean): TNodePusher;
begin
  Result := PropertyName(AName).AddBoolean(AValue);
end;

function TNodePusher.PropertyNull(const AName: UTF8String): TNodePusher;
begin
  Result := PropertyName(AName).AddNull;
end;

function TNodePusher.PropertyNode(const AName: UTF8String; ANode: TJSONData): TNodePusher;
begin
  Result := PropertyName(AName).AddNode(ANode);
end;

function TNodePusher.AddString(const AValue: UTF8String): TNodePusher;
begin
  Need('AddString');
  FState.Scalar('AddString');
  FSink.WriteString(AValue);
  Result := Self;
end;

function TNodePusher.AddInteger(AValue: Int64): TNodePusher;
begin
  Need('AddInteger');
  FState.Scalar('AddInteger');
  FSink.WriteInteger(AValue);
  Result := Self;
end;

function TNodePusher.AddNumber(AValue: Double): TNodePusher;
begin
  Need('AddNumber');
  CheckFloat('AddNumber', AValue);
  FState.Scalar('AddNumber');
  FSink.WriteFloat(AValue);
  Result := Self;
end;

function TNodePusher.AddNumber(const AValue: TBCD): TNodePusher;
begin
  Need('AddNumber');
  FState.Scalar('AddNumber');
  FSink.WriteBcd(AValue);
  Result := Self;
end;

function TNodePusher.AddBoolean(AValue: Boolean): TNodePusher;
begin
  Need('AddBoolean');
  FState.Scalar('AddBoolean');
  FSink.WriteBoolean(AValue);
  Result := Self;
end;

function TNodePusher.AddNull: TNodePusher;
begin
  Need('AddNull');
  FState.Scalar('AddNull');
  FSink.WriteNull;
  Result := Self;
end;

{ Walks a tree in document order and issues the calls a caller could issue
  by hand. The state checks therefore apply to tree input. }
function TNodePusher.AddNode(ANode: TJSONData): TNodePusher;
var
  I: Integer;
  Obj: TJSONObject;
begin
  Need('AddNode');
  if ANode = nil then
    raise EPushError.Create('AddNode: the node is nil');
  case ANode.JSONType of
    jtObject:
      begin
        Obj := TJSONObject(ANode);
        OpenObject;
        for I := 0 to Obj.Count - 1 do
          PropertyName(Obj.Names[I]).AddNode(Obj.Items[I]);
        CloseObject;
      end;
    jtArray:
      begin
        OpenArray;
        for I := 0 to TJSONArray(ANode).Count - 1 do
          AddNode(TJSONArray(ANode).Items[I]);
        CloseArray;
      end;
    jtString: AddString(ANode.AsString);
    jtBoolean: AddBoolean(ANode.AsBoolean);
    jtNull: AddNull;
    jtNumber:
      case TJSONNumber(ANode).NumberType of
        ntInteger, ntInt64: AddInteger(ANode.AsInt64);
        ntQWord: AddNumber(StrToBCD(IntToStr(ANode.AsQWord)));
      else
        AddNumber(ANode.AsFloat);
      end;
  else
    raise EPushError.Create('AddNode: the node type is not supported');
  end;
  Result := Self;
end;

function TNodePusher.Flush: TNodePusher;
begin
  Need('Flush');
  FState.CheckFlush('Flush');
  FSink.Flush;
  Result := Self;
end;

end.
