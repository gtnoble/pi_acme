with AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Acme.Event_Parser;     use Acme.Event_Parser;

package body Acme_Event_Parser_Tests is

   use AUnit.Assertions;

   --  ── Rc_Token tests via full Parse ─────────────────────────────────────
   --
   --  Rc_Token is private to the package body, so we exercise it indirectly
   --  by parsing event lines with known text fields.

   procedure Test_Unquoted_Token (T : in out Test) is
      pragma Unreferenced (T);
      Ev : Event;
      Ok : constant Boolean :=
        Parse ("event M X 0 4 0 4 0 4 Send  ", Ev);
   begin
      Assert (Ok,                               "Should parse successfully");
      Assert (To_String (Ev.Text) = "Send",     "Text should be 'Send'");
      Assert (To_String (Ev.Arg) = "",          "Arg should be empty");
      Assert (To_String (Ev.Origin) = "",       "Origin should be empty");
   end Test_Unquoted_Token;

   procedure Test_Quoted_Token (T : in out Test) is
      pragma Unreferenced (T);
      Ev : Event;
      Ok : constant Boolean :=
        Parse ("event M X 0 9 0 9 0 9 'hello world'  ", Ev);
   begin
      Assert (Ok, "Should parse successfully");
      Assert (To_String (Ev.Text) = "hello world",
              "Quoted text with space");
   end Test_Quoted_Token;

   procedure Test_Escaped_Quote (T : in out Test) is
      pragma Unreferenced (T);
      Ev : Event;
      --  Text is the string: it's  (with a literal apostrophe)
      --  rc encoding: 'it''s'
      Ok : constant Boolean :=
        Parse ("event M X 0 4 0 4 0 4 'it''s'  ", Ev);
   begin
      Assert (Ok,                               "Should parse successfully");
      Assert (To_String (Ev.Text) = "it's",     "Escaped '' should become '");
   end Test_Escaped_Quote;

   --  ── Full event parsing ────────────────────────────────────────────────

   procedure Test_Parse_Execute (T : in out Test) is
      pragma Unreferenced (T);
      --  button-2 (M) execute (X) of "Send" at positions 10-14
      Ev : Event;
      Ok : constant Boolean :=
        Parse ("event M X 10 14 10 14 0 4 Send  ", Ev);
   begin
      Assert (Ok,               "Should parse successfully");
      Assert (Ev.C1 = 'M',      "C1 should be M (mouse)");
      Assert (Ev.C2 = 'X',      "C2 should be X (execute tag)");
      Assert (Ev.Q0 = 10,       "Q0 should be 10");
      Assert (Ev.Q1 = 14,       "Q1 should be 14");
      Assert (Ev.Eq0 = 10,      "Eq0 should be 10");
      Assert (Ev.Eq1 = 14,      "Eq1 should be 14");
      Assert (Ev.Flag = 0,      "Flag should be 0");
      Assert (Ev.Nr = 4,        "Nr should be 4");
      Assert (To_String (Ev.Text) = "Send", "Text should be 'Send'");
   end Test_Parse_Execute;

   procedure Test_Parse_Look (T : in out Test) is
      pragma Unreferenced (T);
      --  button-3 (M) look (L) of a filename at positions 5-10
      Ev : Event;
      Ok : constant Boolean :=
        Parse ("event M L 5 10 5 15 0 5 hello foo.c", Ev);
   begin
      Assert (Ok,                           "Should parse successfully");
      Assert (Ev.C1 = 'M',                  "C1 should be M");
      Assert (Ev.C2 = 'L',                  "C2 should be L (look tag)");
      Assert (Ev.Q0 = 5,                    "Q0 should be 5");
      Assert (Ev.Q1 = 10,                   "Q1 should be 10");
      Assert (Ev.Eq0 = 5,                   "Eq0 should be 5");
      Assert (Ev.Eq1 = 15,                  "Eq1 should be 15");
      Assert (To_String (Ev.Text) = "hello", "Text should be 'hello'");
      Assert (To_String (Ev.Arg)  = "foo.c", "Arg should be 'foo.c'");
   end Test_Parse_Look;

   procedure Test_Parse_Quoted_Text (T : in out Test) is
      pragma Unreferenced (T);
      --  Text with embedded spaces, no arg or origin
      Ev : Event;
      Ok : constant Boolean :=
        Parse ("event K x 0 11 0 11 1 11 'hello world'  ", Ev);
   begin
      Assert (Ok, "Should parse successfully");
      Assert (Ev.C1 = 'K',
              "C1 should be K (keyboard)");
      Assert (Ev.C2 = 'x',
              "C2 should be x (execute body)");
      Assert (Ev.Flag = 1,                          "Flag should be 1");
      Assert (To_String (Ev.Text) = "hello world",  "Quoted text");
   end Test_Parse_Quoted_Text;

   procedure Test_Parse_Invalid (T : in out Test) is
      pragma Unreferenced (T);
      Ev : Event;
   begin
      Assert (not Parse ("foo bar baz", Ev),    "Non-event line ->False");
      Assert (not Parse ("event M",     Ev),    "Too few fields ->False");
      Assert (not Parse ("event M X x 4 0 4 0 4 Send  ", Ev),
              "Non-integer field ->False");
   end Test_Parse_Invalid;

   procedure Test_Parse_Empty (T : in out Test) is
      pragma Unreferenced (T);
      Ev : Event;
   begin
      Assert (not Parse ("",  Ev), "Empty string ->False");
      Assert (not Parse ("  ", Ev), "Whitespace only ->False");
   end Test_Parse_Empty;

end Acme_Event_Parser_Tests;
