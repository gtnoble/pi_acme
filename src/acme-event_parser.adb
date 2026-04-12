--  Acme.Event_Parser body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Acme.Event_Parser is

   --  ── Rc-token parser ───────────────────────────────────────────────────
   --
   --  Ported from the Python _rc_token helper in pi-acme.
   --  Reads one rc(1)-quoted token from Line starting at Position;
   --  advances Position past the token and returns the unescaped text.

   function Rc_Token
     (Line     :     String;
      Position : in out Positive) return String
   is
   begin
      if Position > Line'Last then
         return "";
      end if;

      if Line (Position) /= ''' then
         --  Unquoted token: read until whitespace or end of string.
         declare
            Start : constant Positive := Position;
         begin
            while Position <= Line'Last
              and then Line (Position) not in ' ' | ASCII.HT
            loop
               Position := Position + 1;
            end loop;
            return Line (Start .. Position - 1);
         end;
      end if;

      --  Quoted token: skip the opening quote then accumulate characters.
      Position := Position + 1;
      declare
         Result : Unbounded_String;
      begin
         while Position <= Line'Last loop
            if Line (Position) = ''' then
               if Position < Line'Last
                 and then Line (Position + 1) = '''
               then
                  --  Escaped single quote ''
                  Append (Result, ''');
                  Position := Position + 2;
               else
                  --  Closing quote
                  Position := Position + 1;
                  exit;
               end if;
            else
               Append (Result, Line (Position));
               Position := Position + 1;
            end if;
         end loop;
         return To_String (Result);
      end;
   end Rc_Token;

   --  ── Parse ─────────────────────────────────────────────────────────────

   function Parse (Line : String; Ev : out Event) return Boolean is
      Position : Positive := Line'First;

      --  Skip over horizontal whitespace.
      procedure Skip_Space is
      begin
         while Position <= Line'Last
           and then Line (Position) in ' ' | ASCII.HT
         loop
            Position := Position + 1;
         end loop;
      end Skip_Space;

      --  Read one plain (non-rc-quoted) whitespace-delimited token.
      function Plain_Token return String is
         Start : constant Positive := Position;
      begin
         while Position <= Line'Last
           and then Line (Position) not in ' ' | ASCII.HT
         loop
            Position := Position + 1;
         end loop;
         return Line (Start .. Position - 1);
      end Plain_Token;

   begin
      Ev := Event'(others => <>);

      --  Token 1: must be "event"
      Skip_Space;
      if Plain_Token /= "event" then
         return False;
      end if;

      --  Tokens 2-3: c1, c2 (single characters)
      Skip_Space;
      declare
         Token : constant String := Plain_Token;
      begin
         if Token'Length /= 1 then
            return False;
         end if;
         Ev.C1 := Token (Token'First);
      end;

      Skip_Space;
      declare
         Token : constant String := Plain_Token;
      begin
         if Token'Length /= 1 then
            return False;
         end if;
         Ev.C2 := Token (Token'First);
      end;

      --  Tokens 4-9: q0 q1 eq0 eq1 flag nr (integers)
      Skip_Space; Ev.Q0   := Natural'Value (Plain_Token);
      Skip_Space; Ev.Q1   := Natural'Value (Plain_Token);
      Skip_Space; Ev.Eq0  := Natural'Value (Plain_Token);
      Skip_Space; Ev.Eq1  := Natural'Value (Plain_Token);
      Skip_Space; Ev.Flag := Natural'Value (Plain_Token);
      Skip_Space; Ev.Nr   := Natural'Value (Plain_Token);

      --  Tokens 10-12: text, arg, origin — rc-quoted
      Skip_Space;
      Ev.Text   := To_Unbounded_String (Rc_Token (Line, Position));
      Skip_Space;
      Ev.Arg    := To_Unbounded_String (Rc_Token (Line, Position));
      Skip_Space;
      Ev.Origin := To_Unbounded_String (Rc_Token (Line, Position));

      return True;

   exception
      when Constraint_Error =>
         return False;
   end Parse;

end Acme.Event_Parser;
