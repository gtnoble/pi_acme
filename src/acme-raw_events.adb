--  Acme.Raw_Events body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Nine_P;                use Nine_P;

package body Acme.Raw_Events is

   --  ── Helpers ───────────────────────────────────────────────────────────

   --  Read a run of decimal digits terminated by a single space.
   --  Returns True and advances Position past the space on success.
   function Read_Number
     (Text     :     String;
      Position : in out Positive;
      Value    :    out Natural) return Boolean
   is
   begin
      Value := 0;
      while Position <= Text'Last
        and then Text (Position) in '0' .. '9'
      loop
         Value :=
           Value * 10
           + (Character'Pos (Text (Position)) - Character'Pos ('0'));
         Position := Position + 1;
      end loop;
      if Position > Text'Last or else Text (Position) /= ' ' then
         return False;
      end if;
      Position := Position + 1;    --  consume the terminating space
      return True;
   end Read_Number;

   --  Return the byte-length of the UTF-8 rune whose first byte is at
   --  Text (Position).  Mirrors plan9port's fullrune / chartorune logic.
   function Rune_Byte_Length
     (Text     : String;
      Position : Positive) return Natural
   is
      Byte_Value : constant Natural :=
        Character'Pos (Text (Position));
   begin
      if Byte_Value < 16#80# then
         return 1;
      elsif Byte_Value < 16#E0# then
         return 2;
      elsif Byte_Value < 16#F0# then
         return 3;
      else
         return 4;
      end if;
   end Rune_Byte_Length;

   --  Parse exactly one wire event from Text starting at Position.
   --  Advances Position past the trailing LF on success; returns False
   --  if the buffer is incomplete without modifying Position.
   function Parse_One_Wire
     (Text     :     String;
      Position : in out Positive;
      C1       :    out Character;
      C2       :    out Character;
      Q0       :    out Natural;
      Q1       :    out Natural;
      Flag     :    out Natural;
      Nr       :    out Natural;
      Chars    :    out Unbounded_String) return Boolean
   is
      Current : Positive := Position;
   begin
      C1 := ' '; C2 := ' '; Q0 := 0; Q1 := 0;
      Flag := 0; Nr := 0;
      Chars := Null_Unbounded_String;

      --  Two character-class bytes
      if Current + 1 > Text'Last then
         return False;
      end if;
      C1 := Text (Current); Current := Current + 1;
      C2 := Text (Current); Current := Current + 1;

      --  Four decimal numbers, each terminated by a space
      if not Read_Number (Text, Current, Q0) then
         return False;
      end if;
      if not Read_Number (Text, Current, Q1) then
         return False;
      end if;
      if not Read_Number (Text, Current, Flag) then
         return False;
      end if;
      if not Read_Number (Text, Current, Nr) then
         return False;
      end if;

      --  Nr UTF-8 runes
      for I in 1 .. Nr loop
         if Current > Text'Last then
            return False;
         end if;
         declare
            Rune_Length : constant Natural :=
              Rune_Byte_Length (Text, Current);
         begin
            if Current + Rune_Length - 1 > Text'Last then
               return False;
            end if;
            for J in 0 .. Rune_Length - 1 loop
               Append (Chars, Text (Current + J));
            end loop;
            Current := Current + Rune_Length;
         end;
      end loop;

      --  Trailing LF
      if Current > Text'Last or else Text (Current) /= ASCII.LF then
         return False;
      end if;
      Position := Current + 1;    --  commit only on full success
      return True;
   end Parse_One_Wire;

   --  ── Feed ──────────────────────────────────────────────────────────────

   procedure Feed
     (Parser : in out Event_Parser;
      Data   :     Byte_Array)
   is
   begin
      for B of Data loop
         Append (Parser.Buffer, Character'Val (B));
      end loop;
   end Feed;

   --  ── Next_Event ────────────────────────────────────────────────────────

   function Next_Event
     (Parser : in out Event_Parser;
      Ev     : out    Acme.Event_Parser.Event) return Boolean
   is
      Buffer_String : constant String  := To_String (Parser.Buffer);
      Position      : Positive         := 1;

      C1, C2   : Character;
      Q0, Q1   : Natural;
      Flag, Nr : Natural;
      Chars    : Unbounded_String;

   begin
      Ev := Acme.Event_Parser.Event'(others => <>);

      if Buffer_String'Length = 0 then
         return False;
      end if;

      --  ── Main event ────────────────────────────────────────────────────
      if not Parse_One_Wire
           (Buffer_String, Position, C1, C2, Q0, Q1, Flag, Nr, Chars)
      then
         return False;
      end if;

      Ev.C1   := C1;    Ev.C2  := C2;
      Ev.Q0   := Q0;    Ev.Q1  := Q1;
      Ev.Eq0  := Q0;    Ev.Eq1 := Q1;   --  default: same as Q0/Q1
      Ev.Flag := Flag;  Ev.Nr  := Nr;
      Ev.Text := Chars;

      --  ── Flag & 2: expansion event ─────────────────────────────────────
      --  A zero-rune main event is followed by an event with the actual
      --  expanded text and updated eq0/eq1 positions.
      if (Flag mod 4) >= 2 then
         declare
            XC1, XC2   : Character;
            XQ0, XQ1   : Natural;
            XFlag, XNr : Natural;
            XChars     : Unbounded_String;
         begin
            if not Parse_One_Wire
                 (Buffer_String, Position,
                  XC1, XC2, XQ0, XQ1, XFlag, XNr, XChars)
            then
               return False;
            end if;
            Ev.Eq0  := XQ0;
            Ev.Eq1  := XQ1;
            Ev.Text := XChars;    --  expanded text replaces empty main
         end;
      end if;

      --  ── Flag & 8: chorded arg + origin events ─────────────────────────
      if (Flag mod 16) >= 8 then
         declare
            XC1, XC2   : Character;
            XQ0, XQ1   : Natural;
            XFlag, XNr : Natural;
         begin
            if not Parse_One_Wire
                 (Buffer_String, Position,
                  XC1, XC2, XQ0, XQ1, XFlag, XNr, Ev.Arg)
            then
               return False;
            end if;
            if not Parse_One_Wire
                 (Buffer_String, Position,
                  XC1, XC2, XQ0, XQ1, XFlag, XNr, Ev.Origin)
            then
               return False;
            end if;
         end;
      end if;

      --  Consume the bytes we just parsed from the front of the buffer.
      Parser.Buffer :=
        To_Unbounded_String
          (Buffer_String (Position .. Buffer_String'Last));
      return True;
   end Next_Event;

end Acme.Raw_Events;
