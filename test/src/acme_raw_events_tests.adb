with AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Nine_P;                use Nine_P;
with Acme.Event_Parser;
with Acme.Raw_Events;       use Acme.Raw_Events;

package body Acme_Raw_Events_Tests is

   use AUnit.Assertions;

   --  ── Helper: convert a literal string to a Byte_Array ────────────────

   function Bytes (S : String) return Byte_Array is
      BA : Byte_Array (0 .. S'Length - 1);
   begin
      for I in S'Range loop
         BA (I - S'First) := Uint8 (Character'Pos (S (I)));
      end loop;
      return BA;
   end Bytes;

   --  ── Simple events ─────────────────────────────────────────────────────

   procedure Test_Simple_Execute (T : in out Test) is
      pragma Unreferenced (T);
      --  "MX10 14 0 4 Send\n"
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("MX10 14 0 4 Send" & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse one event");
      Assert (Ev.C1 = 'M',                      "C1 = M");
      Assert (Ev.C2 = 'X',                      "C2 = X");
      Assert (Ev.Q0 = 10,                        "Q0 = 10");
      Assert (Ev.Q1 = 14,                        "Q1 = 14");
      Assert (Ev.Eq0 = 10,                       "Eq0 = Q0 (no expansion)");
      Assert (Ev.Eq1 = 14,                       "Eq1 = Q1 (no expansion)");
      Assert (Ev.Flag = 0,                       "Flag = 0");
      Assert (Ev.Nr = 4,                         "Nr = 4");
      Assert (To_String (Ev.Text) = "Send",      "Text = Send");
      Assert (To_String (Ev.Arg) = "",           "Arg empty");
      Assert (To_String (Ev.Origin) = "",        "Origin empty");
      Assert (not Next_Event (P, Ev),            "No more events");
   end Test_Simple_Execute;

   procedure Test_Simple_Look (T : in out Test) is
      pragma Unreferenced (T);
      --  "ML5 10 0 5 hello\n"
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("ML5 10 0 5 hello" & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse");
      Assert (Ev.C2 = 'L',                      "C2 = L (look tag)");
      Assert (Ev.Q0 = 5,                         "Q0 = 5");
      Assert (Ev.Q1 = 10,                        "Q1 = 10");
      Assert (To_String (Ev.Text) = "hello",     "Text = hello");
   end Test_Simple_Look;

   procedure Test_Keyboard_Insert (T : in out Test) is
      pragma Unreferenced (T);
      --  "Ki42 42 0 1 x\n"  -- keyboard insert of 'x' at pos 42
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("Ki42 42 0 1 x" & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse");
      Assert (Ev.C1 = 'K',                      "C1 = K (keyboard)");
      Assert (Ev.C2 = 'i',                      "C2 = i (insert)");
      Assert (To_String (Ev.Text) = "x",        "Text = x");
   end Test_Keyboard_Insert;

   procedure Test_Multi_Digit_Pos (T : in out Test) is
      pragma Unreferenced (T);
      --  Large position numbers
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("MX12345 67890 0 0 " & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse large positions");
      Assert (Ev.Q0 = 12345, "Q0 = 12345");
      Assert (Ev.Q1 = 67890, "Q1 = 67890");
      Assert (To_String (Ev.Text) = "", "Empty text (nr=0)");
   end Test_Multi_Digit_Pos;

   --  ── Expansion (flag & 2) ───────────────────────────────────────────────
   --
   --  When bit 2 of flag is set, a second event follows that carries the
   --  expanded position and actual text.  The main event has nr=0 and an
   --  empty text field.

   procedure Test_Flag2_Expansion (T : in out Test) is
      pragma Unreferenced (T);
      --  Main:      "Mx5 5 2 0 \n"   (flag=2, empty text at pos 5)
      --  Expansion: "Mx3 9 0 4 Send\n" (expanded: pos 3-9, text "Send")
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("Mx5 5 2 0 " & ASCII.LF
                      & "Mx3 9 0 4 Send" & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse expanded event");
      Assert (Ev.Q0  = 5,                       "Q0 = 5 (original)");
      Assert (Ev.Q1  = 5,                       "Q1 = 5 (original)");
      Assert (Ev.Eq0 = 3,                       "Eq0 = 3 (expanded)");
      Assert (Ev.Eq1 = 9,                       "Eq1 = 9 (expanded)");
      Assert (Ev.Flag = 2,                      "Flag = 2");
      Assert (To_String (Ev.Text) = "Send",     "Text from expansion event");
      Assert (not Next_Event (P, Ev),           "No more events");
   end Test_Flag2_Expansion;

   --  ── Chorded argument (flag & 8) ────────────────────────────────────────

   procedure Test_Flag8_Chorded (T : in out Test) is
      pragma Unreferenced (T);
      --  Main:   "Mx0 4 8 4 Edit\n"  (flag=8, chorded)
      --  Arg:    "Mx0 0 0 6 foo.go\n"
      --  Origin: "Mx0 0 0 0 \n"
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("Mx0 4 8 4 Edit" & ASCII.LF
                      & "Mx0 0 0 6 foo.go" & ASCII.LF
                      & "Mx0 0 0 0 " & ASCII.LF));
      Assert (Next_Event (P, Ev), "Should parse chorded event");
      Assert (To_String (Ev.Text)   = "Edit",   "Text = Edit");
      Assert (To_String (Ev.Arg)    = "foo.go", "Arg = foo.go");
      Assert (To_String (Ev.Origin) = "",       "Origin empty");
   end Test_Flag8_Chorded;

   --  ── Buffer management ──────────────────────────────────────────────────

   procedure Test_Incremental_Feed (T : in out Test) is
      pragma Unreferenced (T);
      --  Feed the event in two chunks; verify it still parses.
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
      Raw : constant String := "MX0 4 0 4 Stop" & ASCII.LF;
   begin
      Feed (P, Bytes (Raw (Raw'First .. Raw'First + 5)));
      Assert (not Next_Event (P, Ev), "Incomplete -> False");
      Feed (P, Bytes (Raw (Raw'First + 6 .. Raw'Last)));
      Assert (Next_Event (P, Ev), "Complete after second feed");
      Assert (To_String (Ev.Text) = "Stop", "Text = Stop");
   end Test_Incremental_Feed;

   procedure Test_Two_Events_One_Feed (T : in out Test) is
      pragma Unreferenced (T);
      P   : Event_Parser;
      Ev  : Acme.Event_Parser.Event;
   begin
      Feed (P, Bytes ("MX0 4 0 4 Send" & ASCII.LF
                      & "MX4 8 0 4 Stop" & ASCII.LF));
      Assert (Next_Event (P, Ev), "First event");
      Assert (To_String (Ev.Text) = "Send", "First text = Send");
      Assert (Next_Event (P, Ev), "Second event");
      Assert (To_String (Ev.Text) = "Stop", "Second text = Stop");
      Assert (not Next_Event (P, Ev), "No third event");
   end Test_Two_Events_One_Feed;

   procedure Test_Incomplete_Returns_False (T : in out Test) is
      pragma Unreferenced (T);
      P  : Event_Parser;
      Ev : Acme.Event_Parser.Event;
   begin
      Assert (not Next_Event (P, Ev), "Empty buffer -> False");
      Feed (P, Bytes ("MX0 "));     --  incomplete: missing rest
      Assert (not Next_Event (P, Ev), "Partial buffer -> False");
   end Test_Incomplete_Returns_False;

end Acme_Raw_Events_Tests;
