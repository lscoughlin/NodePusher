{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: tests
documentation: doc/design.md
notes:
  - console test runner
---
}
program NodePusherTests;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cwstring,{$ENDIF}
  Classes, consoletestrunner, TestPusherCore, TestJson, TestYaml, TestSinks;

type
  TRunner = class(TTestRunner);

var
  App: TRunner;

begin
  App := TRunner.Create(nil);
  App.Initialize;
  App.Title := 'NodePusher tests';
  App.Run;
  App.Free;
end.
