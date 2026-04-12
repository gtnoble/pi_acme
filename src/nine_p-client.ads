--  Nine_P.Client — synchronous 9P2000 client.
--
--  Fs and File are Limited_Controlled: the socket is closed and fids
--  are clunked automatically when the objects go out of scope.
--  No explicit Free or Close calls are required.
--
--  Typical usage:
--
--    declare
--       FS   : Nine_P.Client.Fs   := Nine_P.Client.Ns_Mount ("acme");
--       Ctl  : Nine_P.Client.File :=
--                Nine_P.Client.Open (FS'Access, "/new/ctl");
--       Data : Nine_P.Byte_Array  := Nine_P.Client.Read (Ctl'Access);
--    begin
--       ...
--    end;  --  Ctl clunked, FS socket closed here
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Finalization;
with Ada.Streams;
with Ada.Strings.Unbounded;
with GNAT.Sockets;

package Nine_P.Client is

   --  ── Fs ───────────────────────────────────────────────────────────────

   type Fs is tagged limited private;

   --  ── File ─────────────────────────────────────────────────────────────

   type File is tagged limited private;

   --  ── Connection ───────────────────────────────────────────────────────

   --  Return the plan9port namespace directory.
   --  Uses $NAMESPACE; falls back to /tmp/ns.<USER>.<DISPLAY>.
   function Namespace return String;

   --  Connect using plan9port dial(3) notation:
   --    "unix!/path/to/socket"  or  "tcp!host!port"
   function Dial (Addr  : String;
                  Aname : String := "";
                  Uname : String := "") return Fs;

   --  Connect to a named service in the plan9port namespace.
   function Ns_Mount (Name  : String;
                      Aname : String := "";
                      Uname : String := "") return Fs;

   --  ── File operations ──────────────────────────────────────────────────

   --  Walk + open a path; caller passes Fs'Access.
   --  Using Fs'Class avoids a dual-dispatch conflict between Fs and File.
   function Open (Filesystem : not null access Fs'Class;
                  Path       : String;
                  Mode       : Uint8 := O_READ) return File;

   --  Read up to N bytes (N < 0 → read until EOF).
   --  Uses Byte_Vectors internally for chunk accumulation;
   --  returns a flat Byte_Array.
   function Read (F : not null access File'Class;
                  N : Integer := -1) return Byte_Array;

   --  Issue exactly one Tread RPC and return whatever bytes the server
   --  sends back (up to the file's IOunit).  Unlike Read, this never
   --  loops: it returns as soon as one response arrives, which is
   --  essential for pseudo-files (acme event, plumb ports) that block
   --  until data is ready but return partial results each time.
   --  Returns an empty array on EOF.
   function Read_Once (F : not null access File'Class) return Byte_Array;

   --  Write bytes; return number of bytes written.
   function Write (F    : not null access File'Class;
                   Data : Byte_Array) return Natural;

   --  Write a String as raw bytes.
   function Write (F    : not null access File'Class;
                   Data : String) return Natural;

   --  ── Stream-level framing (also useful for testing) ───────────────────

   --  Read exactly one complete 9P message from S.
   --  Reads the 4-byte little-endian size prefix first.
   function Read_Message
     (S : not null access Ada.Streams.Root_Stream_Type'Class)
     return Byte_Array;

   --  Write one complete 9P message to S.
   procedure Write_Message
     (S    : not null access Ada.Streams.Root_Stream_Type'Class;
      Data : Byte_Array);

private

   use Ada.Strings.Unbounded;

   type Fs is new Ada.Finalization.Limited_Controlled with record
      Socket   : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Stream   : GNAT.Sockets.Stream_Access := null;
      Next_Tag : Uint16 := 1;
      Next_Fid : Uint32 := 2;
      Root_Fid : Uint32 := 1;
      MSize    : Uint32 := 65536;
      Uname    : Unbounded_String;
   end record;

   overriding procedure Finalize (Object : in out Fs);

   type File is new Ada.Finalization.Limited_Controlled with record
      Filesystem : access Fs   := null;
      Fid        : Uint32      := 0;
      IOunit     : Natural     := 0;
      Mode       : Uint8       := O_READ;
      Offset     : Uint64      := 0;
      Is_Open    : Boolean     := False;
   end record;

   overriding procedure Finalize (Object : in out File);

end Nine_P.Client;
