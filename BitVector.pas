unit BitVector;

interface

uses
  AuxTypes;

type
  TBitVector = class(TObject)
  private
    fOwnsMemory:  Boolean;
    fMemory:      Pointer;
    fMemSize:     TMemSize;
    fCount:       Integer;
    fSetCount:    Integer;
    Function GetBit(Index: Integer): Boolean;
    procedure SetBit(Index: Integer; Value: Boolean);
    Function GetCapacity: Integer;
    procedure SetCapacity(NewCapacity: Integer);
    Function GetSetCount: Integer;
  protected
    procedure ScanForSetCount; virtual;
  public
    constructor Create(InitialCapacity: Integer = 0); overload;
    constructor Create(Memory: Pointer; Count: Integer); overload;
    destructor Destroy; override;

    Function Firts: Boolean; virtual;
    Function Last: Boolean; virtual;

    Function Add(Value: Boolean): Integer; virtual;
    procedure Insert(Index: Integer; Value: Boolean); virtual;
    procedure Delete(Index: Integer); virtual;
    procedure Exchange(Index1, Index2: Integer); virtual;
    procedure Move(SrcIdx, DstIdx: Integer); virtual;

    procedure FillTo(Value: Boolean); virtual;
    procedure Clear; virtual;

    procedure Append(Memory: Pointer; Count: Integer); overload; virtual;
    procedure Append(Vector: TBitVector); overload; virtual;
    procedure Assign(Vector: TBitVector); virtual;

    procedure SaveToStream(Stream: TStream); virtual;
    procedure LoadFromStream(Stream: TStream); virtual;
    procedure SaveToFile(const FileName: String); virtual;
    procedure LoadFromFile(const FileName: String); virtual;

    Function IsEmpty: Boolean; virtual;
    Function IsFull: Boolean; virtual;

    Function FirstSet: Integer; virtual;
    Function FirstClean: Integer; virtual;
    Function LastSet: Integer; virtual;
    Function LastClean: Integer; virtual;

    property Bits[Index: Integer]: Boolean read GetBit write SetBit;
    property Memory: Pointer read fMemory;
  published
    property OwnsMemory: Boolean read fOwnsMemory;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read fCount;
    property SetCount: Integer read GetSetCount;
  end;

implementation

end.
