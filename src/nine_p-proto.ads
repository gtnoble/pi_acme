--  Nine_P.Proto — 9P2000 wire protocol: message encoding and decoding.
--
--  Provides:
--    * Stat        — file metadata record (variable-length string fields)
--    * Message     — discriminated record covering every 9P message type
--    * Pack        — encode a Message to a Byte_Array (little-endian)
--    * Unpack      — decode a Byte_Array to a Message
--    * P9_Error    — raised on protocol violations during Unpack
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded;

package Nine_P.Proto is

   P9_Error : exception;

   --  ── Walk helpers ─────────────────────────────────────────────────────

   subtype Walk_Count is Natural range 0 .. MAX_WELEM;

   type Name_Array is
     array (1 .. MAX_WELEM) of Ada.Strings.Unbounded.Unbounded_String;
   type Qid_Array is array (1 .. MAX_WELEM) of Qid;

   --  ── Stat ─────────────────────────────────────────────────────────────
   --
   --  Wire layout (inside the 2-byte leading body-size field):
   --    u16 type | u32 dev | Qid(13) | u32 mode | u32 atime | u32 mtime
   --    u64 length | str name | str uid | str gid | str muid
   --  where each str is u16-length-prefixed UTF-8.

   type Stat is record
      Stype  : Uint16 := 0;
      Dev    : Uint32 := 0;
      Sqid   : Qid;
      Mode   : Uint32 := 0;
      Atime  : Uint32 := 0;
      Mtime  : Uint32 := 0;
      Length : Uint64 := 0;
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Uid    : Ada.Strings.Unbounded.Unbounded_String;
      Gid    : Ada.Strings.Unbounded.Unbounded_String;
      Muid   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  ── Message_Kind ─────────────────────────────────────────────────────

   type Message_Kind is (
      Kind_Tversion, Kind_Rversion,
      Kind_Tauth,    Kind_Rauth,
      Kind_Tattach,  Kind_Rattach,
      Kind_Rerror,
      Kind_Tflush,   Kind_Rflush,
      Kind_Twalk,    Kind_Rwalk,
      Kind_Topen,    Kind_Ropen,
      Kind_Tcreate,  Kind_Rcreate,
      Kind_Tread,    Kind_Rread,
      Kind_Twrite,   Kind_Rwrite,
      Kind_Tclunk,   Kind_Rclunk,
      Kind_Tremove,  Kind_Rremove,
      Kind_Tstat,    Kind_Rstat,
      Kind_Twstat,   Kind_Rwstat
   );

   --  ── Message ──────────────────────────────────────────────────────────
   --
   --  Discriminated record: the Kind discriminant selects the variant.
   --  The Tag field is common to every message.
   --
   --  Field-name prefixes are required because Ada demands unique names
   --  across all variants of a record:
   --    Auth_*   — Tauth / Rauth fields
   --    Att_*    — Tattach / Rattach fields
   --    Walk_*   — Twalk / Rwalk fields
   --    Open_*   — Topen fields
   --    Opened_* — Ropen / Rcreate fields
   --    Cr_*     — Tcreate fields
   --    Rd_*     — Tread / Rread fields
   --    Wr_*     — Twrite / Rwrite fields

   type Message (Kind : Message_Kind) is record
      Tag : Uint16 := NO_TAG;
      case Kind is

         when Kind_Tversion | Kind_Rversion =>
            MSize   : Uint32 := 0;
            Version : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Tauth =>
            Auth_AFid  : Uint32 := NO_FID;
            Auth_Uname : Ada.Strings.Unbounded.Unbounded_String;
            Auth_Aname : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Rauth =>
            Auth_Aqid : Qid;

         when Kind_Tattach =>
            Att_Fid   : Uint32 := 0;
            Att_AFid  : Uint32 := NO_FID;
            Att_Uname : Ada.Strings.Unbounded.Unbounded_String;
            Att_Aname : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Rattach =>
            Att_Qid : Qid;

         when Kind_Rerror =>
            Ename : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Tflush =>
            Old_Tag : Uint16 := NO_TAG;

         --  No-body responses — nothing beyond Tag
         when Kind_Rflush | Kind_Rclunk | Kind_Rremove | Kind_Rwstat =>
            null;

         when Kind_Twalk =>
            Walk_Fid    : Uint32     := 0;
            Walk_Newfid : Uint32     := 0;
            Walk_Nwname : Walk_Count := 0;
            Walk_Names  : Name_Array;

         when Kind_Rwalk =>
            Walk_Nwqid : Walk_Count := 0;
            Walk_Qids  : Qid_Array;

         when Kind_Topen =>
            Open_Fid  : Uint32 := 0;
            Open_Mode : Uint8  := O_READ;

         --  Ropen and Rcreate have identical wire bodies
         when Kind_Ropen | Kind_Rcreate =>
            Opened_Qid    : Qid;
            Opened_Iounit : Uint32 := 0;

         when Kind_Tcreate =>
            Cr_Fid  : Uint32 := 0;
            Cr_Name : Ada.Strings.Unbounded.Unbounded_String;
            Cr_Perm : Uint32 := 0;
            Cr_Mode : Uint8  := O_READ;

         when Kind_Tread =>
            Rd_Fid    : Uint32 := 0;
            Rd_Offset : Uint64 := 0;
            Rd_Count  : Uint32 := 0;

         when Kind_Rread =>
            --  Raw bytes stored as a String (each Character is one octet)
            Rd_Data : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Twrite =>
            Wr_Fid    : Uint32 := 0;
            Wr_Offset : Uint64 := 0;
            Wr_Data   : Ada.Strings.Unbounded.Unbounded_String;

         when Kind_Rwrite =>
            Wr_Count : Uint32 := 0;

         --  Tclunk, Tremove, and Tstat all carry only a fid
         when Kind_Tclunk | Kind_Tremove | Kind_Tstat =>
            Simple_Fid : Uint32 := 0;

         when Kind_Rstat =>
            Rstat_Stat : Stat;

         when Kind_Twstat =>
            Wstat_Fid  : Uint32 := 0;
            Wstat_Stat : Stat;

      end case;
   end record;

   --  ── Pack / Unpack ────────────────────────────────────────────────────

   --  Encode Msg to its 9P2000 wire representation.
   --  The returned array is indexed from 0 and begins with the 4-byte
   --  little-endian total-message-size field.
   function Pack (Msg : Message) return Byte_Array;

   --  Decode one complete 9P2000 message from Data.
   --  Raises P9_Error if the message type byte is unrecognised.
   function Unpack (Data : Byte_Array) return Message;

end Nine_P.Proto;
