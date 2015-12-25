unit BitVector;

interface

uses
  Classes, AuxTypes;

type
  TBitVector = class(TObject)
  private
    fOwnsMemory:  Boolean;
    fMemSize:     TMemSize;
    fMemory:      Pointer;
    fCount:       Integer;
    fSetCount:    Integer;
    fChanging:    Boolean;
    fChanged:     Boolean;
    fOnChange:    TNotifyEvent;
    Function GetBit_LL(Index: Integer): Boolean;
    Function SetBit_LL(Index: Integer; Value: Boolean): Boolean;
    Function GetBit(Index: Integer): Boolean;
    procedure SetBit(Index: Integer; Value: Boolean);
    Function GetCapacity: Integer;
    procedure SetCapacity(Value: Integer);
  protected
    Function CheckIndex(Index: Integer): Boolean; virtual;
    procedure CommonInit; virtual;
    procedure ScanForSetCount; virtual;
    procedure DoOnChange; virtual;
  public
    constructor Create(Memory: Pointer; Count: Integer); overload;
    constructor Create(InitialCapacity: Integer = 0); overload;
    destructor Destroy; override;

    procedure BeginChanging;
    Function EndChanging: Boolean;

    Function LowIndex: Integer; virtual;
    Function HighIndex: Integer; virtual;    
    Function Firts: Boolean; virtual;
    Function Last: Boolean; virtual;

    Function Grow(Force: Boolean = False): Integer; virtual;
    Function Shrink: Integer; virtual;

    Function Add(Value: Boolean): Integer; virtual;
    procedure Insert(Index: Integer; Value: Boolean); virtual;
    procedure Delete(Index: Integer); virtual;
    procedure Exchange(Index1, Index2: Integer); virtual;
    procedure Move(SrcIdx, DstIdx: Integer); virtual;

    procedure FillTo(Value: Boolean); virtual;
    procedure Clear; virtual;

    Function IsEmpty: Boolean; virtual;
    Function IsFull: Boolean; virtual;
(*
    Function FirstSet: Integer; virtual;
    Function FirstClean: Integer; virtual;
    Function LastSet: Integer; virtual;
    Function LastClean: Integer; virtual;

    procedure Append(Memory: Pointer; Count: Integer); overload; virtual;
    procedure Append(Vector: TBitVector); overload; virtual;

    procedure Assign(Memory: Pointer; Count: Integer); virtual; overload;
    procedure Assign(Vector: TBitVector); virtual; overload;
    procedure AssignOR(Vector: TBitVector); virtual;
    procedure AssignAND(Vector: TBitVector); virtual;
    procedure AssignXOR(Vector: TBitVector); virtual;

    procedure Complement; virtual;

    procedure SaveToStream(Stream: TStream); virtual;
    procedure LoadFromStream(Stream: TStream); virtual;
    procedure SaveToFile(const FileName: String); virtual;
    procedure LoadFromFile(const FileName: String); virtual;

*)
    property Bits[Index: Integer]: Boolean read GetBit write SetBit; default;
    property Memory: Pointer read fMemory;
  published
    property OwnsMemory: Boolean read fOwnsMemory;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read fCount;
    property SetCount: Integer read fSetCount;
    property OnChange: TNotifyEvent read fOnChange write fOnChange;
  end;

implementation

uses
  SysUtils, Math;

const
  AllocDeltaBits  = 32;
  AllocDeltaBytes = AllocDeltaBits div 8;


//==============================================================================

Function TBitVector.GetBit_LL(Index: Integer): Boolean;
begin
Result := (PByte(PtrUInt(fMemory) + PtrUInt(Index shr 3))^ shr (Index and 7)) and 1 <> 0;
end;

//------------------------------------------------------------------------------

Function TBitVector.SetBit_LL(Index: Integer; Value: Boolean): Boolean;
var
  OldByte:  Byte;
begin
OldByte := PByte(PtrUInt(fMemory) + PtrUInt(Index shr 3))^;
Result := (OldByte shr (Index and 7)) and 1 <> 0;
If Value then
  PByte(PtrUInt(fMemory) + PtrUInt(Index shr 3))^ := OldByte or (1 shl (Index and 7))
else
  PByte(PtrUInt(fMemory) + PtrUInt(Index shr 3))^ := OldByte and not (1 shl (Index and 7));
end;

//------------------------------------------------------------------------------

Function TBitVector.GetBit(Index: Integer): Boolean;
begin
If CheckIndex(Index) then
  Result := GetBit_LL(Index)
else
  raise Exception.CreateFmt('TBitVector.GetBit: Index (%d) out of bounds.',[Index]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.SetBit(Index: Integer; Value: Boolean);
var
  OldValue: Boolean;
begin
If CheckIndex(Index) then
  begin
    OldValue := SetBit_LL(Index,Value);
    If Value <> OldValue then
      begin
        If OldValue then Dec(fSetCount)
          else Inc(fSetCount);
        DoOnChange;
      end;
  end
else raise Exception.CreateFmt('TBitVector.SetBit: Index (%d) out of bounds.',[Index]);
end;

//------------------------------------------------------------------------------

Function TBitVector.GetCapacity: Integer;
begin
Result := fMemSize shl 3;
end;

//------------------------------------------------------------------------------

procedure TBitVector.SetCapacity(Value: Integer);
var
  NewMemSize: PtrUInt;
begin
If OwnsMemory then
  begin
    NewMemSize := Ceil(Value / AllocDeltaBits) * AllocDeltaBytes;
    If fMemSize <> NewMemSize then
      begin
        fMemSize := NewMemsize;
        ReallocMem(fMemory,fMemSize);
        If Capacity < fCount then
          begin
            fCount := Capacity;
            ScanForSetCount;
            DoOnChange;
          end;
      end;
  end
else raise Exception.Create('TBitVector.SetCapacity: Capacity cannot be changed if object does not own the memory.');
end;

//==============================================================================

Function TBitVector.CheckIndex(Index: Integer): Boolean;
begin
Result := (Index >= 0) and (Index < fCount);
end;

//------------------------------------------------------------------------------

procedure TBitVector.CommonInit;
begin
fChanging := False;
fChanged := False;
fOnChange := nil;
end;

//------------------------------------------------------------------------------

procedure TBitVector.ScanForSetCount;
var
  i:  Integer;
begin
{$message 'reimplement, optimize'}
fSetCount := 0;
If fCount > 0 then
  For i := LowIndex to HighIndex do
    If GetBit_LL(i) then Inc(fSetCount);
end;

//------------------------------------------------------------------------------

procedure TBitVector.DoOnChange;
begin
fChanged := True;
If not fChanging and Assigned(fOnChange) then fOnChange(Self);
end;

//==============================================================================

constructor TBitVector.Create(Memory: Pointer; Count: Integer);
begin
inherited Create;
fOwnsMemory := False;
fMemSize := 0;
fMemory := Memory;
fCount := Count;
ScanForSetCount;
CommonInit;
end;

//------------------------------------------------------------------------------

constructor TBitVector.Create(InitialCapacity: Integer = 0);
begin
inherited Create;
fOwnsMemory := True;
Capacity := InitialCapacity;
fCount := 0;
fSetCount := 0;
CommonInit;
end;

//------------------------------------------------------------------------------

destructor TBitVector.Destroy;
begin
If fOwnsMemory then
  FreeMem(fMemory,fMemSize);
inherited;
end;

//------------------------------------------------------------------------------

procedure TBitVector.BeginChanging;
begin
fChanging := True;
fChanged := False;
end;

//------------------------------------------------------------------------------

Function TBitVector.EndChanging: Boolean;
begin
If fChanging then
  begin
    fChanging := False;
    Result := fChanged;
    If fChanged and Assigned(fOnChange) then fOnChange(Self);
  end
else Result := False;
end;

//------------------------------------------------------------------------------

Function TBitVector.LowIndex: Integer;
begin
Result := 0;
end;

//------------------------------------------------------------------------------

Function TBitVector.HighIndex: Integer;
begin
Result := fCount - 1;
end;

//------------------------------------------------------------------------------

Function TBitVector.Firts: Boolean;
begin
Result := GetBit(LowIndex);
end;

//------------------------------------------------------------------------------

Function TBitVector.Last: Boolean;
begin
Result := GetBit(HighIndex);
end;

//------------------------------------------------------------------------------

Function TBitVector.Grow(Force: Boolean = False): Integer;
begin
If Force then
  begin
    Capacity := Capacity + AllocDeltaBits;
    Result := Capacity;
  end
else
  begin
    If fCount >= Capacity then
      Result := Grow(True)
    else
      Result := Capacity;
  end;
end;

//------------------------------------------------------------------------------

Function TBitVector.Shrink: Integer;
begin
Capacity := fCount;
Result := Capacity;
end;

//------------------------------------------------------------------------------

Function TBitVector.Add(Value: Boolean): Integer;
begin
Grow;
Inc(fCount);
SetBit_LL(HighIndex,Value);
If Value then Inc(fSetCount);
Result := HighIndex;
DoOnChange;
end;

//------------------------------------------------------------------------------

procedure TBitVector.Insert(Index: Integer; Value: Boolean);
var
  i:  Integer;
begin
{$message 'reimplement, optimize'}
If Index = fCount then
  Add(Value)
else
  If CheckIndex(Index) then
    begin
      Grow;
      Inc(fCount);
      For i := Index to Pred(HighIndex) do
        SetBit_LL(i + 1,GetBit_LL(i));
      SetBit_LL(Index,Value);   
      If Value then Inc(fSetCount);
      DoOnChange;
    end
  else raise Exception.CreateFmt('TBitVector.Insert: Index (%d) out of bounds.',[Index]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.Delete(Index: Integer);
var
  i:  Integer;
begin
{$message 'reimplement, optimize'}
If CheckIndex(Index) then
  begin
    If GetBit_LL(Index) then Dec(fSetCount);
    For i := Index to Pred(HighIndex) do
      SetBit_LL(i,GetBit_LL(i + 1));
    Dec(fCount);
    DoOnChange;
  end
else raise Exception.CreateFmt('TBitVector.Delete: Index (%d) out of bounds.',[Index]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.Exchange(Index1, Index2: Integer);
begin
If CheckIndex(Index1) and CheckIndex(Index2) then
  begin
    SetBit_LL(Index2,SetBit_LL(Index1,GetBit_LL(Index2)));
    DoOnChange;
  end
else raise Exception.CreateFmt('TBitVector.Exchange: Index (%d, %d) out of bounds.',[Index1,Index2]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.Move(SrcIdx, DstIdx: Integer);
var
  Value:  Boolean;
  i:      Integer;
begin
{$message 'reimplement, optimize'}
If CheckIndex(SrcIdx) and CheckIndex(DstIdx) then
  begin
    If SrcIdx <> DstIdx then
      begin
        Value := GetBit_LL(SrcIdx);
        If SrcIdx < DstIdx then
          For i := SrcIdx to Pred(DstIdx) do
            SetBit_LL(i,GetBit_LL(i + 1))
        else
          For i := SrcIdx downto Succ(DstIdx) do
            SetBit_LL(i,GetBit_LL(i - 1));
        SetBit_LL(DstIdx,Value);
        DoOnChange;
      end;
  end
else raise Exception.CreateFmt('TBitVector.Move: Index (%d, %d) out of bounds.',[SrcIdx,DstIdx]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.FillTo(Value: Boolean);
var
  i:  PtrUInt;
begin
If fCount > 0 then
  begin
    If Value then
      begin
        For i := 0 to Pred(Ceil(fCount / 8)) do
          PByte(PtrUInt(fMemory) + i)^ := $FF;
        fSetCount := fCount;
      end
    else
      begin
        For i := 0 to Pred(Ceil(fCount / 8)) do
          PByte(PtrUInt(fMemory) + i)^ := 0;
        fSetCount := 0;
      end;
    DoOnChange;  
  end;
end;

//------------------------------------------------------------------------------

procedure TBitVector.Clear;
begin
Fillto(False);
end;

//------------------------------------------------------------------------------

Function TBitVector.IsEmpty: Boolean;
begin
Result := (fSetCount = 0) and (fCount > 0);
end;

//------------------------------------------------------------------------------

Function TBitVector.IsFull: Boolean;
begin
Result := (fSetCount = fCount) and (fCount > 0);
end;


end.
