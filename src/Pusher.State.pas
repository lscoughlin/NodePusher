{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: state
documentation: doc/design.md
notes:
  - document structure checks
---
}
unit Pusher.State;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Pusher.Types;

type
  { Tracks open containers, a pending property name, and the root value.
    Every check raises EPushError. }
  IPushState = interface
    procedure Scalar(const ACall: UTF8String);
    procedure Open(AIsObject: Boolean; const ACall: UTF8String);
    procedure Close(AIsObject: Boolean; const ACall: UTF8String);
    procedure Name(const ACall: UTF8String);
    procedure CheckFlush(const ACall: UTF8String);
  end;

  TPushState = class(TInterfacedObject, IPushState)
  private
    FStack: array of Boolean;  // True when the container is an object
    FDepth: Integer;
    FPendingName: Boolean;
    FRootDone: Boolean;
    procedure ValueStart(const ACall: UTF8String);
  public
    procedure Scalar(const ACall: UTF8String);
    procedure Open(AIsObject: Boolean; const ACall: UTF8String);
    procedure Close(AIsObject: Boolean; const ACall: UTF8String);
    procedure Name(const ACall: UTF8String);
    procedure CheckFlush(const ACall: UTF8String);
  end;

implementation

procedure Fail(const ACall, AMessage: UTF8String);
begin
  raise EPushError.CreateFmt('%s: %s', [ACall, AMessage]);
end;

procedure TPushState.ValueStart(const ACall: UTF8String);
begin
  if FDepth = 0 then
  begin
    if FRootDone then
      Fail(ACall, 'the document already has a root value');
  end
  else if FStack[FDepth - 1] then
  begin
    if not FPendingName then
      Fail(ACall, 'a property name is required inside an object');
    FPendingName := False;
  end;
end;

procedure TPushState.Scalar(const ACall: UTF8String);
begin
  ValueStart(ACall);
  if FDepth = 0 then
    FRootDone := True;
end;

procedure TPushState.Open(AIsObject: Boolean; const ACall: UTF8String);
begin
  ValueStart(ACall);
  if FDepth = Length(FStack) then
    SetLength(FStack, FDepth * 2 + 8);
  FStack[FDepth] := AIsObject;
  Inc(FDepth);
end;

procedure TPushState.Close(AIsObject: Boolean; const ACall: UTF8String);
begin
  if FDepth = 0 then
    Fail(ACall, 'no container is open');
  if FStack[FDepth - 1] <> AIsObject then
    Fail(ACall, 'the open container has a different kind');
  if FPendingName then
    Fail(ACall, 'a property name has no value');
  Dec(FDepth);
  if FDepth = 0 then
    FRootDone := True;
end;

procedure TPushState.Name(const ACall: UTF8String);
begin
  if (FDepth = 0) or not FStack[FDepth - 1] then
    Fail(ACall, 'a property name is allowed only inside an object');
  if FPendingName then
    Fail(ACall, 'the previous property name has no value');
  FPendingName := True;
end;

procedure TPushState.CheckFlush(const ACall: UTF8String);
begin
  if FDepth > 0 then
    Fail(ACall, 'a container is still open');
  if not FRootDone then
    Fail(ACall, 'no root value was written');
end;

end.
