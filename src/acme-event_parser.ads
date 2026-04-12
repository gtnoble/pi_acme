--  Acme.Event_Parser — parse one line of acmeevent(1) output.
--
--  acmeevent reads the raw acme event file and reformats each event as:
--
--    event <c1> <c2> <q0> <q1> <eq0> <eq1> <flag> <nr> <text> <arg> <origin>
--
--  where text, arg and origin are rc(1)-style quoted strings:
--  a bare word if no embedded spaces or quotes, otherwise enclosed in
--  single quotes with '' representing a literal single quote.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded;

package Acme.Event_Parser is

   type Event is record
      C1     : Character                          := ' ';
      --  origin: M=mouse K=keyboard …
      C2     : Character                          := ' ';
      --  action: x/X=execute l/L=look
      Q0     : Natural                            := 0;
      --  selection start (runes)
      Q1     : Natural                            := 0;
      --  selection end
      Eq0    : Natural                            := 0;
      --  expanded start
      Eq1    : Natural                            := 0;
      --  expanded end
      Flag   : Natural                            := 0;
      Nr     : Natural                            := 0;
      --  rune count of Text
      Text   : Ada.Strings.Unbounded.Unbounded_String;
      Arg    : Ada.Strings.Unbounded.Unbounded_String;
      Origin : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse one line of acmeevent output into Ev.
   --  Returns True on success; False for blank or unrecognised lines.
   function Parse (Line : String; Ev : out Event) return Boolean;

end Acme.Event_Parser;
