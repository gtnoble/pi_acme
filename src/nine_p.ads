--  Nine_P — root package
--
--  Constants, primitive integer types, Qid, and the Byte_Array wire type
--  for the 9P2000 protocol.  All subpackages (Proto, Client, …) are child
--  packages of this one and inherit these declarations automatically.
--
--  Reference: http://man.cat-v.org/plan_9/5/intro
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Containers.Vectors;
with Interfaces;

package Nine_P is

   --  ── Integer subtypes ──────────────────────────────────────────────────

   subtype Uint8  is Interfaces.Unsigned_8;
   subtype Uint16 is Interfaces.Unsigned_16;
   subtype Uint32 is Interfaces.Unsigned_32;
   subtype Uint64 is Interfaces.Unsigned_64;

   --  ── Message type codes ────────────────────────────────────────────────

   T_VERSION : constant Uint8 := 100;
   R_VERSION : constant Uint8 := 101;
   T_AUTH    : constant Uint8 := 102;
   R_AUTH    : constant Uint8 := 103;
   T_ATTACH  : constant Uint8 := 104;
   R_ATTACH  : constant Uint8 := 105;
   R_ERROR   : constant Uint8 := 107;
   T_FLUSH   : constant Uint8 := 108;
   R_FLUSH   : constant Uint8 := 109;
   T_WALK    : constant Uint8 := 110;
   R_WALK    : constant Uint8 := 111;
   T_OPEN    : constant Uint8 := 112;
   R_OPEN    : constant Uint8 := 113;
   T_CREATE  : constant Uint8 := 114;
   R_CREATE  : constant Uint8 := 115;
   T_READ    : constant Uint8 := 116;
   R_READ    : constant Uint8 := 117;
   T_WRITE   : constant Uint8 := 118;
   R_WRITE   : constant Uint8 := 119;
   T_CLUNK   : constant Uint8 := 120;
   R_CLUNK   : constant Uint8 := 121;
   T_REMOVE  : constant Uint8 := 122;
   R_REMOVE  : constant Uint8 := 123;
   T_STAT    : constant Uint8 := 124;
   R_STAT    : constant Uint8 := 125;
   T_WSTAT   : constant Uint8 := 126;
   R_WSTAT   : constant Uint8 := 127;

   --  ── Special values ────────────────────────────────────────────────────

   VERSION_9P : constant String := "9P2000";
   NO_TAG     : constant Uint16 := 16#FFFF#;
   NO_FID     : constant Uint32 := 16#FFFF_FFFF#;
   MAX_WELEM  : constant        := 16;

   --  ── Open mode bits ───────────────────────────────────────────────────

   O_READ   : constant Uint8 := 0;
   O_WRITE  : constant Uint8 := 1;
   O_RDWR   : constant Uint8 := 2;
   O_EXEC   : constant Uint8 := 3;
   O_TRUNC  : constant Uint8 := 16;
   O_CEXEC  : constant Uint8 := 32;
   O_RCLOSE : constant Uint8 := 64;

   --  ── Qid type bits ────────────────────────────────────────────────────

   QT_DIR    : constant Uint8 := 16#80#;
   QT_APPEND : constant Uint8 := 16#40#;
   QT_EXCL   : constant Uint8 := 16#20#;
   QT_AUTH   : constant Uint8 := 16#08#;
   QT_TMP    : constant Uint8 := 16#04#;
   QT_FILE   : constant Uint8 := 16#00#;

   --  ── Stat mode bits ───────────────────────────────────────────────────

   DM_DIR    : constant Uint32 := 16#8000_0000#;
   DM_APPEND : constant Uint32 := 16#4000_0000#;
   DM_EXCL   : constant Uint32 := 16#2000_0000#;
   DM_AUTH   : constant Uint32 := 16#0800_0000#;
   DM_TMP    : constant Uint32 := 16#0400_0000#;

   --  ── Wstat sentinels ──────────────────────────────────────────────────

   NO_CHANGE    : constant Uint32 := 16#FFFF_FFFF#;
   NO_CHANGE_64 : constant Uint64 := 16#FFFF_FFFF_FFFF_FFFF#;

   --  ── Qid ──────────────────────────────────────────────────────────────
   --
   --  Server-unique file identifier; 13 bytes on the wire:
   --    1 byte  qtype
   --    4 bytes vers  (little-endian)
   --    8 bytes path  (little-endian)

   type Qid is record
      Qtype : Uint8  := QT_FILE;
      Vers  : Uint32 := 0;
      Path  : Uint64 := 0;
   end record;

   QID_WIRE_SIZE : constant := 13;

   --  ── Raw byte array ───────────────────────────────────────────────────
   --
   --  Used for wire encoding/decoding throughout the protocol stack.

   type Byte_Array is array (Natural range <>) of Uint8;

   --  ── Byte_Vectors ─────────────────────────────────────────────────────
   --
   --  Automatically-managed growable byte sequence.  Use this for
   --  accumulating data of unknown length (e.g. File.Read results)
   --  instead of manual array concatenation.

   use type Interfaces.Unsigned_8;

   package Byte_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Uint8);

end Nine_P;
