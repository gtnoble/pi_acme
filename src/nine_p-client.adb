--  Nine_P.Client body — synchronous 9P2000 client implementation.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Environment_Variables;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;             use Interfaces;
with Nine_P.Proto;           use Nine_P.Proto;

package body Nine_P.Client is

   --  ── Stream helpers ────────────────────────────────────────────────────

   --  Read exactly N stream elements, retrying on partial reads.
   procedure Read_Exactly
     (S    : not null access Ada.Streams.Root_Stream_Type'Class;
      Data : out Ada.Streams.Stream_Element_Array)
   is
      use Ada.Streams;
      Offset : Stream_Element_Offset := Data'First;
      Last   : Stream_Element_Offset;
   begin
      while Offset <= Data'Last loop
         S.Read (Data (Offset .. Data'Last), Last);
         if Last < Offset then
            raise P9_Error with "connection closed unexpectedly";
         end if;
         Offset := Last + 1;
      end loop;
   end Read_Exactly;

   function Read_Message
     (S : not null access Ada.Streams.Root_Stream_Type'Class)
     return Byte_Array
   is
      use Ada.Streams;
      Header : Stream_Element_Array (0 .. 3);
      Size   : Uint32;
   begin
      Read_Exactly (S, Header);
      Size := Uint32 (Header (0))
           or Shift_Left (Uint32 (Header (1)),  8)
           or Shift_Left (Uint32 (Header (2)), 16)
           or Shift_Left (Uint32 (Header (3)), 24);
      declare
         Rest_Len : constant Stream_Element_Offset :=
           Stream_Element_Offset (Size) - 4;
         Rest     : Stream_Element_Array (0 .. Rest_Len - 1);
         Result   : Byte_Array (0 .. Natural (Size) - 1);
      begin
         Read_Exactly (S, Rest);
         Result (0) := Uint8 (Header (0));
         Result (1) := Uint8 (Header (1));
         Result (2) := Uint8 (Header (2));
         Result (3) := Uint8 (Header (3));
         for I in Rest'Range loop
            Result (4 + Natural (I)) := Uint8 (Rest (I));
         end loop;
         return Result;
      end;
   end Read_Message;

   procedure Write_Message
     (S    : not null access Ada.Streams.Root_Stream_Type'Class;
      Data : Byte_Array)
   is
      use Ada.Streams;
      SEA : Stream_Element_Array
        (0 .. Stream_Element_Offset (Data'Length) - 1);
   begin
      for I in Data'Range loop
         SEA (Stream_Element_Offset (I - Data'First)) :=
           Stream_Element (Data (I));
      end loop;
      S.Write (SEA);
   end Write_Message;

   --  ── Internal helpers ─────────────────────────────────────────────────

   function Alloc_Tag (Conn : not null access Fs'Class) return Uint16 is
      Tag : constant Uint16 := Conn.Next_Tag;
   begin
      --  Cycle 1 .. 16#FFFE#, skipping NO_TAG (16#FFFF#)
      Conn.Next_Tag :=
        Uint16 ((Uint32 (Conn.Next_Tag) mod 16#FFFE#) + 1);
      return Tag;
   end Alloc_Tag;

   function Alloc_Fid (Conn : not null access Fs'Class) return Uint32 is
      Fid : constant Uint32 := Conn.Next_Fid;
   begin
      Conn.Next_Fid := Conn.Next_Fid + 1;
      return Fid;
   end Alloc_Fid;

   function RPC (Conn : not null access Fs'Class;
                 Msg  : Message) return Message is
   begin
      Write_Message (Conn.Stream, Pack (Msg));
      declare
         Response : constant Message :=
           Unpack (Read_Message (Conn.Stream));
      begin
         if Response.Kind = Kind_Rerror then
            raise P9_Error with To_String (Response.Ename);
         end if;
         return Response;
      end;
   end RPC;

   procedure Clunk_Fid
     (Conn : not null access Fs'Class;
      Fid  : Uint32)
   is
   begin
      Write_Message
        (Conn.Stream,
         Pack ((Kind       => Kind_Tclunk,
                Tag        => Alloc_Tag (Conn),
                Simple_Fid => Fid)));
      --  Consume the Rclunk; ignore errors (socket may be closing).
      declare
         Dummy : constant Byte_Array := Read_Message (Conn.Stream);
         pragma Unreferenced (Dummy);
      begin
         null;
      end;
   exception
      when others => null;  --  Best-effort cleanup; errors silently dropped.
   end Clunk_Fid;

   --  Split a path like "/1/ctl" into walk name components.
   procedure Path_Parts
     (Path   :  String;
      Names  : out Name_Array;
      Nwname : out Walk_Count)
   is
      Start : Natural := Path'First;
   begin
      Names  := (others => Null_Unbounded_String);
      Nwname := 0;
      if Start <= Path'Last and then Path (Start) = '/' then
         Start := Start + 1;
      end if;
      for I in Start .. Path'Last loop
         if Path (I) = '/' and then I > Start then
            Nwname := Nwname + 1;
            Names (Nwname) :=
              To_Unbounded_String (Path (Start .. I - 1));
            Start := I + 1;
         end if;
      end loop;
      if Start <= Path'Last then
         Nwname := Nwname + 1;
         Names (Nwname) :=
           To_Unbounded_String (Path (Start .. Path'Last));
      end if;
   end Path_Parts;

   function Walk_Path
     (Conn : not null access Fs'Class;
      Path : String) return Uint32
   is
      New_Fid : constant Uint32 := Alloc_Fid (Conn);
      Tag     : constant Uint16 := Alloc_Tag (Conn);
      Names   : Name_Array;
      Nwname  : Walk_Count;
   begin
      Path_Parts (Path, Names, Nwname);
      declare
         Response : constant Message :=
           RPC (Conn,
                (Kind        => Kind_Twalk,
                 Tag         => Tag,
                 Walk_Fid    => Conn.Root_Fid,
                 Walk_Newfid => New_Fid,
                 Walk_Nwname => Nwname,
                 Walk_Names  => Names));
      begin
         if Response.Kind /= Kind_Rwalk then
            Clunk_Fid (Conn, New_Fid);
            raise P9_Error with "expected Rwalk for: " & Path;
         end if;
         if Nwname > 0 and then Response.Walk_Nwqid /= Nwname then
            Clunk_Fid (Conn, New_Fid);
            raise P9_Error with "file not found: " & Path;
         end if;
         return New_Fid;
      end;
   end Walk_Path;

   procedure Do_Negotiate (Conn : not null access Fs'Class) is
      Request : constant Message :=
        (Kind    => Kind_Tversion,
         Tag     => NO_TAG,
         MSize   => Conn.MSize,
         Version => To_Unbounded_String (VERSION_9P));
   begin
      Write_Message (Conn.Stream, Pack (Request));
      declare
         Response : constant Message :=
           Unpack (Read_Message (Conn.Stream));
      begin
         if Response.Kind /= Kind_Rversion then
            raise P9_Error with "expected Rversion during negotiation";
         end if;
         if To_String (Response.Version) /= VERSION_9P then
            raise P9_Error
              with "unsupported server version: "
                   & To_String (Response.Version);
         end if;
         Conn.MSize := Uint32'Min (Conn.MSize, Response.MSize);
      end;
   end Do_Negotiate;

   procedure Do_Attach
     (Conn  : not null access Fs'Class;
      Aname : String)
   is
      Tag      : constant Uint16 := Alloc_Tag (Conn);
      Response : constant Message :=
        RPC (Conn,
             (Kind      => Kind_Tattach,
              Tag       => Tag,
              Att_Fid   => Conn.Root_Fid,
              Att_AFid  => NO_FID,
              Att_Uname => Conn.Uname,
              Att_Aname => To_Unbounded_String (Aname)));
      pragma Unreferenced (Response);
   begin
      null;
   end Do_Attach;

   --  ── Namespace / Dial ─────────────────────────────────────────────────

   function Namespace return String is
      use Ada.Environment_Variables;
   begin
      if Exists ("NAMESPACE") then
         declare
            Namespace_Value : constant String := Value ("NAMESPACE");
         begin
            if Namespace_Value'Length > 0 then
               return Namespace_Value;
            end if;
         end;
      end if;
      declare
         User    : constant String :=
           (if Exists ("USER") then Value ("USER") else "nobody");
         Raw_Display : constant String :=
           (if Exists ("DISPLAY") then Value ("DISPLAY") else ":0");
         --  plan9port getns() strips the screen-number suffix from DISPLAY
         --  e.g. ":0.0" -> ":0", ":1.0" -> ":1"
         Dot_Pos : Natural := 0;
      begin
         --  Find the last '.' that follows a ':' (screen separator)
         for I in Raw_Display'Range loop
            if Raw_Display (I) = '.' then
               Dot_Pos := I;
            end if;
         end loop;
         declare
            Display : constant String :=
              (if Dot_Pos > Raw_Display'First
               then Raw_Display (Raw_Display'First .. Dot_Pos - 1)
               else Raw_Display);
         begin
            return "/tmp/ns." & User & "." & Display;
         end;
      end;
   end Namespace;

   function Dial
     (Addr  : String;
      Aname : String := "";
      Uname : String := "") return Fs
   is
      use GNAT.Sockets;
      use Ada.Environment_Variables;
      --  Parse "net!rest" into (Net, Rest)
      Exclaim_Pos : Natural := 0;
   begin
      for I in Addr'Range loop
         if Addr (I) = '!' then
            Exclaim_Pos := I;
            exit;
         end if;
      end loop;
      if Exclaim_Pos = 0 then
         raise P9_Error with "malformed dial address: " & Addr;
      end if;
      return Result : Fs do
         Result.Uname := To_Unbounded_String
           ((if Uname'Length > 0 then Uname
             elsif Exists ("USER") then Value ("USER")
             else "nobody"));
         declare
            Net  : constant String :=
              Addr (Addr'First .. Exclaim_Pos - 1);
            Rest : constant String :=
              Addr (Exclaim_Pos + 1 .. Addr'Last);
         begin
            if Net = "unix" then
               Create_Socket
                 (Result.Socket, Family_Unix, Socket_Stream);
               Connect_Socket
                 (Result.Socket, Unix_Socket_Address (Rest));
            elsif Net in "tcp" | "tcp4" | "tcp6" then
               --  Parse "host!port" within Rest
               declare
                  Second_Exclaim : Natural := 0;
               begin
                  for I in Rest'Range loop
                     if Rest (I) = '!' then
                        Second_Exclaim := I;
                        exit;
                     end if;
                  end loop;
                  declare
                     Host : constant String :=
                       (if Second_Exclaim > 0
                        then Rest (Rest'First .. Second_Exclaim - 1)
                        else Rest);
                     Port : constant Port_Type :=
                       (if Second_Exclaim > 0
                        then Port_Type'Value
                               (Rest (Second_Exclaim + 1 .. Rest'Last))
                        else 564);
                  begin
                     Create_Socket
                       (Result.Socket, Family_Inet, Socket_Stream);
                     Connect_Socket
                       (Result.Socket,
                        (Family => Family_Inet,
                         Addr   => Inet_Addr (Host),
                         Port   => Port));
                  end;
               end;
            else
               raise P9_Error with "unsupported network: " & Net;
            end if;
         end;
         --  Wrap socket as a stream
         Result.Stream := GNAT.Sockets.Stream (Result.Socket);
         Do_Negotiate (Result'Access);
         Do_Attach    (Result'Access, Aname);
      end return;
   end Dial;

   function Ns_Mount
     (Name  : String;
      Aname : String := "";
      Uname : String := "") return Fs
   is
   begin
      return Dial ("unix!" & Namespace & "/" & Name, Aname, Uname);
   end Ns_Mount;

   --  ── Finalize ─────────────────────────────────────────────────────────

   overriding procedure Finalize (Object : in out Fs) is
      use GNAT.Sockets;
   begin
      if Object.Socket /= No_Socket then
         begin
            --  Best-effort root clunk before closing.
            Clunk_Fid (Object'Unchecked_Access, Object.Root_Fid);
         exception
            --  Exceptions during finalization are silently discarded
            --  (Ada RM 7.6.1); nothing useful can be done here.
            when others => null;
         end;
         Close_Socket (Object.Socket);
         Object.Socket := No_Socket;
         Object.Stream := null;
      end if;
   end Finalize;

   overriding procedure Finalize (Object : in out File) is
   begin
      if Object.Is_Open then
         Object.Is_Open := False;
         begin
            Clunk_Fid (Object.Filesystem, Object.Fid);
         exception
            --  Exceptions during finalization are silently discarded
            --  (Ada RM 7.6.1); nothing useful can be done here.
            when others => null;
         end;
      end if;
   end Finalize;

   --  ── Open / Read / Write ───────────────────────────────────────────────

   function Open
     (Filesystem : not null access Fs'Class;
      Path       : String;
      Mode       : Uint8 := O_READ) return File
   is
   begin
      return Result : File do
         Result.Filesystem := Filesystem.all'Unchecked_Access;
         Result.Fid        := Walk_Path (Filesystem, Path);
         begin
            declare
               Tag      : constant Uint16 := Alloc_Tag (Filesystem);
               Response : constant Message :=
                 RPC (Filesystem,
                      (Kind      => Kind_Topen,
                       Tag       => Tag,
                       Open_Fid  => Result.Fid,
                       Open_Mode => Mode));
            begin
               Result.IOunit :=
                 (if Response.Opened_Iounit > 0
                  then Natural (Response.Opened_Iounit)
                  else Natural (Filesystem.MSize) - 24);
               Result.Mode    := Mode;
               Result.Offset  := 0;
               Result.Is_Open := True;
            end;
         exception
            when others =>
               Clunk_Fid (Filesystem, Result.Fid);
               raise;
         end;
      end return;
   end Open;

   function Read
     (F : not null access File'Class;
      N : Integer := -1) return Byte_Array
   is
      Iounit : constant Uint32 :=
        (if F.IOunit > 0
         then Uint32 (F.IOunit)
         else F.Filesystem.MSize - 24);
      Chunks : Byte_Vectors.Vector;
   begin
      loop
         exit when N >= 0
           and then Natural (Chunks.Length) >= N;
         declare
            Count : constant Uint32 :=
              (if N < 0
               then Iounit
               else Uint32'Min
                      (Iounit,
                       Uint32 (N) -
                         Uint32 (Natural (Chunks.Length))));
            Tag      : constant Uint16   := Alloc_Tag (F.Filesystem);
            Response : constant Message  :=
              RPC (F.Filesystem,
                   (Kind      => Kind_Tread,
                    Tag       => Tag,
                    Rd_Fid    => F.Fid,
                    Rd_Offset => F.Offset,
                    Rd_Count  => Count));
            Data : constant String := To_String (Response.Rd_Data);
         begin
            exit when Data'Length = 0;
            for C of Data loop
               Chunks.Append (Uint8 (Character'Pos (C)));
            end loop;
            F.Offset := F.Offset + Uint64 (Data'Length);
         end;
      end loop;
      --  Convert vector to flat Byte_Array
      declare
         Length : constant Natural := Natural (Chunks.Length);
         Result : Byte_Array (0 .. Length - 1);
      begin
         for I in Result'Range loop
            Result (I) := Chunks (I);
         end loop;
         return Result;
      end;
   end Read;

   function Read_Once (F : not null access File'Class) return Byte_Array is
      Iounit : constant Uint32 :=
        (if F.IOunit > 0
         then Uint32 (F.IOunit)
         else F.Filesystem.MSize - 24);
      Tag      : constant Uint16   := Alloc_Tag (F.Filesystem);
      Response : constant Message  :=
        RPC (F.Filesystem,
             (Kind      => Kind_Tread,
              Tag       => Tag,
              Rd_Fid    => F.Fid,
              Rd_Offset => F.Offset,
              Rd_Count  => Iounit));
      Data : constant String := To_String (Response.Rd_Data);
   begin
      F.Offset := F.Offset + Uint64 (Data'Length);
      declare
         Result : Byte_Array (0 .. Data'Length - 1);
      begin
         for I in Data'Range loop
            Result (I - Data'First) :=
              Uint8 (Character'Pos (Data (I)));
         end loop;
         return Result;
      end;
   end Read_Once;

   function Write
     (F    : not null access File'Class;
      Data : Byte_Array) return Natural
   is
      Iounit : constant Natural :=
        (if F.IOunit > 0
         then F.IOunit
         else Natural (F.Filesystem.MSize) - 24);
      Total  : Natural := 0;
   begin
      --  A zero-length write must still send one Twrite RPC so that
      --  servers (e.g. acme's data VFS file) receive the request to
      --  replace the currently addressed selection with nothing.  The
      --  chunk loop below never executes when Data is empty, so handle
      --  this case explicitly before entering the loop.
      if Data'Length = 0 then
         declare
            Tag      : constant Uint16  := Alloc_Tag (F.Filesystem);
            Response : constant Message :=
              RPC (F.Filesystem,
                   (Kind      => Kind_Twrite,
                    Tag       => Tag,
                    Wr_Fid    => F.Fid,
                    Wr_Offset => F.Offset,
                    Wr_Data   => Null_Unbounded_String));
            pragma Unreferenced (Response);
         begin
            return 0;
         end;
      end if;
      while Total < Data'Length loop
         declare
            Chunk_Length : constant Natural :=
              Natural'Min (Iounit, Data'Length - Total);
            Chunk_String : String (1 .. Chunk_Length);
         begin
            for I in 1 .. Chunk_Length loop
               Chunk_String (I) :=
                 Character'Val (Data (Data'First + Total + I - 1));
            end loop;
            declare
               Tag      : constant Uint16 := Alloc_Tag (F.Filesystem);
               Response : constant Message :=
                 RPC (F.Filesystem,
                      (Kind      => Kind_Twrite,
                       Tag       => Tag,
                       Wr_Fid    => F.Fid,
                       Wr_Offset => F.Offset,
                       Wr_Data   =>
                         To_Unbounded_String (Chunk_String)));
               Written : constant Natural :=
                 Natural (Response.Wr_Count);
            begin
               F.Offset := F.Offset + Uint64 (Written);
               Total    := Total + Written;
               exit when Written = 0;
            end;
         end;
      end loop;
      return Total;
   end Write;

   function Write
     (F    : not null access File'Class;
      Data : String) return Natural
   is
      Byte_Data : Byte_Array (0 .. Data'Length - 1);
   begin
      for I in Data'Range loop
         Byte_Data (I - Data'First) :=
           Uint8 (Character'Pos (Data (I)));
      end loop;
      return Write (F, Byte_Data);
   end Write;

end Nine_P.Client;
