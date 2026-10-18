{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests
documentation: doc/design.md
notes:
  - pusher state and call order tests
---
}
unit TestPusherCore;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Pusher, Pusher.Types, Pusher.Sinks;

type
  TTestPusherCore = class(TTestCase)
  private
    FSink: TStringSink;
    FPusher: TNodePusher;
  protected
    procedure SetUp; override;
  published
    procedure ValueInObjectNeedsName;
    procedure NameInArrayRaises;
    procedure NameAtRootRaises;
    procedure TwoNamesRaise;
    procedure CloseWithoutOpenRaises;
    procedure CloseWrongKindRaises;
    procedure CloseWithPendingNameRaises;
    procedure SecondRootRaises;
    procedure FlushWithOpenContainerRaises;
    procedure FlushWithoutRootRaises;
    procedure NanRaises;
    procedure InfinityRaises;
    procedure UncreatedRecordRaises;
    procedure NilSinkRaises;
    procedure NilNodeRaises;
    procedure CopyShareState;
    procedure RootScalarIsValid;
  end;

implementation

procedure TTestPusherCore.SetUp;
begin
  FSink := TStringSink.Create(pfJSON);
  FPusher := TNodePusher.Create(FSink);
end;

procedure TTestPusherCore.ValueInObjectNeedsName;
begin
  FPusher.OpenObject;
  try
    FPusher.AddString('x');
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.NameInArrayRaises;
begin
  FPusher.OpenArray;
  try
    FPusher.PropertyName('x');
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.NameAtRootRaises;
begin
  try
    FPusher.PropertyName('x');
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.TwoNamesRaise;
begin
  FPusher.OpenObject.PropertyName('a');
  try
    FPusher.PropertyName('b');
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.CloseWithoutOpenRaises;
begin
  try
    FPusher.CloseObject;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.CloseWrongKindRaises;
begin
  FPusher.OpenArray;
  try
    FPusher.CloseObject;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.CloseWithPendingNameRaises;
begin
  FPusher.OpenObject.PropertyName('a');
  try
    FPusher.CloseObject;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.SecondRootRaises;
begin
  FPusher.AddInteger(1);
  try
    FPusher.AddInteger(2);
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.FlushWithOpenContainerRaises;
begin
  FPusher.OpenArray;
  try
    FPusher.Flush;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.FlushWithoutRootRaises;
begin
  try
    FPusher.Flush;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.NanRaises;
begin
  FPusher.OpenArray;
  try
    FPusher.AddNumber(0.0 / 0.0);
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.InfinityRaises;
var
  Zero: Double;
begin
  Zero := 0.0;
  FPusher.OpenObject;
  try
    FPusher.PropertyNumber('x', 1.0 / Zero);
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.UncreatedRecordRaises;
var
  P: TNodePusher;
begin
  FillChar(P, SizeOf(P), 0);
  try
    P.OpenObject;
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.NilSinkRaises;
begin
  try
    TNodePusher.Create(nil);
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.NilNodeRaises;
begin
  try
    FPusher.AddNode(nil);
    Fail('expected EPushError');
  except
    on EPushError do ;
  end;
end;

procedure TTestPusherCore.CopyShareState;
var
  Copy: TNodePusher;
begin
  FPusher.OpenArray;
  Copy := FPusher;
  Copy.AddInteger(1);
  FPusher.AddInteger(2);
  Copy.CloseArray.Flush;
  AssertEquals('[1,2]', FSink.Text);
end;

procedure TTestPusherCore.RootScalarIsValid;
begin
  FPusher.AddString('x').Flush;
  AssertEquals('"x"', FSink.Text);
end;

initialization
  RegisterTest(TTestPusherCore);

end.
