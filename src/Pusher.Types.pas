{**
---
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
keywords: types
documentation: doc/design.md
notes:
  - token interface and shared types
---
}
unit Pusher.Types;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, FmtBCD;

type
  { Raised for every misuse of the pusher or invalid value. }
  EPushError = class(Exception);

  TPushFormat = (pfJSON, pfYAML);

  TPushOptions = record
    Format: TPushFormat;
    { JSON only. YAML always uses block style. }
    Pretty: Boolean;
    { Spaces per level for pretty JSON. }
    IndentWidth: Integer;
  end;

  { A sink receives one token per call. The pusher has already checked
    that the order of calls is valid. }
  IPushSink = interface
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

function PushOptions(AFormat: TPushFormat = pfJSON; APretty: Boolean = False;
  AIndentWidth: Integer = 2): TPushOptions;

implementation

function PushOptions(AFormat: TPushFormat; APretty: Boolean;
  AIndentWidth: Integer): TPushOptions;
begin
  Result.Format := AFormat;
  Result.Pretty := APretty;
  Result.IndentWidth := AIndentWidth;
end;

end.
