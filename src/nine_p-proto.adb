--  Nine_P.Proto body — 9P2000 message encode / decode.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;             use Interfaces;

package body Nine_P.Proto is

   MAX_MSG_SIZE : constant := 65536;

   --  ── Little-endian writers ─────────────────────────────────────────────

   procedure Write_Byte
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Uint8)
   is
   begin
      Buffer (Position) := Value;
      Position := Position + 1;
   end Write_Byte;

   procedure Write_U16
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Uint16)
   is
   begin
      Buffer (Position)     := Uint8 (Value and 16#FF#);
      Buffer (Position + 1) := Uint8 (Shift_Right (Value, 8));
      Position := Position + 2;
   end Write_U16;

   procedure Write_U32
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Uint32)
   is
   begin
      Buffer (Position)     := Uint8 (Value and 16#FF#);
      Buffer (Position + 1) := Uint8 (Shift_Right (Value,  8) and 16#FF#);
      Buffer (Position + 2) := Uint8 (Shift_Right (Value, 16) and 16#FF#);
      Buffer (Position + 3) := Uint8 (Shift_Right (Value, 24));
      Position := Position + 4;
   end Write_U32;

   procedure Write_U64
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Uint64)
   is
   begin
      for I in 0 .. 7 loop
         Buffer (Position + I) :=
           Uint8 (Shift_Right (Value, I * 8) and 16#FF#);
      end loop;
      Position := Position + 8;
   end Write_U64;

   --  Write a length-prefixed 9P string: u16 byte-count then raw UTF-8.
   procedure Write_String
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     String)
   is
   begin
      Write_U16 (Buffer, Position, Uint16 (Value'Length));
      for C of Value loop
         Buffer (Position) := Uint8 (Character'Pos (C));
         Position := Position + 1;
      end loop;
   end Write_String;

   procedure Write_Qid
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Qid)
   is
   begin
      Write_Byte (Buffer, Position, Value.Qtype);
      Write_U32  (Buffer, Position, Value.Vers);
      Write_U64  (Buffer, Position, Value.Path);
   end Write_Qid;

   --  Write a Stat including its leading 2-byte body-size field.
   --  Wire layout: [u16 body_size][u16 stype][u32 dev][Qid][u32 mode]
   --               [u32 atime][u32 mtime][u64 length]
   --               [str name][str uid][str gid][str muid]
   procedure Write_Stat
     (Buffer   : in out Byte_Array;
      Position : in out Natural;
      Value    :     Stat)
   is
      Size_Pos   : constant Natural := Position;
      Body_Start : constant Natural := Position + 2;
   begin
      Position := Body_Start;  --  skip the size placeholder
      Write_U16  (Buffer, Position, Value.Stype);
      Write_U32  (Buffer, Position, Value.Dev);
      Write_Qid  (Buffer, Position, Value.Sqid);
      Write_U32  (Buffer, Position, Value.Mode);
      Write_U32  (Buffer, Position, Value.Atime);
      Write_U32  (Buffer, Position, Value.Mtime);
      Write_U64  (Buffer, Position, Value.Length);
      Write_String (Buffer, Position, To_String (Value.Name));
      Write_String (Buffer, Position, To_String (Value.Uid));
      Write_String (Buffer, Position, To_String (Value.Gid));
      Write_String (Buffer, Position, To_String (Value.Muid));
      --  Back-fill body size (bytes written after the size field itself)
      declare
         Body_Size     : constant Uint16 :=
           Uint16 (Position - Body_Start);
         Size_Write_Pos : Natural := Size_Pos;
      begin
         Write_U16 (Buffer, Size_Write_Pos, Body_Size);
      end;
   end Write_Stat;

   --  ── Kind ↔ code mapping ───────────────────────────────────────────────

   function Kind_To_Code (Kind : Message_Kind) return Uint8 is
   begin
      case Kind is
         when Kind_Tversion => return T_VERSION;
         when Kind_Rversion => return R_VERSION;
         when Kind_Tauth    => return T_AUTH;
         when Kind_Rauth    => return R_AUTH;
         when Kind_Tattach  => return T_ATTACH;
         when Kind_Rattach  => return R_ATTACH;
         when Kind_Rerror   => return R_ERROR;
         when Kind_Tflush   => return T_FLUSH;
         when Kind_Rflush   => return R_FLUSH;
         when Kind_Twalk    => return T_WALK;
         when Kind_Rwalk    => return R_WALK;
         when Kind_Topen    => return T_OPEN;
         when Kind_Ropen    => return R_OPEN;
         when Kind_Tcreate  => return T_CREATE;
         when Kind_Rcreate  => return R_CREATE;
         when Kind_Tread    => return T_READ;
         when Kind_Rread    => return R_READ;
         when Kind_Twrite   => return T_WRITE;
         when Kind_Rwrite   => return R_WRITE;
         when Kind_Tclunk   => return T_CLUNK;
         when Kind_Rclunk   => return R_CLUNK;
         when Kind_Tremove  => return T_REMOVE;
         when Kind_Rremove  => return R_REMOVE;
         when Kind_Tstat    => return T_STAT;
         when Kind_Rstat    => return R_STAT;
         when Kind_Twstat   => return T_WSTAT;
         when Kind_Rwstat   => return R_WSTAT;
      end case;
   end Kind_To_Code;

   function Code_To_Kind (Code : Uint8) return Message_Kind is
   begin
      case Code is
         when T_VERSION => return Kind_Tversion;
         when R_VERSION => return Kind_Rversion;
         when T_AUTH    => return Kind_Tauth;
         when R_AUTH    => return Kind_Rauth;
         when T_ATTACH  => return Kind_Tattach;
         when R_ATTACH  => return Kind_Rattach;
         when R_ERROR   => return Kind_Rerror;
         when T_FLUSH   => return Kind_Tflush;
         when R_FLUSH   => return Kind_Rflush;
         when T_WALK    => return Kind_Twalk;
         when R_WALK    => return Kind_Rwalk;
         when T_OPEN    => return Kind_Topen;
         when R_OPEN    => return Kind_Ropen;
         when T_CREATE  => return Kind_Tcreate;
         when R_CREATE  => return Kind_Rcreate;
         when T_READ    => return Kind_Tread;
         when R_READ    => return Kind_Rread;
         when T_WRITE   => return Kind_Twrite;
         when R_WRITE   => return Kind_Rwrite;
         when T_CLUNK   => return Kind_Tclunk;
         when R_CLUNK   => return Kind_Rclunk;
         when T_REMOVE  => return Kind_Tremove;
         when R_REMOVE  => return Kind_Rremove;
         when T_STAT    => return Kind_Tstat;
         when R_STAT    => return Kind_Rstat;
         when T_WSTAT   => return Kind_Twstat;
         when R_WSTAT   => return Kind_Rwstat;
         when others    =>
            raise P9_Error
              with "unknown 9P message type " & Code'Image;
      end case;
   end Code_To_Kind;

   --  ── Pack ─────────────────────────────────────────────────────────────

   function Pack (Msg : Message) return Byte_Array is
      Buffer   : Byte_Array (0 .. MAX_MSG_SIZE - 1) := (others => 0);
      Position : Natural := 4;  --  reserve first 4 bytes for total-size
   begin
      Write_Byte (Buffer, Position, Kind_To_Code (Msg.Kind));
      Write_U16  (Buffer, Position, Msg.Tag);

      case Msg.Kind is

         when Kind_Tversion | Kind_Rversion =>
            Write_U32    (Buffer, Position, Msg.MSize);
            Write_String (Buffer, Position, To_String (Msg.Version));

         when Kind_Tauth =>
            Write_U32    (Buffer, Position, Msg.Auth_AFid);
            Write_String (Buffer, Position, To_String (Msg.Auth_Uname));
            Write_String (Buffer, Position, To_String (Msg.Auth_Aname));

         when Kind_Rauth =>
            Write_Qid (Buffer, Position, Msg.Auth_Aqid);

         when Kind_Tattach =>
            Write_U32    (Buffer, Position, Msg.Att_Fid);
            Write_U32    (Buffer, Position, Msg.Att_AFid);
            Write_String (Buffer, Position, To_String (Msg.Att_Uname));
            Write_String (Buffer, Position, To_String (Msg.Att_Aname));

         when Kind_Rattach =>
            Write_Qid (Buffer, Position, Msg.Att_Qid);

         when Kind_Rerror =>
            Write_String (Buffer, Position, To_String (Msg.Ename));

         when Kind_Tflush =>
            Write_U16 (Buffer, Position, Msg.Old_Tag);

         when Kind_Rflush | Kind_Rclunk | Kind_Rremove | Kind_Rwstat =>
            null;  --  no body beyond size + type + tag

         when Kind_Twalk =>
            Write_U32 (Buffer, Position, Msg.Walk_Fid);
            Write_U32 (Buffer, Position, Msg.Walk_Newfid);
            Write_U16 (Buffer, Position, Uint16 (Msg.Walk_Nwname));
            for I in 1 .. Msg.Walk_Nwname loop
               Write_String
                 (Buffer, Position, To_String (Msg.Walk_Names (I)));
            end loop;

         when Kind_Rwalk =>
            Write_U16 (Buffer, Position, Uint16 (Msg.Walk_Nwqid));
            for I in 1 .. Msg.Walk_Nwqid loop
               Write_Qid (Buffer, Position, Msg.Walk_Qids (I));
            end loop;

         when Kind_Topen =>
            Write_U32  (Buffer, Position, Msg.Open_Fid);
            Write_Byte (Buffer, Position, Msg.Open_Mode);

         when Kind_Ropen | Kind_Rcreate =>
            Write_Qid (Buffer, Position, Msg.Opened_Qid);
            Write_U32 (Buffer, Position, Msg.Opened_Iounit);

         when Kind_Tcreate =>
            Write_U32    (Buffer, Position, Msg.Cr_Fid);
            Write_String (Buffer, Position, To_String (Msg.Cr_Name));
            Write_U32    (Buffer, Position, Msg.Cr_Perm);
            Write_Byte   (Buffer, Position, Msg.Cr_Mode);

         when Kind_Tread =>
            Write_U32 (Buffer, Position, Msg.Rd_Fid);
            Write_U64 (Buffer, Position, Msg.Rd_Offset);
            Write_U32 (Buffer, Position, Msg.Rd_Count);

         when Kind_Rread =>
            declare
               Data : constant String := To_String (Msg.Rd_Data);
            begin
               Write_U32 (Buffer, Position, Uint32 (Data'Length));
               for C of Data loop
                  Buffer (Position) := Uint8 (Character'Pos (C));
                  Position := Position + 1;
               end loop;
            end;

         when Kind_Twrite =>
            declare
               Data : constant String := To_String (Msg.Wr_Data);
            begin
               Write_U32 (Buffer, Position, Msg.Wr_Fid);
               Write_U64 (Buffer, Position, Msg.Wr_Offset);
               Write_U32 (Buffer, Position, Uint32 (Data'Length));
               for C of Data loop
                  Buffer (Position) := Uint8 (Character'Pos (C));
                  Position := Position + 1;
               end loop;
            end;

         when Kind_Rwrite =>
            Write_U32 (Buffer, Position, Msg.Wr_Count);

         when Kind_Tclunk | Kind_Tremove | Kind_Tstat =>
            Write_U32 (Buffer, Position, Msg.Simple_Fid);

         when Kind_Rstat =>
            --  Rstat adds an extra u16 nstat wrapper around the packed Stat.
            declare
               Nstat_Pos  : constant Natural := Position;
               Stat_Start : constant Natural := Position + 2;
            begin
               Position := Stat_Start;
               Write_Stat (Buffer, Position, Msg.Rstat_Stat);
               declare
                  Nstat          : constant Uint16 :=
                    Uint16 (Position - Stat_Start);
                  Size_Write_Pos : Natural := Nstat_Pos;
               begin
                  Write_U16 (Buffer, Size_Write_Pos, Nstat);
               end;
            end;

         when Kind_Twstat =>
            --  Twstat: fid then u16 nstat wrapper then the packed Stat.
            Write_U32 (Buffer, Position, Msg.Wstat_Fid);
            declare
               Nstat_Pos  : constant Natural := Position;
               Stat_Start : constant Natural := Position + 2;
            begin
               Position := Stat_Start;
               Write_Stat (Buffer, Position, Msg.Wstat_Stat);
               declare
                  Nstat          : constant Uint16 :=
                    Uint16 (Position - Stat_Start);
                  Size_Write_Pos : Natural := Nstat_Pos;
               begin
                  Write_U16 (Buffer, Size_Write_Pos, Nstat);
               end;
            end;

      end case;

      --  Back-fill the total message size at bytes 0..3.
      declare
         Total          : constant Uint32 := Uint32 (Position);
         Size_Write_Pos : Natural         := 0;
      begin
         Write_U32 (Buffer, Size_Write_Pos, Total);
      end;

      return Buffer (0 .. Position - 1);
   end Pack;

   --  ── Little-endian readers ─────────────────────────────────────────────

   function Read_Byte
     (Data     : Byte_Array;
      Position : in out Natural) return Uint8
   is
      Value : constant Uint8 := Data (Position);
   begin
      Position := Position + 1;
      return Value;
   end Read_Byte;

   function Read_U16
     (Data     : Byte_Array;
      Position : in out Natural) return Uint16
   is
      Lo : constant Uint16 := Uint16 (Data (Position));
      Hi : constant Uint16 := Uint16 (Data (Position + 1));
   begin
      Position := Position + 2;
      return Lo or Shift_Left (Hi, 8);
   end Read_U16;

   function Read_U32
     (Data     : Byte_Array;
      Position : in out Natural) return Uint32
   is
      Value : Uint32 := 0;
   begin
      for I in 0 .. 3 loop
         Value := Value or Shift_Left (Uint32 (Data (Position + I)), I * 8);
      end loop;
      Position := Position + 4;
      return Value;
   end Read_U32;

   function Read_U64
     (Data     : Byte_Array;
      Position : in out Natural) return Uint64
   is
      Value : Uint64 := 0;
   begin
      for I in 0 .. 7 loop
         Value := Value or Shift_Left (Uint64 (Data (Position + I)), I * 8);
      end loop;
      Position := Position + 8;
      return Value;
   end Read_U64;

   function Read_String
     (Data     : Byte_Array;
      Position : in out Natural) return String
   is
      Length : constant Natural := Natural (Read_U16 (Data, Position));
      Result : String (1 .. Length);
   begin
      for I in Result'Range loop
         Result (I) := Character'Val (Data (Position));
         Position := Position + 1;
      end loop;
      return Result;
   end Read_String;

   function Read_Qid
     (Data     : Byte_Array;
      Position : in out Natural) return Qid
   is
   begin
      return Q : Qid do
         Q.Qtype := Read_Byte (Data, Position);
         Q.Vers  := Read_U32  (Data, Position);
         Q.Path  := Read_U64  (Data, Position);
      end return;
   end Read_Qid;

   --  Read a Stat including its leading 2-byte body-size field.
   function Read_Stat
     (Data     : Byte_Array;
      Position : in out Natural) return Stat
   is
      Body_Size : constant Uint16 := Read_U16 (Data, Position);
      pragma Unreferenced (Body_Size);
   begin
      return S : Stat do
         S.Stype  := Read_U16  (Data, Position);
         S.Dev    := Read_U32  (Data, Position);
         S.Sqid   := Read_Qid  (Data, Position);
         S.Mode   := Read_U32  (Data, Position);
         S.Atime  := Read_U32  (Data, Position);
         S.Mtime  := Read_U32  (Data, Position);
         S.Length := Read_U64  (Data, Position);
         S.Name   := To_Unbounded_String (Read_String (Data, Position));
         S.Uid    := To_Unbounded_String (Read_String (Data, Position));
         S.Gid    := To_Unbounded_String (Read_String (Data, Position));
         S.Muid   := To_Unbounded_String (Read_String (Data, Position));
      end return;
   end Read_Stat;

   --  ── Unpack ───────────────────────────────────────────────────────────

   function Unpack (Data : Byte_Array) return Message is
      Position  : Natural := Data'First;
      Size      : Uint32;
      Code      : Uint8;
      Tag       : Uint16;
      Kind      : Message_Kind;
      pragma Unreferenced (Size);
   begin
      Size := Read_U32  (Data, Position);   --  consume but don't validate
      Code := Read_Byte (Data, Position);
      Tag  := Read_U16  (Data, Position);
      Kind := Code_To_Kind (Code);

      case Kind is

         when Kind_Tversion =>
            declare
               Msize   : constant Uint32 := Read_U32    (Data, Position);
               Version : constant String := Read_String (Data, Position);
            begin
               return (Kind    => Kind_Tversion,
                       Tag     => Tag,
                       MSize   => Msize,
                       Version => To_Unbounded_String (Version));
            end;

         when Kind_Rversion =>
            declare
               Msize   : constant Uint32 := Read_U32    (Data, Position);
               Version : constant String := Read_String (Data, Position);
            begin
               return (Kind    => Kind_Rversion,
                       Tag     => Tag,
                       MSize   => Msize,
                       Version => To_Unbounded_String (Version));
            end;

         when Kind_Tauth =>
            declare
               Afid  : constant Uint32 := Read_U32    (Data, Position);
               Uname : constant String := Read_String (Data, Position);
               Aname : constant String := Read_String (Data, Position);
            begin
               return (Kind       => Kind_Tauth,
                       Tag        => Tag,
                       Auth_AFid  => Afid,
                       Auth_Uname => To_Unbounded_String (Uname),
                       Auth_Aname => To_Unbounded_String (Aname));
            end;

         when Kind_Rauth =>
            return (Kind      => Kind_Rauth,
                    Tag       => Tag,
                    Auth_Aqid => Read_Qid (Data, Position));

         when Kind_Tattach =>
            declare
               Fid   : constant Uint32 := Read_U32    (Data, Position);
               Afid  : constant Uint32 := Read_U32    (Data, Position);
               Uname : constant String := Read_String (Data, Position);
               Aname : constant String := Read_String (Data, Position);
            begin
               return (Kind      => Kind_Tattach,
                       Tag       => Tag,
                       Att_Fid   => Fid,
                       Att_AFid  => Afid,
                       Att_Uname => To_Unbounded_String (Uname),
                       Att_Aname => To_Unbounded_String (Aname));
            end;

         when Kind_Rattach =>
            return (Kind    => Kind_Rattach,
                    Tag     => Tag,
                    Att_Qid => Read_Qid (Data, Position));

         when Kind_Rerror =>
            return (Kind  => Kind_Rerror,
                    Tag   => Tag,
                    Ename =>
                      To_Unbounded_String (Read_String (Data, Position)));

         when Kind_Tflush =>
            return (Kind    => Kind_Tflush,
                    Tag     => Tag,
                    Old_Tag => Read_U16 (Data, Position));

         when Kind_Rflush  => return (Kind => Kind_Rflush,  Tag => Tag);
         when Kind_Rclunk  => return (Kind => Kind_Rclunk,  Tag => Tag);
         when Kind_Rremove => return (Kind => Kind_Rremove, Tag => Tag);
         when Kind_Rwstat  => return (Kind => Kind_Rwstat,  Tag => Tag);

         when Kind_Twalk =>
            declare
               Fid    : constant Uint32     := Read_U32 (Data, Position);
               Newfid : constant Uint32     := Read_U32 (Data, Position);
               Nwname : constant Walk_Count :=
                 Walk_Count (Read_U16 (Data, Position));
               Names  : Name_Array;
            begin
               for I in 1 .. Nwname loop
                  Names (I) :=
                    To_Unbounded_String (Read_String (Data, Position));
               end loop;
               return (Kind        => Kind_Twalk,
                       Tag         => Tag,
                       Walk_Fid    => Fid,
                       Walk_Newfid => Newfid,
                       Walk_Nwname => Nwname,
                       Walk_Names  => Names);
            end;

         when Kind_Rwalk =>
            declare
               Nwqid : constant Walk_Count :=
                 Walk_Count (Read_U16 (Data, Position));
               Qids  : Qid_Array;
            begin
               for I in 1 .. Nwqid loop
                  Qids (I) := Read_Qid (Data, Position);
               end loop;
               return (Kind       => Kind_Rwalk,
                       Tag        => Tag,
                       Walk_Nwqid => Nwqid,
                       Walk_Qids  => Qids);
            end;

         when Kind_Topen =>
            declare
               Fid  : constant Uint32 := Read_U32  (Data, Position);
               Mode : constant Uint8  := Read_Byte (Data, Position);
            begin
               return (Kind      => Kind_Topen,
                       Tag       => Tag,
                       Open_Fid  => Fid,
                       Open_Mode => Mode);
            end;

         when Kind_Ropen =>
            declare
               Q      : constant Qid    := Read_Qid (Data, Position);
               Iounit : constant Uint32 := Read_U32  (Data, Position);
            begin
               return (Kind          => Kind_Ropen,
                       Tag           => Tag,
                       Opened_Qid    => Q,
                       Opened_Iounit => Iounit);
            end;

         when Kind_Rcreate =>
            declare
               Q      : constant Qid    := Read_Qid (Data, Position);
               Iounit : constant Uint32 := Read_U32  (Data, Position);
            begin
               return (Kind          => Kind_Rcreate,
                       Tag           => Tag,
                       Opened_Qid    => Q,
                       Opened_Iounit => Iounit);
            end;

         when Kind_Tcreate =>
            declare
               Fid  : constant Uint32 := Read_U32    (Data, Position);
               Name : constant String := Read_String (Data, Position);
               Perm : constant Uint32 := Read_U32    (Data, Position);
               Mode : constant Uint8  := Read_Byte   (Data, Position);
            begin
               return (Kind    => Kind_Tcreate,
                       Tag     => Tag,
                       Cr_Fid  => Fid,
                       Cr_Name => To_Unbounded_String (Name),
                       Cr_Perm => Perm,
                       Cr_Mode => Mode);
            end;

         when Kind_Tread =>
            declare
               Fid    : constant Uint32 := Read_U32 (Data, Position);
               Offset : constant Uint64 := Read_U64 (Data, Position);
               Count  : constant Uint32 := Read_U32 (Data, Position);
            begin
               return (Kind      => Kind_Tread,
                       Tag       => Tag,
                       Rd_Fid    => Fid,
                       Rd_Offset => Offset,
                       Rd_Count  => Count);
            end;

         when Kind_Rread =>
            declare
               Count : constant Natural := Natural (Read_U32 (Data, Position));
               S     : String (1 .. Count);
            begin
               for I in S'Range loop
                  S (I) := Character'Val (Data (Position));
                  Position := Position + 1;
               end loop;
               return (Kind    => Kind_Rread,
                       Tag     => Tag,
                       Rd_Data => To_Unbounded_String (S));
            end;

         when Kind_Twrite =>
            declare
               Fid    : constant Uint32  := Read_U32 (Data, Position);
               Offset : constant Uint64  := Read_U64 (Data, Position);
               Count  : constant Natural :=
                 Natural (Read_U32 (Data, Position));
               S      : String (1 .. Count);
            begin
               for I in S'Range loop
                  S (I) := Character'Val (Data (Position));
                  Position := Position + 1;
               end loop;
               return (Kind      => Kind_Twrite,
                       Tag       => Tag,
                       Wr_Fid    => Fid,
                       Wr_Offset => Offset,
                       Wr_Data   => To_Unbounded_String (S));
            end;

         when Kind_Rwrite =>
            return (Kind     => Kind_Rwrite,
                    Tag      => Tag,
                    Wr_Count => Read_U32 (Data, Position));

         when Kind_Tclunk =>
            return (Kind       => Kind_Tclunk,
                    Tag        => Tag,
                    Simple_Fid => Read_U32 (Data, Position));

         when Kind_Tremove =>
            return (Kind       => Kind_Tremove,
                    Tag        => Tag,
                    Simple_Fid => Read_U32 (Data, Position));

         when Kind_Tstat =>
            return (Kind       => Kind_Tstat,
                    Tag        => Tag,
                    Simple_Fid => Read_U32 (Data, Position));

         when Kind_Rstat =>
            declare
               Nstat : constant Uint16 := Read_U16 (Data, Position);
               pragma Unreferenced (Nstat);
            begin
               return (Kind       => Kind_Rstat,
                       Tag        => Tag,
                       Rstat_Stat => Read_Stat (Data, Position));
            end;

         when Kind_Twstat =>
            declare
               Fid   : constant Uint32 := Read_U32 (Data, Position);
               Nstat : constant Uint16 := Read_U16 (Data, Position);
               pragma Unreferenced (Nstat);
            begin
               return (Kind       => Kind_Twstat,
                       Tag        => Tag,
                       Wstat_Fid  => Fid,
                       Wstat_Stat => Read_Stat (Data, Position));
            end;

      end case;
   end Unpack;

end Nine_P.Proto;
