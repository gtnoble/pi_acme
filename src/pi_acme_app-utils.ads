--  Pi_Acme_App.Utils — pure utility functions shared by Pi_Acme_App.
--
--  All subprograms in this package take only plain parameters and have no
--  dependency on App_State, Acme.Window, or Pi_RPC.  They may be tested in
--  isolation without a live acme session.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with GNATCOLL.JSON;
with Nine_P;

package Pi_Acme_App.Utils is

   --  ── UTF-8 pseudographic constants ────────────────────────────────────
   --  Each constant holds the UTF-8 byte sequence for one Unicode character.

   UC_BULLET : constant String :=  --  ●  U+25CF
     Character'Val (16#E2#) & Character'Val (16#97#) & Character'Val (16#8F#);
   UC_DBL_H  : constant String :=  --  ═  U+2550
     Character'Val (16#E2#) & Character'Val (16#95#) & Character'Val (16#90#);
   UC_BOX_V  : constant String :=  --  │  U+2502
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#82#);
   UC_BOX_TL : constant String :=  --  ┌  U+250C
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#8C#);
   UC_BOX_BL : constant String :=  --  └  U+2514
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#94#);
   UC_GEAR   : constant String :=  --  ⚙  U+2699
     Character'Val (16#E2#) & Character'Val (16#9A#) & Character'Val (16#99#);
   UC_CHECK  : constant String :=  --  ✓  U+2713
     Character'Val (16#E2#) & Character'Val (16#9C#) & Character'Val (16#93#);
   UC_CROSS  : constant String :=  --  ✗  U+2717
     Character'Val (16#E2#) & Character'Val (16#9C#) & Character'Val (16#97#);
   UC_TRI_R  : constant String :=  --  ▶  U+25B6
     Character'Val (16#E2#) & Character'Val (16#96#) & Character'Val (16#B6#);
   UC_WARN   : constant String :=  --  ⚠  U+26A0
     Character'Val (16#E2#) & Character'Val (16#9A#) & Character'Val (16#A0#);
   UC_ELLIP  : constant String :=  --  …  U+2026
     Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#A6#);
   UC_HORIZ  : constant String :=  --  ─  U+2500
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#80#);
   UC_RETRY  : constant String :=  --  ↻  U+21BB
     Character'Val (16#E2#) & Character'Val (16#86#) & Character'Val (16#BB#);
   UC_HOOK_L : constant String :=  --  ↩  U+21A9
     Character'Val (16#E2#) & Character'Val (16#86#) & Character'Val (16#A9#);

   --  ── String utilities ─────────────────────────────────────────────────

   --  Repeat string Text exactly N times.
   function Str_Repeat (Text : String; N : Positive) return String;

   --  Natural'Image without the leading space.
   function Natural_Image (N : Natural) return String;

   --  Format a token count compactly: 800 -> "800", 1500 -> "1.5k".
   function Format_Kilo (N : Natural) return String;

   --  Format N (units of $0.0001) as "$D.FFFF".
   --  Examples: 0 -> "$0.0000", 234 -> "$0.0234", 12345 -> "$1.2345".
   function Format_Cost (Dmil : Natural) return String;

   --  Return just the stem of an agent path.
   --  E.g. "~/.../foo.agent.md" -> "foo"
   function Agent_Stem (Path : String) return String;

   --  Return the N-th (1-based) whitespace-separated token from Text,
   --  or "" if Text has fewer than N tokens.  Whitespace is space or HT.
   function Nth_Field (Text : String; N : Positive) return String;

   --  Extract the session UUID from a plumb session token.
   --  Pid_Prefix must be "llm-chat+PID/" for this pi-acme instance.
   --
   --  Accepts:
   --    "llm-chat+PID/UUID"       -> UUID  (PID-tagged for this instance)
   --    "llm-chat+UUID"           -> UUID  (bare token, backward-compat)
   --  Rejects (returns ""):
   --    "llm-chat+OTHER_PID/UUID" -> ""   (tagged for another instance)
   --    anything else             -> ""
   function Parse_Session_Token
     (Data       : String;
      Pid_Prefix : String) return String;

   --  Return the first 16 hex characters of the SHA-256 digest of Tool_Id,
   --  matching the token computed by the Python reference implementation:
   --    hashlib.sha256(tool_id.encode()).hexdigest()[:16]
   function Hash_Tool_Id (Tool_Id : String) return String;

   --  Scan Context (a substring of the acme body starting at rune Ctx_Start)
   --  for a llm-chat+.../tool/... URI that contains rune position Anchor.
   --  Returns the first matching token string, or "" if none is found.
   --
   --  Token pattern:  llm-chat+ [0-9a-f-]+ /tool/ [0-9a-f]+
   --
   --  Local byte positions in Context are converted to approximate body rune
   --  offsets by adding Ctx_Start.  This is exact for the ASCII-only tokens
   --  this function scans for; any multi-byte UTF-8 characters that precede
   --  the token introduce only a small positive error acceptable for
   --  click-position matching.
   function Scan_Tool_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String;

   --  Scan Context for a fork+PID/SESSION-UUID/TURN-N token that contains
   --  rune position Anchor.  Returns the token string, or "".
   --
   --  Token pattern:  fork+ [0-9]+ / [0-9a-f-]+ / [0-9]+
   --
   --  The same ASCII-only approximation for rune offsets applies here.
   function Scan_Fork_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String;

   --  Run `diff -u` on Old_Text vs New_Text, strip the ---/+++/@@ unified
   --  diff header lines, and return the remaining body lines joined by
   --  ASCII.LF.  Truncates to Max_L body lines (default 30) and appends a
   --  "… N more lines" trailer when the diff exceeds the limit.
   --
   --  Returns "(no changes)" when Old_Text = New_Text or when the diff
   --  produces no body lines.  Returns "(diff error)" if the `diff`
   --  subprocess cannot be started.
   --
   --  Matches the behaviour of the Python reference's edit_diff_lines().
   function Edit_Diff_Lines
     (Old_Text : String;
      New_Text : String;
      Max_L    : Positive := 30) return String;

   --  Extract the data payload from a raw plumb message byte array.
   --  A plumb message is 7 newline-separated fields; the last field is
   --  the data payload.  Returns "" if the message is malformed.
   function Extract_Plumb_Data (Raw : Nine_P.Byte_Array) return String;

   --  ── Turn footer builders ─────────────────────────────────────────────

   --  Build the bracketed per-turn summary placed before the fork token.
   --  Returns "" when no summary parts are available.
   function Format_Turn_Summary
     (Input_Tokens      : Natural;
      Output_Tokens     : Natural;
      Ctx_Window        : Natural;
      Model_Text        : String;
      Turn_Cost_Dmil    : Natural := 0;
      Session_Cost_Dmil : Natural := 0) return String;

   --  Turn footer between completed turns.  Carries a clickable fork token
   --  so button-3 opens a forked session.
   --  Format: [summary ]fork+PID/UUID/N\n════...════\n\n
   function Format_Turn_Footer
     (Turn_N            : Positive;
      UUID              : String;
      PID               : String;
      Input_Tokens      : Natural := 0;
      Output_Tokens     : Natural := 0;
      Ctx_Window        : Natural := 0;
      Model_Text        : String  := "";
      Turn_Cost_Dmil    : Natural := 0;
      Session_Cost_Dmil : Natural := 0) return String;

   --  ── JSON field helpers ────────────────────────────────────────────────

   --  Return the string value of Field from Val, or "" if absent or not
   --  a JSON string.
   function Get_String
     (Val   : GNATCOLL.JSON.JSON_Value;
      Field : GNATCOLL.JSON.UTF8_String) return String;

   --  Return the integer value of Field from Val as Natural, or 0 if
   --  absent or not a JSON integer.
   function Get_Integer
     (Val   : GNATCOLL.JSON.JSON_Value;
      Field : GNATCOLL.JSON.UTF8_String) return Natural;

   --  Read a JSON cost field (float or integer) and return the value in
   --  units of $0.0001 ("dmil").  Handles JSON_Float_Type (the normal case
   --  from pi's cost.total computation) and JSON_Int_Type (zero when no
   --  pricing is configured).  Returns 0 when the field is absent, zero,
   --  or negative.
   function Get_Cost_Dmil
     (Val   : GNATCOLL.JSON.JSON_Value;
      Field : GNATCOLL.JSON.UTF8_String) return Natural;

   --  Return the boolean value of Field from Val, or False if absent or
   --  not a JSON boolean.
   function Get_Boolean
     (Val   : GNATCOLL.JSON.JSON_Value;
      Field : GNATCOLL.JSON.UTF8_String) return Boolean;

   --  Return the object value of Field from Val, or JSON_Null if absent
   --  or not a JSON object.
   function Get_Object
     (Val   : GNATCOLL.JSON.JSON_Value;
      Field : GNATCOLL.JSON.UTF8_String) return GNATCOLL.JSON.JSON_Value;

   --  Return a human-readable string for a scalar JSON value suitable for
   --  display in tool-call argument summaries.
   --
   --  Strings are returned as-is (no quotation marks).  Integers, booleans,
   --  and floats are serialised by GNATCOLL.JSON.Write (e.g. 42, true,
   --  3.14).  Null, object, and array values return "...".
   function JSON_Scalar_Image
     (Val : GNATCOLL.JSON.JSON_Value) return String;

   --  Format a single tool-argument field for display in the acme window.
   --
   --  The first line of the result is "│ Name: <first line of Value>".
   --  Each subsequent line (delimited by ASCII.LF in Value) is prefixed
   --  with "│ " so that the box border is continuous for multi-line
   --  values such as bash commands.
   --
   --  Value is truncated to Max_Len bytes (keeping the first Max_Len - 3
   --  bytes and appending "…") when Value'Length > Max_Len.
   --
   --  The returned string contains no leading LF; the caller should
   --  prepend ASCII.LF before appending to the acme window body.
   function Format_Tool_Field
     (Name    : String;
      Value   : String;
      Max_Len : Positive := 200) return String;

end Pi_Acme_App.Utils;
