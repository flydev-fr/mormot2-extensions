unit mormot.ext.mcp.tools;

interface

{$I mormot.defines.inc}

uses
  mormot.core.base;

type
  TRunExecutableParams = record
    Path: RawUtf8;
    Args: RawUtf8;
    Wait: boolean;
  end;


implementation


end.
