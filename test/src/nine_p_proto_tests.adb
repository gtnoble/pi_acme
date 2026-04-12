with AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;             use Interfaces;
with Nine_P;                 use Nine_P;
with Nine_P.Proto;           use Nine_P.Proto;

package body Nine_P_Proto_Tests is

   use AUnit.Assertions;

   --  ── Helpers ───────────────────────────────────────────────────────────

   --  Round-trip a message through Pack then Unpack and return the result.
   function RT (Msg : Message) return Message is
   begin
      return Unpack (Pack (Msg));
   end RT;

   --  ── Qid round-trip ────────────────────────────────────────────────────

   procedure Test_Qid_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Q    : constant Qid     :=
        (Qtype => QT_DIR, Vers => 42, Path => 16#DEAD_BEEF#);
      Orig : constant Message :=
        (Kind => Kind_Rattach, Tag => 5, Att_Qid => Q);
      Got  : constant Message := RT (Orig);
   begin
      Assert (Got.Kind           = Kind_Rattach, "Kind mismatch");
      Assert (Got.Tag            = 5,            "Tag mismatch");
      Assert (Got.Att_Qid.Qtype = QT_DIR,       "Qid.Qtype mismatch");
      Assert (Got.Att_Qid.Vers  = 42,            "Qid.Vers mismatch");
      Assert (Got.Att_Qid.Path  = 16#DEAD_BEEF#, "Qid.Path mismatch");
   end Test_Qid_Round_Trip;

   --  ── Stat round-trip ───────────────────────────────────────────────────

   procedure Test_Stat_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      S : constant Stat :=
        (Stype  => 16,
         Dev    => 7,
         Sqid   => (Qtype => QT_FILE, Vers => 3, Path => 99),
         Mode   => 8#755#,
         Atime  => 1000,
         Mtime  => 2000,
         Length => 42,
         Name   => To_Unbounded_String ("hello"),
         Uid    => To_Unbounded_String ("user"),
         Gid    => To_Unbounded_String ("group"),
         Muid   => To_Unbounded_String ("muid"));
      Orig : constant Message :=
        (Kind => Kind_Rstat, Tag => 7, Rstat_Stat => S);
      Got  : constant Message := RT (Orig);
      GS   : Stat renames Got.Rstat_Stat;
   begin
      Assert (Got.Kind            = Kind_Rstat,   "Kind mismatch");
      Assert (GS.Stype            = 16,           "Stat.Stype mismatch");
      Assert (GS.Dev              = 7,            "Stat.Dev mismatch");
      Assert (GS.Sqid.Path        = 99,           "Stat.Sqid.Path mismatch");
      Assert (GS.Mode             = 8#755#,       "Stat.Mode mismatch");
      Assert (GS.Length           = 42,           "Stat.Length mismatch");
      Assert (To_String (GS.Name) = "hello",      "Stat.Name mismatch");
      Assert (To_String (GS.Uid)  = "user",       "Stat.Uid mismatch");
      Assert (To_String (GS.Gid)  = "group",      "Stat.Gid mismatch");
      Assert (To_String (GS.Muid) = "muid",       "Stat.Muid mismatch");
   end Test_Stat_Round_Trip;

   --  ── Individual message round-trips ────────────────────────────────────

   procedure Test_Tversion_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind    => Kind_Tversion,
         Tag     => NO_TAG,
         MSize   => 8192,
         Version => To_Unbounded_String (VERSION_9P));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind                = Kind_Tversion, "Kind mismatch");
      Assert (Got.MSize               = 8192,          "MSize mismatch");
      Assert (To_String (Got.Version) = VERSION_9P,    "Version mismatch");
   end Test_Tversion_Round_Trip;

   procedure Test_Rversion_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind    => Kind_Rversion,
         Tag     => NO_TAG,
         MSize   => 4096,
         Version => To_Unbounded_String (VERSION_9P));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind  = Kind_Rversion, "Kind mismatch");
      Assert (Got.MSize = 4096,          "MSize mismatch");
   end Test_Rversion_Round_Trip;

   procedure Test_Tattach_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind      => Kind_Tattach,
         Tag       => 1,
         Att_Fid   => 10,
         Att_AFid  => NO_FID,
         Att_Uname => To_Unbounded_String ("alice"),
         Att_Aname => To_Unbounded_String (""));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind                  = Kind_Tattach, "Kind mismatch");
      Assert (Got.Att_Fid               = 10,           "Fid mismatch");
      Assert (Got.Att_AFid              = NO_FID,       "AFid mismatch");
      Assert (To_String (Got.Att_Uname) = "alice",      "Uname mismatch");
      Assert (To_String (Got.Att_Aname) = "",           "Aname mismatch");
   end Test_Tattach_Round_Trip;

   procedure Test_Rattach_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Q    : constant Qid     :=
        (Qtype => QT_DIR, Vers => 0, Path => 1);
      Orig : constant Message :=
        (Kind => Kind_Rattach, Tag => 1, Att_Qid => Q);
      Got  : constant Message := RT (Orig);
   begin
      Assert (Got.Kind         = Kind_Rattach, "Kind mismatch");
      Assert (Got.Att_Qid.Path = 1,            "Qid.Path mismatch");
   end Test_Rattach_Round_Trip;

   procedure Test_Rerror_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind  => Kind_Rerror,
         Tag   => 2,
         Ename => To_Unbounded_String ("no such file"));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind              = Kind_Rerror,    "Kind mismatch");
      Assert (To_String (Got.Ename) = "no such file", "Ename mismatch");
   end Test_Rerror_Round_Trip;

   procedure Test_Twalk_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Names : Name_Array;
      Orig  : Message (Kind_Twalk);
   begin
      Names (1) := To_Unbounded_String ("usr");
      Names (2) := To_Unbounded_String ("glenda");
      Orig := (Kind        => Kind_Twalk,
               Tag         => 3,
               Walk_Fid    => 1,
               Walk_Newfid => 2,
               Walk_Nwname => 2,
               Walk_Names  => Names);
      declare
         Got : constant Message := RT (Orig);
      begin
         Assert (Got.Kind        = Kind_Twalk,  "Kind mismatch");
         Assert (Got.Walk_Fid    = 1,           "Fid mismatch");
         Assert (Got.Walk_Newfid = 2,           "Newfid mismatch");
         Assert (Got.Walk_Nwname = 2,           "Nwname mismatch");
         Assert (To_String (Got.Walk_Names (1)) = "usr",
                 "Names(1) mismatch");
         Assert (To_String (Got.Walk_Names (2)) = "glenda",
                 "Names(2) mismatch");
      end;
   end Test_Twalk_Round_Trip;

   procedure Test_Rwalk_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Qids : Qid_Array;
      Orig : Message (Kind_Rwalk);
   begin
      Qids (1) := (Qtype => QT_DIR,  Vers => 1, Path => 10);
      Qids (2) := (Qtype => QT_FILE, Vers => 2, Path => 20);
      Orig := (Kind       => Kind_Rwalk,
               Tag        => 3,
               Walk_Nwqid => 2,
               Walk_Qids  => Qids);
      declare
         Got : constant Message := RT (Orig);
      begin
         Assert (Got.Kind              = Kind_Rwalk, "Kind mismatch");
         Assert (Got.Walk_Nwqid        = 2,          "Nwqid mismatch");
         Assert (Got.Walk_Qids (1).Path = 10,        "Qids(1).Path mismatch");
         Assert (Got.Walk_Qids (2).Path = 20,        "Qids(2).Path mismatch");
      end;
   end Test_Rwalk_Round_Trip;

   procedure Test_Topen_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind      => Kind_Topen,
         Tag       => 4,
         Open_Fid  => 7,
         Open_Mode => O_RDWR);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind      = Kind_Topen, "Kind mismatch");
      Assert (Got.Open_Fid  = 7,          "Fid mismatch");
      Assert (Got.Open_Mode = O_RDWR,     "Mode mismatch");
   end Test_Topen_Round_Trip;

   procedure Test_Ropen_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Q    : constant Qid     :=
        (Qtype => QT_FILE, Vers => 0, Path => 55);
      Orig : constant Message :=
        (Kind          => Kind_Ropen,
         Tag           => 4,
         Opened_Qid    => Q,
         Opened_Iounit => 8192);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind            = Kind_Ropen, "Kind mismatch");
      Assert (Got.Opened_Qid.Path = 55,         "Qid.Path mismatch");
      Assert (Got.Opened_Iounit   = 8192,       "Iounit mismatch");
   end Test_Ropen_Round_Trip;

   procedure Test_Tread_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind      => Kind_Tread,
         Tag       => 5,
         Rd_Fid    => 3,
         Rd_Offset => 16#1_0000_0000#,
         Rd_Count  => 512);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind      = Kind_Tread,        "Kind mismatch");
      Assert (Got.Rd_Fid    = 3,                 "Fid mismatch");
      Assert (Got.Rd_Offset = 16#1_0000_0000#,   "Offset mismatch");
      Assert (Got.Rd_Count  = 512,               "Count mismatch");
   end Test_Tread_Round_Trip;

   procedure Test_Rread_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind    => Kind_Rread,
         Tag     => 5,
         Rd_Data => To_Unbounded_String ("hello world"));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind                = Kind_Rread,    "Kind mismatch");
      Assert (To_String (Got.Rd_Data) = "hello world", "Data mismatch");
   end Test_Rread_Round_Trip;

   procedure Test_Twrite_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind      => Kind_Twrite,
         Tag       => 6,
         Wr_Fid    => 4,
         Wr_Offset => 0,
         Wr_Data   => To_Unbounded_String ("write me"));
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind                = Kind_Twrite,  "Kind mismatch");
      Assert (Got.Wr_Fid              = 4,            "Fid mismatch");
      Assert (To_String (Got.Wr_Data) = "write me",   "Data mismatch");
   end Test_Twrite_Round_Trip;

   procedure Test_Rwrite_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind => Kind_Rwrite, Tag => 6, Wr_Count => 8);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind     = Kind_Rwrite, "Kind mismatch");
      Assert (Got.Wr_Count = 8,           "Count mismatch");
   end Test_Rwrite_Round_Trip;

   procedure Test_Tclunk_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      Orig : constant Message :=
        (Kind => Kind_Tclunk, Tag => 7, Simple_Fid => 99);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind       = Kind_Tclunk, "Kind mismatch");
      Assert (Got.Simple_Fid = 99,          "Fid mismatch");
   end Test_Tclunk_Round_Trip;

   procedure Test_Stat_Message_Round_Trip (T : in out Test) is
      pragma Unreferenced (T);
      --  Tstat round-trip (just carries a fid like Tclunk)
      Orig : constant Message :=
        (Kind => Kind_Tstat, Tag => 8, Simple_Fid => 12);
      Got : constant Message := RT (Orig);
   begin
      Assert (Got.Kind       = Kind_Tstat, "Kind mismatch");
      Assert (Got.Simple_Fid = 12,         "Fid mismatch");
   end Test_Stat_Message_Round_Trip;

   --  ── Wire-format correctness ───────────────────────────────────────────

   procedure Test_Message_Size (T : in out Test) is
      pragma Unreferenced (T);
      --  Rflush: size(4) + type(1) + tag(2) = 7 bytes total
      Orig : constant Message := (Kind => Kind_Rflush, Tag => 1);
      Data : constant Byte_Array := Pack (Orig);
   begin
      Assert (Data'Length = 7, "Rflush should be exactly 7 bytes");
      --  The first 4 bytes are the little-endian total size.
      Assert (Data (0) = 7, "Size field byte 0 should be 7");
      Assert (Data (1) = 0, "Size field byte 1 should be 0");
      Assert (Data (2) = 0, "Size field byte 2 should be 0");
      Assert (Data (3) = 0, "Size field byte 3 should be 0");
      --  Byte 4 is the message type code for Rflush = 109.
      Assert (Data (4) = R_FLUSH,
              "Type byte should be R_FLUSH (109)");
   end Test_Message_Size;

   procedure Test_Little_Endian (T : in out Test) is
      pragma Unreferenced (T);
      --  Tread with a known 64-bit offset:  0x01_02_03_04_05_06_07_08
      --  On the wire the bytes should appear in little-endian order:
      --    08 07 06 05 04 03 02 01
      --  Layout: size(4) + type(1) + tag(2) + fid(4) = byte 11 for offset.
      Orig : constant Message :=
        (Kind      => Kind_Tread,
         Tag       => 0,
         Rd_Fid    => 0,
         Rd_Offset => 16#01_02_03_04_05_06_07_08#,
         Rd_Count  => 0);
      Data     : constant Byte_Array := Pack (Orig);
      Off_Base : constant Natural    := 4 + 1 + 2 + 4;  --  = 11
   begin
      Assert (Data (Off_Base)     = 16#08#, "Offset byte 0 should be 16#08#");
      Assert (Data (Off_Base + 1) = 16#07#, "Offset byte 1 should be 16#07#");
      Assert (Data (Off_Base + 2) = 16#06#, "Offset byte 2 should be 16#06#");
      Assert (Data (Off_Base + 3) = 16#05#, "Offset byte 3 should be 16#05#");
      Assert (Data (Off_Base + 4) = 16#04#, "Offset byte 4 should be 16#04#");
      Assert (Data (Off_Base + 5) = 16#03#, "Offset byte 5 should be 16#03#");
      Assert (Data (Off_Base + 6) = 16#02#, "Offset byte 6 should be 16#02#");
      Assert (Data (Off_Base + 7) = 16#01#, "Offset byte 7 should be 16#01#");
   end Test_Little_Endian;

   procedure Test_String_Encoding (T : in out Test) is
      pragma Unreferenced (T);
      --  Rerror with ename = "hello"
      --  Layout: size(4) + type(1) + tag(2) = 7 bytes;
      --  then 2-byte length + chars.
      Orig : constant Message :=
        (Kind  => Kind_Rerror,
         Tag   => 1,
         Ename => To_Unbounded_String ("hello"));
      Data     : constant Byte_Array := Pack (Orig);
      Str_Base : constant Natural    := 4 + 1 + 2;  --  = 7
   begin
      --  Length field: 5 in little-endian
      Assert (Data (Str_Base)     = 5,
              "Length byte 0 should be 5");
      Assert (Data (Str_Base + 1) = 0,
              "Length byte 1 should be 0");
      --  Character bytes
      Assert (Data (Str_Base + 2) = Character'Pos ('h'), "'h' mismatch");
      Assert (Data (Str_Base + 3) = Character'Pos ('e'), "'e' mismatch");
      Assert (Data (Str_Base + 4) = Character'Pos ('l'), "'l' mismatch");
      Assert (Data (Str_Base + 5) = Character'Pos ('l'), "'l' mismatch");
      Assert (Data (Str_Base + 6) = Character'Pos ('o'), "'o' mismatch");
   end Test_String_Encoding;

end Nine_P_Proto_Tests;
