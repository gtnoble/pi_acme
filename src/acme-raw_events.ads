--  Acme.Raw_Events — parse the raw acme event-file wire format.
--
--  The acme event file emits events in a compact binary-ish format
--  (see /usr/local/plan9/src/cmd/acmeevent.c for the reference decoder):
--
--    c1 c2 q0 SP q1 SP flag SP nr SP <nr UTF-8 runes> LF
--
--  Two optional follow-on events handle acme's expansion flags:
--    flag & 2  →  a second event carries the expanded text/position
--    flag & 8  →  two more events carry the chorded argument and origin
--
--  Feed raw bytes from the event file with Feed; call Next_Event in a
--  loop to extract complete, fully-expanded Acme.Event_Parser.Event
--  records without requiring the external acmeevent(1) program.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Acme.Event_Parser;
with Ada.Strings.Unbounded;
with Nine_P;

package Acme.Raw_Events is

   type Event_Parser is limited private;

   --  Append raw bytes read from the acme event file.
   procedure Feed
     (Parser : in out Event_Parser;
      Data   :     Nine_P.Byte_Array);

   --  Extract the next fully-expanded event from the buffer.
   --  Returns True and populates Ev when a complete event (including any
   --  flag-2/flag-8 follow-on events) is available.
   --  Returns False when more bytes are needed.
   function Next_Event
     (Parser : in out Event_Parser;
      Ev     : out    Acme.Event_Parser.Event) return Boolean;

private

   use Ada.Strings.Unbounded;

   type Event_Parser is limited record
      --  Unbounded_String is a controlled container — no manual memory mgmt.
      Buffer : Unbounded_String;
   end record;

end Acme.Raw_Events;
