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
    procedure ShiftDown(Idx1,Idx2: Integer); virtual;
    procedure ShiftUp(Idx1,Idx2: Integer); virtual;
    Function CheckIndex(Index: Integer): Boolean; virtual;
    procedure CommonInit; virtual;
    procedure ScanForSetCount; virtual;
    procedure DoOnChange; virtual;
  public
    constructor Create(Memory: Pointer; Count: Integer); overload;
    constructor Create(InitialCount: Integer = 0; InitialValue: Boolean = False); overload;
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
    procedure Complement; virtual;
    procedure Clear; virtual;

    Function IsEmpty: Boolean; virtual;
    Function IsFull: Boolean; virtual;

    Function FirstSet: Integer; virtual;
    Function FirstClean: Integer; virtual;
    Function LastSet: Integer; virtual;
    Function LastClean: Integer; virtual;
(*
    procedure Append(Memory: Pointer; Count: Integer); overload; virtual;
    procedure Append(Vector: TBitVector); overload; virtual;

    procedure Assign(Memory: Pointer; Count: Integer); virtual; overload;
    procedure Assign(Vector: TBitVector); virtual; overload;
    procedure AssignOR(Memory: Pointer; Count: Integer); virtual; overload;
    procedure AssignOR(Vector: TBitVector); virtual; overload;
    procedure AssignAND(Memory: Pointer; Count: Integer); virtual; overload;
    procedure AssignAND(Vector: TBitVector); virtual; overload;
    procedure AssignXOR(Memory: Pointer; Count: Integer); virtual; overload;
    procedure AssignXOR(Vector: TBitVector); virtual; overload;

    Function Same(Vector: TBitVector): Boolean; virtual;

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
  AllocDeltaBytes = 4;


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
        fMemSize := NewMemSize;
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

procedure TBitVector.ShiftDown(Idx1,Idx2: Integer);
var
  i:      Integer;
  Temp:   UInt16;
  Carry:  Boolean;
begin
If Idx2 > Idx1 then
  begin
    If (Idx2 shr 3) - (Idx1 shr 3) > 1 then
      begin
        // shift last byte and preserve shifted-out bit
        Carry := GetBit_LL(Idx2 and not 7);
        For i := (Idx2 and not 7) to Pred(Idx2) do
          SetBit_LL(i,GetBit_LL(i + 1));
        // shift whole bytes
        For i := Pred(Idx2 shr 3) downto Succ(Idx1 shr 3) do
          begin
            If Carry then
              Temp := UInt16(PByte(PtrUInt(fMemory) + PtrUInt(i))^) or $0100
            else
              Temp := UInt16(PByte(PtrUInt(fMemory) + PtrUInt(i))^) and $FEFF;
            Carry := (Temp and 1) <> 0;
            PByte(PtrUInt(fMemory) + PtrUInt(i))^ := Byte(Temp shr 1);
          end;
        // shift first byte and store carry
        For i := Idx1 to Pred(Idx1 or 7) do
          SetBit_LL(i,GetBit_LL(i + 1));
        SetBit_LL(Idx1 or 7,Carry);
      end
    else
      For i := Idx1 to Pred(Idx2) do
        SetBit_LL(i,GetBit_LL(i + 1));
  end
else raise Exception.CreateFmt('TBitVector.ShiftDown: First index (%d) must be smaller or equal to the second index (%d).',[Idx1,Idx2]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.ShiftUp(Idx1,Idx2: Integer);
var
  i:      Integer;
  Temp:   UInt16;
  Carry:  Boolean;
begin
If Idx2 > Idx1 then
  begin
    If (Idx2 shr 3) - (Idx1 shr 3) > 1 then
      begin
        // shift first byte and preserve shifted-out bit
        Carry := GetBit_LL(Idx1 or 7);
        For i := (Idx1 or 7) downto Succ(Idx1) do
          SetBit_LL(i,GetBit_LL(i - 1));
        // shift whole bytes
        For i := Succ(Idx1 shr 3) to Pred(Idx2 shr 3) do
          begin
            If Carry then
              Temp := (UInt16(PByte(PtrUInt(fMemory) + PtrUInt(i))^) shl 1) or 1
            else
              Temp := (UInt16(PByte(PtrUInt(fMemory) + PtrUInt(i))^) shl 1) and not 1;
            Carry := (Temp and $100) <> 0;
            PByte(PtrUInt(fMemory) + PtrUInt(i))^ := Byte(Temp);
          end;
        // shift last byte and store carry
        For i := Idx2 downto Succ(Idx2 and not 7) do
          SetBit_LL(i,GetBit_LL(i - 1));
        SetBit_LL(Idx2 and not 7,Carry);
      end
    else
      For i := Idx2 downto Succ(Idx1) do
        SetBit_LL(i,GetBit_LL(i - 1));
  end
else raise Exception.CreateFmt('TBitVector.ShiftUp: First index (%d) must be smaller or equal to the second index (%d).',[Idx1,Idx2]);
end;

//------------------------------------------------------------------------------

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
  i:        Integer;
  WorkPtr:  PByte;

  Function CountBits(Buff: Byte; MaxBits: Byte = 8): Integer;
  var
    ii: Integer;
  begin
    Result := 0;
    If MaxBits >= 8 then
      case Buff of
          0:  Exit; // do nothing, result is already 0
        255:  Result := 8;
      else
        For ii := 0 to 7 do
          If ((Buff shr ii) and 1) <> 0 then Inc(Result);
      end
    else
      For ii := 0 to Pred(MaxBits) do
        If ((Buff shr ii) and 1) <> 0 then Inc(Result);
  end;

begin
fSetCount := 0;
If fCount > 0 then
  begin
    WorkPtr := PByte(fMemory);
    For i := 0 to Pred(fCount shr 3) do
      begin
        Inc(fSetCount,CountBits(WorkPtr^));
        Inc(WorkPtr);
      end;
    If (fCount and 7) > 0 then
      Inc(fSetCount,CountBits(WorkPtr^,fCount and 7));
  end;
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

constructor TBitVector.Create(InitialCount: Integer = 0; InitialValue: Boolean = False);
begin
inherited Create;
fOwnsMemory := True;
Capacity := InitialCount;
fCount := InitialCount;
FillTo(InitialValue); // SetCout is set in this routine
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
If fOwnsMemory then
  begin
    Grow;
    Inc(fCount);
    SetBit_LL(HighIndex,Value);
    If Value then Inc(fSetCount);
    Result := HighIndex;
    DoOnChange;
  end
else raise Exception.Create('TBitVector.Add: Method not allowed for not owned memory.');
end;

//------------------------------------------------------------------------------

procedure TBitVector.Insert(Index: Integer; Value: Boolean);
begin
If fOwnsMemory then
  begin
    If Index >= fCount then
      Add(Value)
    else
      begin
        If CheckIndex(Index) then
          begin
            Grow;
            Inc(fCount);
            ShiftUp(Index,HighIndex);
            SetBit_LL(Index,Value);
            If Value then Inc(fSetCount);
            DoOnChange;
          end
        else raise Exception.CreateFmt('TBitVector.Insert: Index (%d) out of bounds.',[Index]);
      end;
  end
else raise Exception.Create('TBitVector.Insert: Method not allowed for not owned memory.');
end;

//------------------------------------------------------------------------------

procedure TBitVector.Delete(Index: Integer);
begin
If fOwnsMemory then
  begin
    If CheckIndex(Index) then
      begin
        If GetBit_LL(Index) then Dec(fSetCount);
        If Index < HighIndex then
          ShiftDown(Index,HighIndex);
        Dec(fCount);
        DoOnChange;
      end
    else raise Exception.CreateFmt('TBitVector.Delete: Index (%d) out of bounds.',[Index]);
  end
else raise Exception.Create('TBitVector.Delete: Method not allowed for not owned memory.');
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
begin
If CheckIndex(SrcIdx) and CheckIndex(DstIdx) then
  begin
    If SrcIdx <> DstIdx then
      begin
        Value := GetBit_LL(SrcIdx);
        If SrcIdx < DstIdx then
          ShiftDown(SrcIdx,DstIdx)
        else
          ShiftUp(DstIdx,SrcIdx);
        SetBit_LL(DstIdx,Value);
        DoOnChange;
      end;
  end
else raise Exception.CreateFmt('TBitVector.Move: Index (%d, %d) out of bounds.',[SrcIdx,DstIdx]);
end;

//------------------------------------------------------------------------------

procedure TBitVector.FillTo(Value: Boolean);
var
  i:  Integer;
begin
If fCount > 0 then
  begin
    For i := 0 to Pred(fCount div 8) do
      PByte(PtrUInt(fMemory) + PtrUInt(i))^ := $FF * Ord(Value);
    For i := (fCount and not 7) to Pred(fCount) do
      SetBit_LL(i,Value);
    fSetCount := fCount * Ord(Value);      
    DoOnChange;
  end;
end;

//------------------------------------------------------------------------------

procedure TBitVector.Complement;
var
  i:  Integer;
begin
If fCount > 0 then
  begin
    For i := 0 to Pred(fCount div 8) do
      PByte(PtrUInt(fMemory) + PtrUInt(i))^ := not PByte(PtrUInt(fMemory) + PtrUInt(i))^;
    For i := (fCount and not 7) to Pred(fCount) do
      SetBit_LL(i,not GetBit_LL(i));
    fSetCount := fCount - fSetCount;
    DoOnChange;
  end;
end;

//------------------------------------------------------------------------------

procedure TBitVector.Clear;
begin
fCount := 0;
fSetCount := 0;
DoOnChange;
end;

//------------------------------------------------------------------------------

Function TBitVector.IsEmpty: Boolean;
begin
Result := (fCount > 0) and (fSetCount = 0);
end;

//------------------------------------------------------------------------------

Function TBitVector.IsFull: Boolean;
begin
Result := (fCount > 0) and (fSetCount = fCount);
end;

//------------------------------------------------------------------------------

Function TBitVector.FirstSet: Integer;
var
  i:        Integer;
  WorkByte: Byte;

  Function ScanByte(Value: Byte): Integer;
  begin
    For Result := 0 to 7 do
      If (Value shr Result) and 1 <> 0 then Exit;
    raise Exception.Create('TBitVector.FirstSet.ScanByte: Operation not allowed.');
  end;

begin
If fCount > 0 then
  begin
    For i := 0 to Pred(fCount div 8) do
      begin
        WorkByte := PByte(PtrUInt(fMemory) + PtrUInt(i))^;
        If WorkByte <> 0 then
          begin
            Result := (i * 8) + ScanByte(WorkByte);
            Exit;
          end;
      end;
    For Result := (fCount and not 7) to Pred(fCount) do
      If GetBit_LL(Result) then Exit;
    Result := -1;
  end
else Result := -1;
end;

//------------------------------------------------------------------------------

Function TBitVector.FirstClean: Integer;
var
  i:        Integer;
  WorkByte: Byte;

  Function ScanByte(Value: Byte): Integer;
  begin
    For Result := 0 to 7 do
      If (Value shr Result) and 1 = 0 then Exit;
    raise Exception.Create('TBitVector.FirstClean.ScanByte: Operation not allowed.');
  end;

begin
If fCount > 0 then
  begin
    For i := 0 to Pred(fCount div 8) do
      begin
        WorkByte := PByte(PtrUInt(fMemory) + PtrUInt(i))^;
        If WorkByte <> $FF then
          begin
            Result := (i * 8) + ScanByte(WorkByte);
            Exit;
          end;
      end;
    For Result := (fCount and not 7) to Pred(fCount) do
      If not GetBit_LL(Result) then Exit;
    Result := -1;
  end
else Result := -1;
end;

//------------------------------------------------------------------------------

Function TBitVector.LastSet: Integer;
var
  i:        Integer;
  WorkByte: Byte;

  Function ScanByte(Value: Byte): Integer;
  begin
    For Result := 7 downto 0 do
      If (Value shr Result) and 1 <> 0 then Exit;
    raise Exception.Create('TBitVector.LastSet.ScanByte: Operation not allowed.');
  end;

begin
If fCount > 0 then
  begin
    For Result := Pred(fCount) downto (fCount and not 7) do
      If GetBit_LL(Result) then Exit;
    For i := Pred(fCount div 8) downto 0 do
      begin
        WorkByte := PByte(PtrUInt(fMemory) + PtrUInt(i))^;
        If WorkByte <> 0 then
          begin
            Result := (i * 8) + ScanByte(WorkByte);
            Exit;
          end;
      end;
    Result := -1;
  end
else Result := -1;
end;

//------------------------------------------------------------------------------

Function TBitVector.LastClean: Integer;
var
  i:        Integer;
  WorkByte: Byte;

  Function ScanByte(Value: Byte): Integer;
  begin
    For Result := 7 downto 0 do
      If (Value shr Result) and 1 = 0 then Exit;
    raise Exception.Create('TBitVector.LastSet.ScanByte: Operation not allowed.');
  end;

begin
If fCount > 0 then
  begin
    For Result := Pred(fCount) downto (fCount and not 7) do
      If not GetBit_LL(Result) then Exit;
    For i := Pred(fCount div 8) downto 0 do
      begin
        WorkByte := PByte(PtrUInt(fMemory) + PtrUInt(i))^;
        If WorkByte <> $FF then
          begin
            Result := (i * 8) + ScanByte(WorkByte);
            Exit;
          end;
      end;
    Result := -1;
  end
else Result := -1;
end;

end.
