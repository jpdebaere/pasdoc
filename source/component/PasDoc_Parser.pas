{ @abstract(provides all the parsing functionality of pasdoc)
  @author(Ralf Junker (delphi@zeitungsjunge.de))
  @author(Marco Schmidt (marcoschmidt@geocities.com))
  @author(Johannes Berg <johannes@sipsolutions.de>)
  @author(Michalis Kamburelis)
  @cvs($Date$)

  Parsing implements most of the functionality of the pasdoc program.

  It provides the @link(TParser) object, which scans the command line parameters
  for file names and switches and then starts collecting information from those
  files, issueing warnings to standard out if necessary. }

unit PasDoc_Parser;

{$I DEFINES.INC}

interface

uses
  Classes,
  PasDoc_Types,
  PasDoc_Items,
  PasDoc_Scanner,
  PasDoc_Tokenizer,
  StringVector;

type
  { Parser class that will process a complete unit file and all of its
    include files, regarding directives.
    When creating this object constructor @link(Create) takes as an argument 
    an input stream and a list of directives.
    Parsing work is done by calling @link(ParseUnit) method.
    If no errors appear, should return a @link(TPasUnit) object with
    all information on the unit. 
    
    Things that parser inits in items it returns:
    
    @unorderedList(
      @item(Of every TPasItem :
        Name, RawDescription, Visibility, IsDeprecated, IsPlatformSpecific, 
        IsLibrarySpecific, FullDeclararation (note: for now not all items
        get sensible FullDeclararation, but the intention is to improve this
        over time; see @link(TPasItem.FullDeclaration) to know where 
        FullDeclararation is available now).

        Note to IsDeprecated: parser inits it basing on hint directive
        "deprecated" presence in source file; it doesn't handle the fact 
        that @@deprecated tag may be specified inside RawDescription.

        Note to RawDescription: parser inits them from user's comments
        that preceded given item in source file.
        It doesn't handle the fact that @@member and @@value tags
        may also assign RawDescription for some item.)
      
      @item Of TPasCio: Ancestors, Fields, Methods, Properties, MyType.
      
      @item Of TPasEnum: Members.
      
      @item Of TPasMethod: What.
      
      @item Of TPasVarConst: FullDeclaration.
      
      @item(Of TPasProperty: IndexDecl, FullDeclaration.
        PropType (only if was specified in property declaration).
        It was intended that parser will also set Default,
        NoDefault, StoredId, DefaultId, Reader, Writer attributes, 
        but it's still not implemented.)
      
      @item(Of TPasUnit; UsesUnits, Types, Variables, CIOs, Constants,
        FuncsProcs.)
    )
    
    It doesn't init other values. 
    E.g. AbstractDescription or DetailedDescription of TPasItem 
    should be inited while expanding this item's tags.
    E.g. SourceFileDateTime and SourceFileName of TPasUnit must
    be set by other means.

    TODO --- for now it's not really consistent how the errors in parsing
    are reported. Some errors cause ParseXxx methods to exit with false,
    some errors cause raising an exception. }
  TParser = class
  private
    FImplicitVisibility: TImplicitVisibility;
    
    procedure SetCommentMarkers(const Value: TStringList);
    
    { Skips all whitespace and comments and while it sees some hint directive
      (platform, library, deprecated) it consumes it, sets appropriate
      property of Item (IsPlatformSpecific, IsLibrarySpecific or IsDeprecated)
      to true and goes further.
      
      Stops when PeekNextToken returns some non-whitespace non-comment 
      non-hint-directive token. }
    procedure ParseHintDirectives(Item: TPasItem);
  protected
    { Last comment found in input or nil if no comment available.
      Will be modified by @link(GetLastComment).
      Always LastCommentToken.MyType is in TokenCommentTypes
      (as long as LastCommentToken <> nil). }
    LastCommentToken: TToken;
    { The underlying scanner object. }
    Scanner: TScanner;
    FOnMessage: TPasDocMessageEvent;
    FVerbosity: Cardinal;
    FCommentMarkers: TStringList;
    FMarkersOptional: boolean;
    FShowVisibilities: TVisibilities;

    procedure DoError(const AMessage: string; 
      const AArguments: array of const);
    procedure DoMessage(const AVerbosity: Cardinal; const MessageType:
      TMessageType; const AMessage: string; const AArguments: array of const);

    { Clears the last comment token. Should be issued soon after
      @link(GetLastComment) was called with @code(ClearLastComment) set to
      @False. }
    procedure ClearLastComment;
    
    { Extracts the documentation comment from T.
      Always T.MyType must be within TokenCommentTypes.
    
      If T = nil, the Result will be an empty string.
      The comment is intended to be a "documentation comment",
      i.e. we intend to put it inside output documentation.
      So comment markers, if present, 
      are removed from the beginning and end of the data.
      Also, if comment markers were required but were not present,
      then this returns empty string.
      
      If FreeToken is @True, @Name frees t.
      Otherwise, T stays untouched for further use. }
    function ExtractDocComment(const FreeToken: Boolean;
      var t: TToken): string;
      
    { Returns the last comment that was found in input. If there was none, the
      Result will be an empty string. If ClearLastComment is @True, @Name clears
      the last comment. Otherwise, it stays untouched for further use. }
    function GetLastComment(const AClearLastComment: Boolean): String;

    { Reads tokens and throws them away as long as they are either whitespace
      or comments.
      
      Sets WhitespaceCollector to all the whitespace that was skipped.
      (Does @italic(not) append them to WhitespaceCollector,
      it @italic(sets) WhitespaceCollector to them, deleting previous
      WhitespaceCollector value.)
      
      Comments are collected to LastCommentToken, so that you can
      use GetLastComment.

      Returns non-white token that was found.
      This token is equal to @code(Scanner.PeekToken).
      Note that this token was @italic(peeked)
      from the stream, i.e. the caller is still responsible for doing 
      @code(Scanner.ConsumeToken).
      Calling this method twice in a row will return the same thing.
      
      Always returns something non-nil (will raise exception in case
      of problems, e.g. when stream ended). }
    function PeekNextToken(out WhitespaceCollector: string): TToken; overload;
    
    { Same thing as PeekNextToken(Dummy) }
    function PeekNextToken: TToken; overload;
        
    { Just like @link(PeekNextToken), but returned token is already consumed.
      Next call to @name will return next token. }
    function GetNextToken(out WhitespaceCollector: string): TToken; overload;
    
    { Just like @link(PeekNextToken), but returned token is already consumed.
      Moreover, whitespace collected is appended to 
      WhitespaceCollectorItem.FullDeclaration
      (does not delete previous WhitespaceCollectorItem.FullDeclaration value, 
      it only appends to it). }
    function GetNextToken(WhitespaceCollectorItem: TPasItem): TToken; overload;
    
    function GetNextToken: TToken; overload;
    
    function ParseArguments(var a: string): Boolean;
    { Parses a constructor, a destructor, a function or a procedure.
      Resulting @link(TPasMethod) item will be returned in M.
      
      ClassKeywordString contains the keyword 'class'
      in the exact spelling as it was found in input,
      for class methods. Else it contains ''.
      
      KeyWordString contains the keyword constructor, destructor, 
      function or procedure in the exact spelling as it was found in input.
      You can specify KeyWordString = '', this way you avoid including
      such keyword at the beginning of returned M.FullDeclaration.
      
      Key contains one of the KEY_xxx constants for the What field of the
      resulting method object. Yes, this is the keyword that should correspond 
      to KeyWordString.
      
      D may contain a description or nil. }
    function ParseCDFP(out M: TPasMethod; 
      const ClassKeywordString: string;
      const KeyWordString: string; Key: TKeyWord;
      d: string; const NeedName: boolean): Boolean;
    { Parses a class, an interface or an object.
      U is the unit this item will be added to on success.
      N is the name of this item.
      CIOType describes if item is class, interface or object.
      D may contain a description or nil. }
    function ParseCIO(const U: TPasUnit; const CioName: string; CIOType:
      TCIOType; d: string; const IsInRecordCase: boolean): Boolean;
    { }
    function ParseRecordCase(const R: TPasCio; const SubCase: boolean): boolean;
    function ParseConstant(const U: TPasUnit; 
      const ConstantName: string): Boolean;
    function ParseInterfaceSection(const U: TPasUnit): Boolean;
    function ParseProperty(out p: TPasProperty): Boolean;
    function ParseType(const U: TPasUnit; var t: TToken): Boolean;
    
    { This assumes that you just read left parenthesis starting
      an enumerated type. It finishes parsing of TPasEnum,
      returning is as P. }
    function ParseEnum(out p: TPasEnum; 
      const Name, RawDescription: string): boolean;

    function ParseUses(const U: TPasUnit): Boolean;
    
    function ParseVariables(const U: TPasUnit; var t: TToken): Boolean;
    
    { Parse one variables or fields clause 
      ("one clause" is something like 
        NAME1, NAME2, ... : TYPE;
      i.e. a list of variables/fields sharing one type declaration.)
      @param Items If Items <> nil then it adds parsed variables/fields to Items.
      @param(Visibility will be assigned to Visibility of 
       each variable/field instance.) }
    function ParseFieldsVariables(Items: TPasItems; var t: TToken;
      OfObject: boolean; Visibility: TVisibility): Boolean;
    
    { Read all tokens until you find a semicolon at brace-level 0 and
      end-level (between "record" and "end" keywords) also 0.

      Alternatively, also stops before reading "end" without beginning
      "record" (so it can handle some cases where declaration doesn't end
      with semicolon).

      If you pass Item <> nil then all read data will be 
      appended to Item.FullDeclaration. Also Item.IsLibrarySpecific,
      Item.IsPlatformSpecific and Item.IsDeprecated will be set to true
      if appropriate hint directive will occur in source file. }    
    function SkipDeclaration(const Item: TPasItem): Boolean;
  public
    { Create a parser, initialize the scanner with input stream S.
      All strings in SD are defined compiler directives. }
    constructor Create(
      const InputStream: TStream;
      const Directives: TStringVector;
      const IncludeFilePaths: TStringVector;
      const OnMessageEvent: TPasDocMessageEvent;
      const VerbosityLevel: Cardinal;
      const AStreamName: string;
      const AHandleMacros: boolean);
      
    { Release all dynamically allocated memory. }
    destructor Destroy; override;
    
    procedure ParseUnit(var U: TPasUnit);

    property OnMessage: TPasDocMessageEvent read FOnMessage write FOnMessage;
    property CommentMarkers: TStringList read FCommentMarkers write SetCommentMarkers;
    property MarkersOptional: boolean read fMarkersOptional write fMarkersOptional;
    property ShowVisibilities: TVisibilities 
      read FShowVisibilities write FShowVisibilities;
      
    { See command-line option @--implicit-visibility documentation at
      [http://pasdoc.sipsolutions.net/ImplicitVisibilityOption] }
    property ImplicitVisibility: TImplicitVisibility
      read FImplicitVisibility write FImplicitVisibility;
  end;

implementation

uses
  SysUtils,
  Utils;

{ ---------------------------------------------------------------------------- }
{ TParser }
{ ---------------------------------------------------------------------------- }

procedure TParser.ClearLastComment;
begin
  if Assigned(LastCommentToken) then begin
    LastCommentToken.Free;
    LastCommentToken := nil;
  end;
end;

constructor TParser.Create(
  const InputStream: TStream;
  const Directives: TStringVector;
  const IncludeFilePaths: TStringVector;
  const OnMessageEvent: TPasDocMessageEvent;
  const VerbosityLevel: Cardinal;
  const AStreamName: string;
  const AHandleMacros: boolean);
begin
  inherited Create;
  FOnMessage := OnMessageEvent;
  FVerbosity := VerbosityLevel;

  Scanner := TScanner.Create(InputStream, OnMessageEvent, 
    VerbosityLevel, AStreamName, AHandleMacros);
  Scanner.AddSymbols(Directives);
  Scanner.IncludeFilePaths := IncludeFilePaths;
  FCommentMarkers := TStringlist.Create;
end;

{ ---------------------------------------------------------------------------- }

destructor TParser.Destroy;
begin
  FCommentMarkers.Free;
  Scanner.Free;
  LastCommentToken.Free;
  inherited;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.DoError(const AMessage: string; 
  const AArguments: array of const);
begin
  raise EPasDoc.Create(AMessage, AArguments, 1);
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.DoMessage(const AVerbosity: Cardinal; const MessageType:
  TMessageType; const AMessage: string; const AArguments: array of const);
begin
  if (AVerbosity <= FVerbosity) and Assigned(FOnMessage) then
    FOnMessage(MessageType, Format(AMessage, AArguments), AVerbosity);
end;

{ ---------------------------------------------------------------------------- }
function TParser.ExtractDocComment(const FreeToken: Boolean; 
  var t: TToken): string;
var
  l: Integer;
  i: integer;
  Marker: string;
begin
  if Assigned(t) then 
  begin
    Result := t.CommentContent;
    if FreeToken then 
    begin
      t.Free;
      t := nil;
    end;
  end else
    Result := '';

  if (Result = '') or (CommentMarkers.Count = 0) then
    exit;

  for i := 0 to CommentMarkers.Count-1 do begin
    Marker := CommentMarkers[i];
    l := Length(Marker);
    if (Length(Result) >= l) and (Copy(Result, 1, l) = Marker) then begin
      Delete(Result, 1, l);
      exit;
    end;
  end;
  if not MarkersOptional then
    Result := '';
end;

function TParser.GetLastComment(const AClearLastComment: Boolean): string;
begin
  result := ExtractDocComment(AClearLastComment, LastCommentToken);
end;

{ ---------------------------------------------------------------------------- }

function TParser.GetNextToken(out WhitespaceCollector: string): TToken;
begin
  Result := PeekNextToken(WhitespaceCollector);
  Scanner.ConsumeToken;
end;

function TParser.GetNextToken(WhitespaceCollectorItem: TPasItem): TToken;
var
  WhitespaceCollector: string;
begin
  Result := GetNextToken(WhitespaceCollector);
  WhitespaceCollectorItem.FullDeclaration := 
    WhitespaceCollectorItem.FullDeclaration + WhitespaceCollector;
end;

function TParser.GetNextToken: TToken;
var
  LDummy: string;
begin
  Result := GetNextToken(LDummy);
end;

function TParser.ParseArguments(var a: string): Boolean;
var
  Finished: Boolean;
  t: TToken;
begin
  Finished := False;
  a := '';
  t := nil;
  repeat
    t := Scanner.GetToken;

    if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType =
      SYM_RIGHT_PARENTHESIS) then begin
      Finished := True
    end else begin
      if (t.MyType = TOK_SYMBOL) and
        ((t.Info.SymbolType = SYM_COLON) or
        (t.Info.SymbolType = SYM_COMMA) or
        (t.Info.SymbolType = SYM_SEMICOLON)) then begin
        if (Length(a) > 0) and (a[Length(a)] = ' ') then
          SetLength(a, Length(a) - 1);
        a := a + t.Data;
      end
      else if (t.MyType = TOK_WHITESPACE) then begin
        if (Length(a) > 0) and (a[Length(a)] <> ' ') then a := a + ' ';
      end
      else if t.MyType in TokenCommentTypes + [TOK_DIRECTIVE] then
        begin
            { ignore }
      end
      else { otherwise copy }
        a := a + t.Data;
    end;
      FreeAndNil(t);
  until Finished;
  ParseArguments := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseCDFP(out M: TPasMethod; 
  const ClassKeywordString: string;
  const KeyWordString: string; Key: TKeyword; 
  d: string; const NeedName: boolean): Boolean;
var
  IsSemicolon: Boolean;
  t: TToken;
  level: Integer;
  InvalidType: boolean;
begin
  Result := False;
  M := TPasMethod.Create;
  M.RawDescription := d;
  t := nil;
  case Key of
    KEY_CONSTRUCTOR: M.What := METHOD_CONSTRUCTOR;
    KEY_DESTRUCTOR:  M.What := METHOD_DESTRUCTOR;
    KEY_FUNCTION:    M.What := METHOD_FUNCTION;
    KEY_PROCEDURE:   M.What := METHOD_PROCEDURE;
    KEY_OPERATOR:    M.What := METHOD_OPERATOR;
  else
    DoError('FATAL ERROR: CDFP got invalid key.', []);
  end;
  
  if ClassKeyWordString <> '' then
    M.FullDeclaration :=  ClassKeyWordString + ' ';
  M.FullDeclaration := M.FullDeclaration + KeyWordString;

  { next non-wc token must be the name }
  if NeedName then
  begin
    try
      t := GetNextToken;
    except
      M.Free;
      raise;
    end;
    if (Key = KEY_OPERATOR) then
    begin
      InvalidType := (t.MyType <> TOK_SYMBOL);
    end
    else
    begin
      InvalidType := (t.MyType <> TOK_IDENTIFIER);
    end;

    if InvalidType then begin
      M.Free;
      FreeAndNil(t);
      DoError('Could not get next identifier', []);
    end;
    M.Name := t.Data;
    DoMessage(5, mtInformation, 'Parsing %s "%s"',
      [LowerCase(KeyWordArray[Key]), M.Name]);
    M.FullDeclaration := M.FullDeclaration + ' ' + M.Name;
    FreeAndNil(t);
  end;

  { copy tokens until first semicolon with parenthesis level zero }
  level := 0;
  repeat
    t := Scanner.GetToken;
    if not (t.MyType in TokenCommentTypes) then
      case t.MyType of
        TOK_WHITESPACE:
          begin
            { add exactly *one space* at the end of M.FullDeclaration }
            if Length(M.FullDeclaration) > 0 then begin
              if (M.FullDeclaration[Length(M.FullDeclaration)] <> ' ') then
                M.FullDeclaration := M.FullDeclaration + ' ';
            end;
          end
        else
          M.FullDeclaration := M.FullDeclaration + t.Data;
      end;
    if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType = SYM_LEFT_PARENTHESIS)
      then Inc(level);
    if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType = SYM_RIGHT_PARENTHESIS)
      then Dec(level);
    IsSemicolon := (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType =
      SYM_SEMICOLON);
    FreeAndNil(t);
  until IsSemicolon and (Level = 0);
  
  { first get non-WC token - if it is not an identifier in SD_SET put it back
    into stream and leave; otherwise copy tokens until semicolon }
  repeat
    FreeAndNil(t);
    try
      t := GetNextToken;
    except
      M.Free;
      raise;
    end;
    
    if t.MyType = TOK_IDENTIFIER then
    begin
      case t.Info.StandardDirective of
        SD_ABSTRACT, SD_ASSEMBLER, SD_CDECL, SD_DYNAMIC, SD_EXPORT,
          SD_FAR, SD_FORWARD, SD_NEAR, SD_OVERLOAD, SD_OVERRIDE, SD_INLINE,
          SD_PASCAL, SD_REGISTER, SD_SAFECALL, SD_STDCALL, SD_REINTRODUCE, SD_VIRTUAL,
          SD_VARARGS:
          begin
            M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
            FreeAndNil(t);

            try
              t := GetNextToken;
            except
              M.Free;
              raise
            end;
          end;

        { * External declarations might be followed by a string constant.
          * Messages are followed by an integer constant between 1 and 49151 which
            specifies the message ID. }
        SD_EXTERNAL, SD_MESSAGE, SD_NAME:
          begin
            M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
            FreeAndNil(t);

            // Keep on reading up to the next semicolon or declaration
            repeat
              try
                t := GetNextToken;
              except
                M.Free;
                raise;
              end;

              if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType = SYM_SEMICOLON) then begin
                Break
              end else begin
                if t.MyType = TOK_IDENTIFIER then 
                  case t.Info.StandardDirective of
                    SD_ABSTRACT, SD_ASSEMBLER, SD_CDECL, SD_DYNAMIC, SD_EXPORT, SD_EXTERNAL,
                      SD_FAR, SD_FORWARD, SD_NAME, SD_NEAR, SD_OVERLOAD, SD_OVERRIDE,
                      SD_PASCAL, SD_REGISTER, SD_SAFECALL, SD_STDCALL, SD_REINTRODUCE, SD_VIRTUAL:
                      begin
                        // FScanner.UnGetToken(t);
                        Break;
                      end;
                  end;

                M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
                FreeAndNil(t);
              end;
            until False;
          end;
        SD_DEPRECATED: begin
          M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
          M.IsDeprecated := True;
          FreeAndNil(t);
          t := GetNextToken;
        end;
        SD_PLATFORM: begin
          M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
          M.IsPlatformSpecific := True;
          FreeAndNil(t);
          t := GetNextToken;
        end;
      else
        begin
          Scanner.UnGetToken(t);
          Break;
        end;
      end; // case
    end else
    if t.MyType = TOK_KEYWORD then 
    begin
      case t.Info.KeyWord of 
        KEY_INLINE: begin
            M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
            FreeAndNil(t);
            t := GetNextToken;
          end;
        KEY_LIBRARY:
          begin
            M.FullDeclaration := M.FullDeclaration + ' ' + t.Data;
            M.IsLibrarySpecific := True;
            FreeAndNil(t);
            t := GetNextToken;
          end;
        else 
          begin
            Scanner.UnGetToken(t);
            Break;        
          end;
      end;
    end else
    begin
      Scanner.UnGetToken(t);
      Break;
    end;

    { Apparently, the Delphi compiler does NOT enforce that
      directives must be separated and be terminated by a semicolon,
      even though Delphi help consistently uses them consistently.
      However, we take the compiler as a reference and try to mimic its behaviour. }
    { Is current token a semicolon? }
    if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType = SYM_SEMICOLON) then
      M.FullDeclaration := M.FullDeclaration + ';'
    else begin
      M.FullDeclaration := M.FullDeclaration + ' ';
      Scanner.UnGetToken(t);
    end;

  until False;
  Result := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseCIO(const U: TPasUnit; const CioName: string; CIOType:
  TCIOType; d: string; const IsInRecordCase: boolean): Boolean;

  { Parse fields clause, i.e. something like
      NAME1, NAME2, ... : TYPE;
    If AddToFields then adds parsed fields to i.Fields.
    Visibility of created fields is set to given Visibility parameter. }
  function ParseFields(var t: TToken; 
    i: TPasCio; AddToFields: boolean; Visibility: TVisibility): boolean;
  var Items: TPasItems;
  begin
    if AddToFields then
      Items := i.Fields else
      Items := nil;
    Result := ParseFieldsVariables(Items, t, true, Visibility);
  end;
  
var
  Finished: Boolean;
  i: TPasCio;
  M: TPasMethod;
  p: TPasProperty;
  s: string;
  Visibility: TVisibility;
  t: TToken;
  ClassKeyWordString: string;
begin
  t := nil;
  Result := False;
  DoMessage(5, mtInformation, 'Parsing class/interface/object "%s"', [CioName]);
  i := nil;
  try
    t := GetNextToken;

    { Test for forward class definition here:
        class MyClass = class;
      with no ancestor or class members listed after the word class. }
    if t.IsSymbol(SYM_SEMICOLON) then begin
      Result := True; // No error, continue the parsing.
      t.Free;
      Exit;
    end;

    i := TPasCio.Create;
    i.Name := CioName;
    i.RawDescription := d;
    i.MyType := CIOType;
    { get all ancestors; remember, this could look like
      TNewClass = class ( Classes.TClass, MyClasses.TFunkyClass, MoreClasses.YAC) ... end;
      All class ancestors are supposed to be included in the docs!
    }
    { TODO -otwm :
      That's not quite true since multiple inheritance is not supported by 
       Delphi/Kylix or FPC. Every entry but the first must be an interface. }
    if t.IsSymbol(SYM_LEFT_PARENTHESIS) then begin
        { optional ancestor introduced by ( }
      FreeAndNil(t);
      Finished := False;
      { outer repeat loop: one ancestor per pass }
      repeat
        FreeAndNil(t);
        t := GetNextToken;

        if t.MyType = TOK_IDENTIFIER then begin { an ancestor }
          s := t.Data;
              { inner repeat loop: one part of the ancestor per name }
          repeat
            FreeAndNil(t);
            t := Scanner.GetToken;
            if not t.IsSymbol(SYM_PERIOD) then begin
              Scanner.UnGetToken(t);
              t := nil;
              Break; { leave inner repeat loop }
            end;
            FreeAndNil(t);
            s := s + '.';
            t := Scanner.GetToken;
            if t.MyType <> TOK_IDENTIFIER then
              DoError('%s: expected class, object or interface in ancestor' +
                ' declaration.', [Scanner.GetStreamInfo]);

            s := s + t.Data;
          until False;
          i.Ancestors.Add(s);
        end else begin
          if (t.IsSymbol(SYM_COMMA)) then
              { comma, separating two ancestors } begin
            FreeAndNil(t);
          end else begin
            Finished := t.IsSymbol(SYM_RIGHT_PARENTHESIS);
            FreeAndNil(t);
            if not Finished then
              DoError('%s: Error - ")" expected.', [Scanner.GetStreamInfo]);
          end;
        end;
      until Finished;
    end else begin
      Scanner.UnGetToken(t);
      case i.MyType of
        CIO_CLASS: begin
          if not SameText(i.Name, 'tobject') then begin
            i.Ancestors.Add('TObject');
          end;
        end;
        CIO_SPINTERFACE: begin
          if not SameText(i.Name, 'idispinterface') then begin
            i.Ancestors.Add('IDispInterface');
          end;
        end;
        CIO_INTERFACE: begin
          if not SameText(i.Name, 'iinterface') then begin
            i.Ancestors.Add('IInterface');
          end;
        end;
        CIO_OBJECT: begin
          if not SameText(i.Name, 'tobject') then begin
            i.Ancestors.Add('TObject');
          end;
        end;
      end;
    end;
    t := GetNextToken;
    
    if (t.IsSymbol(SYM_LEFT_BRACKET)) then begin
      FreeAndNil(t);
      
      { for the time being, we throw away the ID itself }
      t := GetNextToken;
      if (t.MyType <> TOK_STRING) and (t.MyType <> TOK_IDENTIFIER) then
        DoError('%s: Error - literal String or identifier as interface ID expected.', [Scanner.GetStreamInfo]);
      FreeAndNil(t);
      
      t := GetNextToken;
      if not t.IsSymbol(SYM_RIGHT_BRACKET) then
        DoError('%s: Error - "]" expected.', [Scanner.GetStreamInfo]);
    end else begin
      Scanner.UnGetToken(t);
    end;

    { Visibility of members at the beginning of a class declaration
      that don't have a specified visibility is controlled
      by ImplicitVisibility value. }
    case ImplicitVisibility of
      ivPublic:
        if Scanner.SwitchOptions['M'] then 
          Visibility := viPublished else 
          Visibility := viPublic;
      ivPublished:
        Visibility := viPublished;
      ivImplicit:
        Visibility := viImplicit;
      else raise EInternalError.Create('ImplicitVisibility = ??');
    end;

    { now collect methods, fields and properties }
    
    { This is needed to include ClassKeyWordString in 
      class methods declarations. }
    ClassKeyWordString := '';

    Finished := False;
    repeat
      FreeAndNil(t);
      try
        t := GetNextToken;
      except
        i.Free;
        raise;
      end;
      if (t.IsSymbol(SYM_SEMICOLON)) then begin
          { A forward declaration of type "name = class(ancestor);" }
        FreeAndNil(t);
        if Assigned(U) then U.AddCIO(i);
        Result := True;
        Exit;
      end
      else
        if (t.MyType = TOK_KEYWORD) then
          case t.Info.KeyWord of
            KEY_CLASS: ClassKeyWordString := t.Data;
            KEY_CONSTRUCTOR,
            KEY_DESTRUCTOR,
            KEY_FUNCTION,
            KEY_PROCEDURE: 
              begin
                d := GetLastComment(True);
                if not ParseCDFP(M, ClassKeyWordString, 
                  t.Data, t.Info.KeyWord, d, True) then
                begin
                  i.Free;
                  FreeAndNil(t);
                  Exit;
                end;
                ClassKeyWordString := '';
                M.Visibility := Visibility;
                if Visibility in ShowVisibilities then begin
                  i.Methods.Add(M);
                end
                else
                begin
                  M.Free;
                end;
              end;
            KEY_END: Finished := True;
            KEY_PROPERTY: begin
                if (not ParseProperty(p)) then begin
                  FreeAndNil(t);
                  i.Free;
                  Exit;
                end;
                p.Visibility := Visibility;
                if Visibility in ShowVisibilities then begin
                  i.Properties.Add(p);
                end
                else
                begin
                  FreeAndNil(p);
                end;
              end;
            KEY_CASE: begin
              try
                if not ParseRecordCase(i, false) then begin
                  FreeAndNil(t);
                  i.Free;
                  Exit;
                end;
                except
                  FreeAndNil(t);
                  i.Free;
                  raise;
                end;
              end;
          else begin
              i.Free;
              try
                DoError('%s: Error, unexpected reserved keyword "%s".',
                  [Scanner.GetStreamInfo, KeyWordArray[t.Info.KeyWord]]);
              finally
                FreeAndNil(t);
              end;
            end;
          end
        else
          if (t.MyType = TOK_IDENTIFIER) then
          begin
            case t.Info.StandardDirective of
              SD_DEFAULT: begin
                  if not SkipDeclaration(nil) then begin
                    DoError('%s: Could not skip declaration after default property.', [Scanner.GetStreamInfo]);
                  end;
                  DoMessage(5, mtInformation, 'Skipped default property keyword.', []);
                end;
              SD_PUBLIC:    Visibility := viPublic;
              SD_PUBLISHED: Visibility := viPublished;
              SD_PRIVATE:   Visibility := viPrivate;
              SD_PROTECTED: Visibility := viProtected;
              SD_AUTOMATED: Visibility := viAutomated;
              else
                if not ParseFields(t, i, Visibility in ShowVisibilities, Visibility) then
                  Exit;
            end;
          end;
      FreeAndNil(t);
    until Finished;
    
    ParseHintDirectives(i);
    
    t := GetNextToken;
    try
      if not t.IsSymbol(SYM_SEMICOLON) then
      begin
        if IsInRecordCase then
        begin
          if t.IsSymbol(SYM_RIGHT_PARENTHESIS) then 
            Scanner.UnGetToken(t) else 
          begin
            i.Free;
            DoError('%s: unexpected symbol at end of sub-record.', 
              [Scanner.GetStreamInfo]);
          end;
        end else 
        begin
          i.Free;
          DoError('%s: Semicolon at the end of Class / Object / Interface' +
            ' / Record expected.', [Scanner.GetStreamInfo]);
        end;
      end;
    finally
      FreeAndNil(t);
    end;

    if Assigned(U) then U.AddCIO(i) else i.Free;
  except
    t.Free;
    raise;
  end;
  Result := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseConstant(const U: TPasUnit; 
  const ConstantName: string): Boolean;
var
  i: TPasConstant;
begin
  Result := False;
  i := TPasConstant.Create;
  i.Name := ConstantName;
  DoMessage(5, mtInformation, 'Parsing constant %s.', [i.Name]);
  i.RawDescription := GetLastComment(True);
  i.FullDeclaration := ConstantName;
  if SkipDeclaration(i) then
  begin
    U.AddConstant(i);
    Result := True;
  end
  else
    DoError('Could not skip declaration of constant "%s".', [i.Name]);
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseEnum(out p: TPasEnum;
  const Name, RawDescription: string): boolean;
var
  t: TToken;
  item: TPasItem;
begin
  t := nil;
  p := TPasEnum.Create;
  p.Name := Name;
  p.RawDescription := RawDescription;
  p.FullDeclaration := Name + ' = (...);'; 

  t := GetNextToken;
  while not t.IsSymbol(SYM_RIGHT_PARENTHESIS) do begin
    if t.MyType = TOK_IDENTIFIER then begin
      item := TPasItem.Create;
      item.Name := t.Data;
      item.RawDescription := GetLastComment(True);
      p.Members.Add(item);
    end;
    if t.IsSymbol(SYM_EQUAL) then begin
      FreeAndNil(t);
      t := GetNextToken;
    end;
    FreeAndNil(t);
    t := GetNextToken;
  end;
  FreeAndNil(t);
  t := GetNextToken;
  { TODO: check here that t is ; }
  FreeAndNil(t);
  Result := true;
end;

function TParser.ParseInterfaceSection(const U: TPasUnit): Boolean;
const
  MODE_UNDEFINED = 0;
  MODE_CONST = 1;
  MODE_TYPE = 2;
  MODE_VAR = 3;
var
  d: string;
  Finished: Boolean;
  Mode: Integer;
  M: TPasMethod;
  t: TToken;
begin
  DoMessage(4, mtInformation, 'Entering interface section of unit %s',[U.Name]);
  Result := False;
  Finished := False;
  Mode := MODE_UNDEFINED;

  repeat
    t := GetNextToken;

    try
      case t.MyType of
        TOK_IDENTIFIER: begin
            // s := t.Data;
            case Mode of
              MODE_CONST:
                if (not ParseConstant(U, t.Data)) then Exit;
              MODE_TYPE:
                if (not ParseType(U, t)) then Exit;
              MODE_VAR:
                if (not ParseVariables(U, t)) then Exit;
            else
              DoError('%s: Error, unexpected identifier "%s".',
                [Scanner.GetStreamInfo, t.Data]);
            end;
          end;
        TOK_KEYWORD: begin
            case t.Info.KeyWord of
              KEY_RESOURCESTRING,
                KEY_CONST:
                Mode := MODE_CONST;
              KEY_OPERATOR: begin
                  d := GetLastComment(True);
                  if (not ParseCDFP(M, '', t.Data, t.Info.KeyWord, d, True))
                  then begin
                    Exit;
                  end;
                  u.FuncsProcs.Add(M);
                  Mode := MODE_UNDEFINED;
                end;
              KEY_FUNCTION,
                KEY_PROCEDURE: begin
                  d := GetLastComment(True);
                  if (not ParseCDFP(M, '', t.Data, t.Info.KeyWord, d, True))
                    then begin
                    Exit;
                  end;
                  u.FuncsProcs.Add(M);
                  Mode := MODE_UNDEFINED;
                end;
              KEY_IMPLEMENTATION:
                Finished := True;
              KEY_TYPE:
                Mode := MODE_TYPE;
              KEY_USES:
                if not ParseUses(U) then Exit;
              KEY_THREADVAR,
                KEY_VAR:
                Mode := MODE_VAR;
            else
              DoError('%s: Unexpected keyword %s.', [Scanner.GetStreamInfo,
                t.Data]);
            end;
          end;
      end;
    finally
      FreeAndNil(t);
    end;
  until Finished;
  Result := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseProperty(out p: TPasProperty): Boolean;
var
  Finished: Boolean;
  t: TToken;
begin
  t := nil;
  ParseProperty := False;
  
  t := GetNextToken;
  if (t.MyType <> TOK_IDENTIFIER) then begin
    FreeAndNil(t);
    DoError('%s: expected identifier as property name.',
      [Scanner.GetStreamInfo]);
  end;
  p := TPasProperty.Create;
  p.Name := t.Data;
  FreeAndNil(t);
  DoMessage(5, mtInformation, 'Parsing property %s', [p.Name]);
  p.IndexDecl := '';
  p.Proptype := '';
  p.FullDeclaration := 'property ' + p.Name;
  p.RawDescription := GetLastComment(True);
  
  { Is this only a redeclaration of property from ancestor
    (to e.g. change it's visibility) }
  t := GetNextToken(P);
  if t.IsSymbol(SYM_SEMICOLON) then
  begin
    p.FullDeclaration := p.FullDeclaration + ';';
    FreeAndNil(t);
    ParseProperty := True;
    Exit;
  end;

  { get index }
  if t.IsSymbol(SYM_LEFT_BRACKET) then
  begin
    FreeAndNil(t);
    p.IndexDecl := '[';
    p.FullDeclaration := p.FullDeclaration + '[';
    repeat
      t := Scanner.GetToken;

      if not (t.MyType in TokenCommentTypes + [TOK_DIRECTIVE]) then
      begin
        p.IndexDecl := p.IndexDecl + t.Data;
        p.FullDeclaration := p.FullDeclaration + t.Data;
      end;
      Finished := t.IsSymbol(SYM_RIGHT_BRACKET);
      FreeAndNil(t);
    until Finished;

    t := GetNextToken;
  end;

  { now if there is a colon, it is followed by the type }
  if t.IsSymbol(SYM_COLON) then 
  begin
    FreeAndNil(t);
    
    { get property type }
    t := GetNextToken;
    if (t.MyType <> TOK_IDENTIFIER) and (t.MyType <> TOK_KEYWORD) then
      DoError('Identifier expected, found %s in file %s',
        [TOKEN_TYPE_NAMES[t.MyType], Scanner.GetStreamInfo]);

    p.Proptype := t.Data;
    FreeAndNil(t);
    p.FullDeclaration := p.FullDeclaration + ': ' + p.Proptype;
  end else
  begin
    p.FullDeclaration := p.FullDeclaration + t.Data;
    FreeAndNil(t);
  end;
  
  { read the rest of declaration }
  if not SkipDeclaration(P) then
    DoError('Could not skip rest of declaration in file %s', 
      [Scanner.GetStreamInfo]);

  Result := True;
end;

{ ---------------------------------------------------------------------------- }

{
  TYPENAME =
    class of ... ;               => "normal" type
    class ( ANCESTOR<S> )        => class
          ANYTHING               => class
    object ( ) end ;                 => object
          ANYTHING
    interface end ;              => interface
}

function TParser.ParseRecordCase(const R: TPasCio;
  const SubCase: boolean): boolean;
var
  t1, t2: TToken;
  P: TPasItem;
  LLastWasComma: boolean;
  s: string;
  LNeedId: boolean;
  ParenCount: integer;
begin
  Result := True;
  ParenCount := 0;
  t2 := nil;
  t1 := GetNextToken;
  if t1.MyType <> TOK_IDENTIFIER then begin
    Result := False;
    FreeAndNil(t1);
  end else begin
    t2 := GetNextToken;
    if (t2.MyType = TOK_SYMBOL) and (t2.Info.SymbolType = SYM_COLON) then begin
      // case x:Type of
      FreeAndNil(t2); // colon
      t2 := GetNextToken;
      P := TPasItem.Create;
      p.Name := t1.Data;
      p.RawDescription := GetLastComment(True);
      p.FullDeclaration := p.Name + ': ' + t2.Data;
      R.Fields.Add(p);
    end else begin
      // case Type of
      Scanner.UnGetToken(t2);
    end;
    FreeAndNil(t2);
    FreeAndNil(t1);
    t1 := GetNextToken;
    if (t1.MyType <> TOK_KEYWORD) or (t1.Info.KeyWord <> KEY_OF) then begin
      FreeAndNil(t1);
      DoError('OF expected', []);
    end;
    FreeAndNil(t1);
    t1 := GetNextToken;
    LNeedId := True;
    repeat
      while true do begin
        case t1.MyType of
          TOK_SYMBOL: begin
              case t1.Info.SymbolType of
                SYM_COLON: break;
                SYM_COMMA: LNeedId := True;
              end;
            end;
          TOK_IDENTIFIER,
          TOK_NUMBER: if not LNeedId then begin
                        s := t1.Data;
                        FreeAndNil(t1);
                        DoError('did not expect identifier %s here!', [s]);
                      end;
          else begin
            s := t1.Data;
            FreeAndNil(t1);
            DoError('unexpected token: %s', [s]);
          end;
        end;
        FreeAndNil(t1);
        t1 := GetNextToken;
      end;
      // read all identifiers before colon

      FreeAndNil(t1);
      t1 := GetNextToken;
      if (t1.MyType <> TOK_SYMBOL) or (t1.Info.SymbolType <> SYM_LEFT_PARENTHESIS) then begin
        FreeAndNil(t1);
        DoError('( expected', []);
      end;
      FreeAndNil(t1);
      t1 := GetNextToken;
      while (t1.MyType <> TOK_SYMbol) or (T1.Info.SymbolType <> SYM_RIGHT_PARENTHESIS) do begin
        if (t1.MyType = TOK_IDENTIFIER) or (ParenCount > 0) then begin
          P := TPasItem.Create;
          p.RawDescription := GetLastComment(True);
          P.Name := t1.Data;
          P.FullDeclaration := P.Name; { TODO -- better FullDeclaration }
          R.Fields.Add(p);
          if (ParenCount = 0) then
          begin
            FreeAndNil(t1);
            t1 := GetNextToken;
          end;
          LLastWasComma := false;
          while (t1.MyType <> TOK_SYMBOL)
            OR ((t1.Info.SymbolType <> SYM_SEMICOLON)
            and (t1.Info.SymbolType <> SYM_RIGHT_PARENTHESIS))
            or ((t1.Info.SymbolType = SYM_RIGHT_PARENTHESIS)
            and (ParenCount > 0)) do begin
            if (t1.MyType = TOK_IDENTIFIER) then begin
              if LLastWasComma then begin
                p := TPasItem.Create;
                p.RawDescription := GetLastComment(True);
                p.Name := t1.data;
                P.FullDeclaration := P.Name; { TODO -- better FullDeclaration }
                R.Fields.Add(p);
              end;
            end;
            if t1.MyType = TOK_KEYWORD then begin
              if (t1.Info.KeyWord = KEY_RECORD) then begin
                ParseCIO(nil, '', CIO_RECORD, '', True);
              end;
              if (t1.Info.KeyWord = KEY_PACKED) then begin
                FreeAndNil(t1);
                t1 := GetNextToken;
                if (t1.MyType = TOK_KEYWORD) and (t1.Info.KeyWord = KEY_RECORD) then begin
                  ParseCIO(nil, '', CIO_PACKEDRECORD, '', True);
                end;
              end;
            end;
            LLastWasComma := false;
            if (t1.MyType = TOK_SYMBOL) and (t1.Info.SymbolType = SYM_COMMA) then begin
              LLastWasComma := True;
            end;
            if (not (t1.Info.SymbolType in [SYM_RIGHT_PARENTHESIS, SYM_COLON]))
              or ((t1.Info.SymbolType = SYM_RIGHT_PARENTHESIS) and
              (ParenCount > 0)) then begin

              if t1.Info.SymbolType = SYM_LEFT_PARENTHESIS then
              begin
                Inc(ParenCount)
              end
              else if t1.Info.SymbolType = SYM_RIGHT_PARENTHESIS then
              begin
                Dec(ParenCount)
              end;
            end;
            FreeAndNil(t1);
            t1 := GetNextToken;
          end;
          if (t1.Info.SymbolType = SYM_RIGHT_PARENTHESIS)
            and (ParenCount = 0) then
          begin
            Scanner.UnGetToken(t1);
          end;
        end else begin
          if (t1.MyType = TOK_KEYWORD) and (t1.Info.KeyWord = KEY_CASE) then begin
            ParseRecordCase(R, true);
          end else begin
            FreeAndNil(t1);
            DoError('Invalid keyword found', []);
          end;
        end;
        FreeAndNil(t1); // free token
        t1 := GetNextToken;
      end;
      FreeAndNil(t1); // free ')' token
      t1 := GetNextToken; // next
      if (t1.MyType = TOK_SYMBOL) and (t1.Info.SymbolType = SYM_SEMICOLON) then begin
        FreeAndNil(t1);
        t1 := GetNextToken;
      end;
      if (t1.MyType = TOK_KEYWORD) and (t1.Info.KeyWord = KEY_END) then break;
      if subcase and (t1.MyType = TOK_SYMBOL) and (t1.Info.SymbolType = SYM_RIGHT_PARENTHESIS) then break;
    until false;
    Scanner.UnGetToken(t1);
  end;
end;

function TParser.ParseType(const U: TPasUnit; var t: TToken): Boolean;
var
  d: string;
  NormalType: TPasType;
  TypeName: string;
  LCollected, LTemp: string;
  MethodType: TPasMethod;
  EnumType: TPasEnum;
begin
  Result := False;
  TypeName := t.Data;
  DoMessage(5, mtInformation, 'Parsing type "%s"', [TypeName]);
  FreeAndNil(t);
  d := GetLastComment(True);
  t := GetNextToken(LCollected);

  if (not t.IsSymbol(SYM_EQUAL)) then begin
    if (t.IsSymbol(SYM_SEMICOLON)) then begin
      FreeAndNil(t);
      t := nil;
      Result := True;
      Exit;
    end;
    FreeAndNil(t);
    DoError('"=" expected in file %s', [Scanner.GetStreamInfo]);
  end;
  LCollected := TypeName + LCollected + t.Data;
  FreeAndNil(t);

  t := GetNextToken(LTemp);
  LCollected := LCollected + LTemp + t.Data;

  if (t.MyType = TOK_KEYWORD) then
    case t.Info.KeyWord of
      KEY_CLASS: begin
          FreeAndNil(t);
          t := GetNextToken(LTemp);
          LCollected := LCollected + LTemp + t.Data;
          if (t.MyType = TOK_KEYWORD) and (t.Info.KeyWord = KEY_OF) then begin
            { include "identifier = class of something;" as standard type }
          end else begin
            Scanner.UnGetToken(t);
            t := nil;
            if not ParseCIO(U, TypeName, CIO_CLASS, d, False) then Exit;
            Result := True;
            Exit;
          end;
        end;
      KEY_DISPINTERFACE: begin
          FreeAndNil(t);
          if not ParseCIO(U, TypeName, CIO_SPINTERFACE, d, False) then Exit;
          Result := True;
          Exit;
        end;
      KEY_INTERFACE: begin
          FreeAndNil(t);
          if not ParseCIO(U, TypeName, CIO_INTERFACE, d, False) then Exit;
          Result := True;
          Exit;
        end;
      KEY_OBJECT: begin
          FreeAndNil(t);
          if not ParseCIO(U, TypeName, CIO_OBJECT, d, False) then Exit;
          Result := True;
          Exit;
        end;
      KEY_RECORD: begin
          FreeAndNil(t);
          if not ParseCIO(U, TypeName, CIO_RECORD, d, False) then Exit;
          Result := True;
          Exit;
        end;
      KEY_PACKED: begin
          FreeAndNil(t);
          t := GetNextToken(LTemp);
          LCollected := LCollected + LTemp + t.Data;
          if (t.MyType = TOK_KEYWORD) AND (t.Info.KeyWord = KEY_RECORD) then begin
            FreeAndNil(t);
            if not ParseCIO(U, TypeName, CIO_PACKEDRECORD, d, False) then exit;
            Result := True;
            exit;
          end;
        end;
    end;
  if Assigned(t) then begin
    if (t.MyType = TOK_KEYWORD) then begin
      if t.Info.KeyWord in [KEY_FUNCTION, KEY_PROCEDURE] then begin
        if ParseCDFP(MethodType, '', t.Data, t.Info.KeyWord, d, False) then begin
          MethodType.Name := TypeName;
          MethodType.FullDeclaration := 
            TypeName + ' = ' + MethodType.FullDeclaration;
          U.AddType(MethodType);
          Result := True;
          exit;
        end else begin
          DoError('Very strange condition - found function but could not parse', []);
        end;
      end;
    end;
    if t.IsSymbol(SYM_LEFT_PARENTHESIS) then begin
      if ParseEnum(EnumType, TypeName, d) then 
      begin
        U.AddType(EnumType);
        Result := True;
        exit;
      end;
    end;
    SetLength(LCollected, Length(LCollected)-Length(t.Data));
    Scanner.UnGetToken(t);
  end;

  NormalType := TPasType.Create;
  NormalType.FullDeclaration := LCollected;
  if not SkipDeclaration(NormalType) then begin
    NormalType.Free;
  end else begin
    NormalType.Name := TypeName;
    NormalType.RawDescription := d;
    U.AddType(NormalType);
    Result := True;
  end;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.ParseUnit(var U: TPasUnit);
var
  t: TToken;
begin
  { get 'unit' keyword }
  t := GetNextToken;
  if (t.MyType <> TOK_KEYWORD) or (t.Info.KeyWord <> KEY_UNIT) then
    DoError(Scanner.GetStreamInfo + ': keyword "unit" expected.', []);
  FreeAndNil(t);

  U := TPasUnit.Create;
  try
    U.RawDescription := GetLastComment(True);

    { get unit name identifier }
    t := GetNextToken;
    if t.MyType <> TOK_IDENTIFIER then
      DoError(Scanner.GetStreamInfo + ': identifier (unit name) expected.', []);
    U.Name := t.Data;
    FreeAndNil(t);
    
    ParseHintDirectives(U);
    
    { skip semicolon }
    t := GetNextToken;
    if not t.IsSymbol(SYM_SEMICOLON) then
      DoError(Scanner.GetStreamInfo + ': semicolon expected.', []);
    FreeAndNil(t);
    
    { get 'interface' keyword }
    t := GetNextToken;
    if (t.MyType <> TOK_KEYWORD) or (t.Info.KeyWord <> KEY_INTERFACE) then
      DoError(Scanner.GetStreamInfo + ': keyword "INTERFACE" expected.', []);
      
    { now parse the interface section of that unit }
    if not ParseInterfaceSection(U) then
      DoError('Parsing interface failed', []);
  except
    FreeAndNil(U);
    FreeAndNil(t);
    raise;
  end;
  FreeAndNil(t);
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseUses(const U: TPasUnit): Boolean;
var
  Finished: Boolean;
  t: TToken;
begin
  t := nil;
  Result := False;

  repeat
    t := GetNextToken;
    if t.MyType <> TOK_IDENTIFIER then
      DoError('%s: Error, unit name expected (found %s "%s")',
        [Scanner.GetStreamInfo, t.GetTypeName, t.Data]);
    U.UsesUnits.Add(t.Data);
    FreeAndNil(t);
    
    t := GetNextToken;
    if (t.MyType <> TOK_SYMBOL) and
      (t.Info.SymbolType <> SYM_COMMA) and
      (t.Info.SymbolType <> SYM_SEMICOLON) then
      DoError('%s: Error, comma or semicolon expected.',
        [Scanner.GetStreamInfo]);
    Finished := t.Info.SymbolType = SYM_SEMICOLON;
    FreeAndNil(t);
  until Finished;

  Result := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.ParseVariables(const U: TPasUnit; var t: TToken): Boolean;
begin
  Result := ParseFieldsVariables(U.Variables, t, false, viPublished);
end;

function TParser.ParseFieldsVariables(Items: TPasItems; var t: TToken;
  OfObject: boolean; Visibility: TVisibility): Boolean;
var
  Finished: Boolean;
  FirstLoop: Boolean;
  NewItem: TPasFieldVariable;
  ItemCollector: TPasFieldVariable;
  m: TPasMethod;
  ItemsParsed: TPasItems;
  WhitespaceCollector: string;
  ttemp: TToken;
  FirstCheck: boolean;
begin
  Result := false;
  
  ItemCollector := TPasFieldVariable.Create;
  try
    ItemsParsed := TPasItems.Create(false);
    try
      FirstLoop := True;
      repeat
        NewItem := TPasFieldVariable.Create;
        if FirstLoop then 
        begin
          NewItem.Name := t.Data;
          FirstLoop := False;
        end else 
        begin
          t := GetNextToken(ItemCollector);
          if (t.MyType <> TOK_IDENTIFIER) then
            DoError('%s: Identifier expected.', [Scanner.GetStreamInfo]);
          NewItem.Name := t.Data;
        end;       

        if Items <> nil then
        begin
          NewItem.Visibility := Visibility;
          NewItem.RawDescription := GetLastComment(false);
          Items.Add(NewItem);
          ItemsParsed.Add(NewItem);
        end else
        begin
          FreeAndNil(NewItem);
        end;

        FreeAndNil(t);
        
        t := GetNextToken(ItemCollector);
        
        if (t.MyType <> TOK_SYMBOL) or
          ((t.Info.SymbolType <> SYM_COMMA) and
          (t.Info.SymbolType <> SYM_COLON)) then
          DoError('%s: Expected comma or colon in variable or field declaration.',
            [Scanner.GetStreamInfo]);

        Finished := (t.Info.SymbolType = SYM_COLON);
        if (t.MyType <> TOK_SYMBOL) or (t.Info.SymbolType <> SYM_COMMA) then 
          ItemCollector.FullDeclaration := 
            ItemCollector.FullDeclaration + t.Data;
        FreeAndNil(t);
      until Finished;
      
      ClearLastComment;
      t := GetNextToken(ItemCollector);
      ItemCollector.FullDeclaration := 
        ItemCollector.FullDeclaration + t.Data;
      if (t.MyType = TOK_KEYWORD) and 
         (t.Info.KeyWord in [KEY_FUNCTION, KEY_PROCEDURE]) then 
      begin
        { KeyWordString for ParseCDFP below is '', because we already included
          t.Data inside ItemCollector.FullDeclaration. 
          If KeyWordString would be t.Data, then we would incorrectly
          append t.Data twice to ItemCollector.FullDeclaration
          when appending m.FullDeclaration to ItemCollector.FullDeclaration. }
        ParseCDFP(M, '', '', t.Info.KeyWord, '', false);
        ItemCollector.FullDeclaration := 
          ItemCollector.FullDeclaration + M.FullDeclaration;
        M.Free;
        FreeAndNil(t);
        t := GetNextToken(ItemCollector);

        if (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType = SYM_EQUAL) then
        begin
          ItemCollector.FullDeclaration := 
            ItemCollector.FullDeclaration + t.Data;
          SkipDeclaration(ItemCollector);
        end else 
        begin
          Scanner.UnGetToken(t);
        end;
      end else
      if (t.MyType = TOK_KEYWORD) and (t.Info.KeyWord = KEY_RECORD) then
      begin
        ParseCIO(nil, '', CIO_RECORD, '', false);
      end else
      if (t.MyType = TOK_KEYWORD) and (t.Info.KeyWord = KEY_RECORD) then
      begin 
        FreeAndNil(t);
        t := GetNextToken;
        if (t.MyType = TOK_KEYWORD) and (t.Info.KeyWord = KEY_RECORD) then begin
          ParseCIO(nil, '', CIO_PACKEDRECORD, '', False);
        end else begin
          SkipDeclaration(ItemCollector);
        end;      
      end else
      begin
        if not SkipDeclaration(ItemCollector) then Exit;
      end;

      if not OfObject then
      begin
        // The following section allows PasDoc to parse variable modifiers in FPC.
        // See: http://www.freepascal.org/docs-html/ref/refse19.html
        ClearLastComment;
        Finished := False;
        FirstCheck := True;
        repeat
          ttemp := GetNextToken(WhitespaceCollector);

          if FirstCheck then
          begin
            // If the first non-white character token after the semicolon
            // is "cvar", "export', "external", or "public", there is
            // a variable modifier present.

            // This does not take into account the "absolute" modifier
            // (which is not preceeded by a semicolon).
            FirstCheck := False;
            if (ttemp.MyType = TOK_IDENTIFIER) and 
               (ttemp.Info.StandardDirective in 
                 [SD_CVAR, SD_EXPORT, SD_EXTERNAL, SD_PUBLIC]) then 
            begin
              ItemCollector.FullDeclaration := ItemCollector.FullDeclaration +  ' ' + ttemp.Data;
              FreeAndNil(ttemp)
            end
            else
            begin
              Finished := True;
              Scanner.UnGetToken(ttemp);
            end;
            while not Finished do
            begin
              ttemp := GetNextToken(WhitespaceCollector);
              if ttemp = nil then Exit;
              if (ttemp.MyType = TOK_SYMBOL) and (ttemp.Info.SymbolType = SYM_SEMICOLON) then
              begin
                Finished := True;
                FirstCheck := False;
                ItemCollector.FullDeclaration := ItemCollector.FullDeclaration +  ttemp.Data;
              end
              else
              begin
                ItemCollector.FullDeclaration := ItemCollector.FullDeclaration +  ' ' + ttemp.Data;
              end;
              FreeAndNil(ttemp)
            end;
          end;
        until Finished and not FirstCheck;
      end;

      Result := True;
      ItemsParsed.SetFullDeclaration(true, ItemCollector.FullDeclaration);
      ItemsParsed.SetIsDeprecated(ItemCollector.IsDeprecated);
      ItemsParsed.SetIsPlatformSpecific(ItemCollector.IsPlatformSpecific);
      ItemsParsed.SetIsLibrarySpecific(ItemCollector.IsLibrarySpecific);
    finally ItemsParsed.Free end; 
  finally ItemCollector.Free end;
end;

{ ---------------------------------------------------------------------------- }

procedure TParser.SetCommentMarkers(const Value: TStringList);
begin
  FCommentMarkers.Assign(Value);
end;

function TParser.SkipDeclaration(const Item: TPasItem): Boolean;
var
  EndLevel: Integer;
  IsSemicolon: Boolean;
  PLevel: Integer;
  t: TToken;
  WhitespaceCollector: string;
begin
  Result := False;
  EndLevel := 0;
  PLevel := 0;
  repeat
    t := GetNextToken(WhitespaceCollector);
    if t = nil then Exit;
    if Assigned(Item) then begin
      Item.FullDeclaration := Item.FullDeclaration + WhitespaceCollector;
    end;
    case t.MyType of
      TOK_SYMBOL:
        case t.Info.SymbolType of
          SYM_LEFT_PARENTHESIS: Inc(PLevel);
          SYM_RIGHT_PARENTHESIS: Dec(PLevel);
        end;
      TOK_KEYWORD:
        case t.Info.KeyWord of
          KEY_END: Dec(EndLevel);
          KEY_RECORD: Inc(EndLevel);
          KEY_LIBRARY: 
            if Assigned(Item) then Item.IsLibrarySpecific := true;
        end;
      TOK_IDENTIFIER:
        case t.Info.StandardDirective of
          SD_PLATFORM: 
            if Assigned(Item) then Item.IsPlatformSpecific := true;
          SD_DEPRECATED: 
            if Assigned(Item) then Item.IsDeprecated := true;
        end;
    end;
    IsSemicolon := (t.MyType = TOK_SYMBOL) and (t.Info.SymbolType =
      SYM_SEMICOLON);
    if Assigned(Item) then Item.FullDeclaration := Item.FullDeclaration + t.Data;
    if EndLevel<0 then begin
      // within records et al. the last declaration need not be terminated by ;
      Scanner.UnGetToken(t);
      Result := True;
      exit;
    end;
    FreeAndNil(t);
  until IsSemicolon and (EndLevel = 0) and (PLevel = 0);
  Result := True;
end;

{ ---------------------------------------------------------------------------- }

function TParser.PeekNextToken(out WhitespaceCollector: string): TToken;
var
  t: TToken;
begin
  Result := nil;
  t := nil;
  WhitespaceCollector := '';
  repeat
    t := Scanner.PeekToken;
    if t.MyType in TokenCommentTypes then
    begin
      Scanner.ConsumeToken;
      // If there are several comments in a row, combine them.
      if Assigned(LastCommentToken) and
         (t.MyType = TOK_COMMENT_CSTYLE) and 
         (t.MyType = LastCommentToken.MyType) then 
      begin
        t.CommentContent := GetLastComment(True) + LineEnding + 
          ExtractDocComment(False, t);

        (* Remember that t.Data and t.CommentContent 
           must be in the form acceptable by ExtractDocComment again.
           And the code above surely removed comment
           markers from the t.CommentContent,
           moreover we should recreate t.Data from t.CommentContent
           (to be sure that T is in sensible state).
           
           This means that we must do something ugly now:
           1. add again marker to t.CommentContent, 
              if it's not optional (otherwise comments could be
              errorneously rejected because they no longer have required
              marker)
           2. apply again comment braces for t.Data
        *)
        if (not MarkersOptional) and (CommentMarkers.Count > 0) then
          t.CommentContent := CommentMarkers[0] + t.CommentContent;
        t.Data := '{' + t.CommentContent + '}';
      end;
      if Assigned(LastCommentToken) then
      begin
        LastCommentToken.Free;
      end;
      LastCommentToken := t;
      t := nil;
    end else
    begin
      case t.MyType of
        TOK_WHITESPACE: 
          begin
            Scanner.ConsumeToken;
            WhitespaceCollector := WhitespaceCollector + t.Data;
            FreeAndNil(t);
          end;
        else 
          begin
            Result := t;
            break;
          end;
      end;
    end;
  until False;
end;

function TParser.PeekNextToken: TToken; 
var 
  Dummy: string;
begin
  Result := PeekNextToken(Dummy);
end;

{ ------------------------------------------------------------ }

procedure TParser.ParseHintDirectives(Item: TPasItem);
var
  t: TToken;
begin
  repeat
    t := PeekNextToken;
    
    if (t.MyType = TOK_IDENTIFIER) and 
       (t.Info.StandardDirective = SD_PLATFORM) then
    begin
      Scanner.ConsumeToken;
      Item.IsPlatformSpecific := true;
      FreeAndNil(t);
    end else
    if (t.MyType = TOK_IDENTIFIER) and 
       (t.Info.StandardDirective = SD_DEPRECATED) then
    begin
      Scanner.ConsumeToken;
      Item.IsDeprecated := true;
      FreeAndNil(t);
    end else
    if (t.MyType = TOK_KEYWORD) and 
       (t.Info.KeyWord = KEY_LIBRARY) then
    begin
      Scanner.ConsumeToken;
      Item.IsLibrarySpecific := true;
      FreeAndNil(t);
    end else
      break;
  until false;
end;

end.
