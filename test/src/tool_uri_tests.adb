--  Tool_URI_Tests body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with AUnit.Assertions;
with Pi_Acme_App.Utils;  use Pi_Acme_App.Utils;

package body Tool_URI_Tests is

   use AUnit.Assertions;

   --  ── Helpers ──────────────────────────────────────────────────────────

   --  True iff every character of S is a lowercase hex digit (0-9, a-f).
   function Is_Lowercase_Hex (S : String) return Boolean is
   begin
      for C of S loop
         if C not in '0' .. '9' | 'a' .. 'f' then
            return False;
         end if;
      end loop;
      return True;
   end Is_Lowercase_Hex;

   --  Build the canonical token string for a given session UUID and tool hash.
   function Make_Token (Session_UUID : String; Hash : String) return String is
   begin
      return "llm-chat+" & Session_UUID & "/tool/" & Hash;
   end Make_Token;

   --  Sample UUID used throughout the Scan tests.
   Sample_UUID : constant String :=
     "aabbccdd-1122-3344-5566-aabbccddeeff";

   --  ── Hash_Tool_Id tests ────────────────────────────────────────────────

   --  SHA-256("") =
   --    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
   --  First 16 hex chars = "e3b0c44298fc1c14"
   procedure Test_Hash_Empty (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Hash_Tool_Id ("") = "e3b0c44298fc1c14",
              "SHA-256 of empty string should match Python reference");
   end Test_Hash_Empty;

   --  Known values cross-checked against:
   --    python3 -c "import hashlib;
   --                print(hashlib.sha256(b'tc-ok-001').hexdigest()[:16])"
   procedure Test_Hash_Known_Values (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert
        (Hash_Tool_Id ("tc-ok-001") = "e74ffc63142d6dcb",
         "Hash of 'tc-ok-001' should match Python reference");
      Assert
        (Hash_Tool_Id ("toolfoo") = "bb4537d4f05a6a84",
         "Hash of 'toolfoo' should match Python reference");
      Assert
        (Hash_Tool_Id ("abc123def456") = "e861b2eab679927c",
         "Hash of 'abc123def456' should match Python reference");
   end Test_Hash_Known_Values;

   --  Hash_Tool_Id must always return exactly 16 characters.
   procedure Test_Hash_Length (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Hash_Tool_Id ("")'Length = 16,
              "Hash of empty string should be 16 chars");
      Assert (Hash_Tool_Id ("x")'Length = 16,
              "Hash of single char should be 16 chars");
      Assert (Hash_Tool_Id ("some-tool-call-id-12345")'Length = 16,
              "Hash of longer string should be 16 chars");
   end Test_Hash_Length;

   --  A small sample of distinct inputs should produce distinct hashes.
   procedure Test_Hash_Distinct (T : in out Test) is
      pragma Unreferenced (T);
      H1 : constant String := Hash_Tool_Id ("alpha");
      H2 : constant String := Hash_Tool_Id ("beta");
      H3 : constant String := Hash_Tool_Id ("gamma");
      H4 : constant String := Hash_Tool_Id ("alpha2");
   begin
      Assert (H1 /= H2, "Different inputs should yield different hashes (1)");
      Assert (H1 /= H3, "Different inputs should yield different hashes (2)");
      Assert (H2 /= H3, "Different inputs should yield different hashes (3)");
      Assert (H1 /= H4, "Different inputs should yield different hashes (4)");
   end Test_Hash_Distinct;

   --  All characters in the result must be lowercase hex digits.
   procedure Test_Hash_Lowercase_Hex (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Is_Lowercase_Hex (Hash_Tool_Id ("")),
              "Hash of empty string should be lowercase hex");
      Assert (Is_Lowercase_Hex (Hash_Tool_Id ("hello")),
              "Hash of 'hello' should be lowercase hex");
      Assert (Is_Lowercase_Hex (Hash_Tool_Id ("UPPER")),
              "Hash of upper-case input should still be lowercase hex");
   end Test_Hash_Lowercase_Hex;

   --  ── Scan_Tool_Token tests ─────────────────────────────────────────────

   --  Token at the very beginning of the context string.
   --  Ctx_Start = 0; anchor = 5 (middle of token).
   procedure Test_Scan_Token_At_Start (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc1");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Context : constant String := Token & " some text after";
      Anchor  : constant Natural := 5;   --  well inside the token
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Token,
         "Token at context start should be found");
   end Test_Scan_Token_At_Start;

   --  Token at the very end of the context string.
   procedure Test_Scan_Token_At_End (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc2");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Prefix  : constant String := "some text before ";
      Context : constant String := Prefix & Token;
      --  Anchor is in the middle of the token, expressed as a body offset
      --  with Ctx_Start = 0 so it equals the byte offset within Context.
      Anchor  : constant Natural := Prefix'Length + Token'Length / 2;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Token,
         "Token at context end should be found");
   end Test_Scan_Token_At_End;

   --  Token surrounded by arbitrary text on both sides.
   procedure Test_Scan_Token_In_Middle (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc3");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Before  : constant String := "text before | ";
      After   : constant String := " | text after";
      Context : constant String := Before & Token & After;
      Anchor  : constant Natural := Before'Length + Token'Length / 2;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Token,
         "Token in middle of context should be found");
   end Test_Scan_Token_In_Middle;

   --  Anchor falls on the first character of the token.
   procedure Test_Scan_Anchor_At_Token_Start (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc4");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Before  : constant String := "prefix ";
      Context : constant String := Before & Token & " suffix";
      --  Anchor = first character of token in body rune space.
      Anchor  : constant Natural := Before'Length;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Token,
         "Anchor at token start (inclusive) should match");
   end Test_Scan_Anchor_At_Token_Start;

   --  Anchor falls on the last character of the token.
   procedure Test_Scan_Anchor_At_Token_End (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc5");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Before  : constant String := "prefix ";
      Context : constant String := Before & Token & " suffix";
      --  Anchor = last character of token.
      Anchor  : constant Natural := Before'Length + Token'Length - 1;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Token,
         "Anchor at token end (inclusive) should match");
   end Test_Scan_Anchor_At_Token_End;

   --  Anchor one position before the token start → no match.
   procedure Test_Scan_Anchor_Before_Token (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc6");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Before  : constant String := "prefix ";
      Context : constant String := Before & Token;
   begin
      --  The character just before the token (index Before'Length - 1,
      --  0-based = Before'Length - 1) is outside the token bounds.
      Assert
        (Scan_Tool_Token (Context, 0, Before'Length - 1) = "",
         "Anchor one position before token should return empty");
   end Test_Scan_Anchor_Before_Token;

   --  Anchor one position after the token end → no match.
   procedure Test_Scan_Anchor_After_Token (T : in out Test) is
      pragma Unreferenced (T);
      Hash    : constant String := Hash_Tool_Id ("tc7");
      Token   : constant String := Make_Token (Sample_UUID, Hash);
      Before  : constant String := "prefix ";
      Context : constant String := Before & Token & " suffix";
      --  Anchor = first character after the token.
      Anchor  : constant Natural := Before'Length + Token'Length;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = "",
         "Anchor one position after token should return empty");
   end Test_Scan_Anchor_After_Token;

   --  Empty context → "".
   procedure Test_Scan_Empty_Context (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Scan_Tool_Token ("", 0, 0) = "",
              "Empty context should return empty string");
   end Test_Scan_Empty_Context;

   --  Context with no llm-chat+ token at all.
   procedure Test_Scan_No_Token (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert
        (Scan_Tool_Token ("just some ordinary text", 0, 5) = "",
         "Context with no token should return empty string");
   end Test_Scan_No_Token;

   --  Token with no "/tool/" separator is not recognised.
   procedure Test_Scan_No_Tool_Separator (T : in out Test) is
      pragma Unreferenced (T);
      --  Deliberately omit "/tool/"
      Fake_Token : constant String :=
        "llm-chat+" & Sample_UUID & "/notool/" & Hash_Tool_Id ("x");
      Context    : constant String := Fake_Token;
      Anchor     : constant Natural := Fake_Token'Length / 2;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = "",
         "Token without '/tool/' should not be recognised");
   end Test_Scan_No_Tool_Separator;

   --  Token with empty hex suffix after "/tool/" is not recognised.
   procedure Test_Scan_Empty_Hex_Suffix (T : in out Test) is
      pragma Unreferenced (T);
      --  "/tool/" with nothing after it
      Fake_Token : constant String :=
        "llm-chat+" & Sample_UUID & "/tool/";
      Context    : constant String := Fake_Token & " ";
      Anchor     : constant Natural := Fake_Token'Length - 1;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = "",
         "Token with empty hex suffix should not be recognised");
   end Test_Scan_Empty_Hex_Suffix;

   --  Nothing between "llm-chat+" and "/tool/" → UUID part is empty
   --  → not recognised (the scanner requires at least one UUID char).
   procedure Test_Scan_Empty_Uuid (T : in out Test) is
      pragma Unreferenced (T);
      Fake_Token : constant String :=
        "llm-chat+" & "/tool/" & Hash_Tool_Id ("x");
      Context    : constant String := Fake_Token;
      Anchor     : constant Natural := 5;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = "",
         "Token with empty UUID part should not be recognised");
   end Test_Scan_Empty_Uuid;

   --  Non-zero Ctx_Start: the context string starts at body rune 1000.
   --  All positions are shifted accordingly.
   procedure Test_Scan_Nonzero_Ctx_Start (T : in out Test) is
      pragma Unreferenced (T);
      Ctx_Start : constant Natural := 1000;
      Hash      : constant String  := Hash_Tool_Id ("tc-ctx");
      Token     : constant String  := Make_Token (Sample_UUID, Hash);
      Before    : constant String  := "leading ";
      Context   : constant String  := Before & Token & " trailing";
      --  Anchor expressed as an absolute body rune offset.
      --  Token starts at byte Before'Length within Context, which
      --  corresponds to body rune Ctx_Start + Before'Length.
      Anchor    : constant Natural :=
        Ctx_Start + Before'Length + Token'Length / 2;
   begin
      Assert
        (Scan_Tool_Token (Context, Ctx_Start, Anchor) = Token,
         "Non-zero Ctx_Start should shift rune positions correctly");
   end Test_Scan_Nonzero_Ctx_Start;

   --  Two tokens in the context; anchor placed in the second one.
   procedure Test_Scan_Second_Of_Two (T : in out Test) is
      pragma Unreferenced (T);
      Hash1   : constant String := Hash_Tool_Id ("first");
      Hash2   : constant String := Hash_Tool_Id ("second");
      Tok1    : constant String := Make_Token (Sample_UUID, Hash1);
      Tok2    : constant String := Make_Token (Sample_UUID, Hash2);
      Sep     : constant String := "  ";
      Context : constant String := Tok1 & Sep & Tok2;
      --  Anchor inside Tok2.
      Anchor  : constant Natural :=
        Tok1'Length + Sep'Length + Tok2'Length / 2;
   begin
      Assert
        (Scan_Tool_Token (Context, 0, Anchor) = Tok2,
         "Anchor in second token should return second token");
   end Test_Scan_Second_Of_Two;

   --  ── Scan_Fork_Token ───────────────────────────────────────────────────

   --  Representative valid token used across the fork tests.
   --  Format:  fork+<PID>/<UUID>/<TURN>
   Fork_Token : constant String :=
     "fork+12345/abc123ef-0000-4000-8000-ffffffffffff/7";

   procedure Test_Scan_Fork_Basic (T : in out Test) is
      pragma Unreferenced (T);
      Context : constant String := Fork_Token;
      Anchor  : constant Natural := Fork_Token'Length / 2;
   begin
      Assert
        (Scan_Fork_Token (Context, 0, Anchor) = Fork_Token,
         "Anchor in middle of fork token should return the token");
   end Test_Scan_Fork_Basic;

   procedure Test_Scan_Fork_Before (T : in out Test) is
      pragma Unreferenced (T);
      Pad     : constant String := "xxx";
      Context : constant String := Pad & Fork_Token;
      --  Anchor falls in the padding, before the token.
      Anchor  : constant Natural := Pad'Length - 1;
   begin
      Assert
        (Scan_Fork_Token (Context, 0, Anchor) = "",
         "Anchor before fork token should return empty");
   end Test_Scan_Fork_Before;

   procedure Test_Scan_Fork_After (T : in out Test) is
      pragma Unreferenced (T);
      Context : constant String := Fork_Token & "zzz";
      --  Anchor falls one position past the last character of the token.
      Anchor  : constant Natural := Fork_Token'Length;
   begin
      Assert
        (Scan_Fork_Token (Context, 0, Anchor) = "",
         "Anchor one position after fork token should return empty");
   end Test_Scan_Fork_After;

   procedure Test_Scan_Fork_Empty (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert
        (Scan_Fork_Token ("", 0, 0) = "",
         "Empty context should return empty");
   end Test_Scan_Fork_Empty;

   procedure Test_Scan_Fork_Ctx_Start (T : in out Test) is
      pragma Unreferenced (T);
      Ctx_Start : constant Natural := 500;
      Context   : constant String  := Fork_Token;
      --  Anchor expressed as a body rune offset (Ctx_Start + local offset).
      Anchor    : constant Natural :=
        Ctx_Start + Fork_Token'Length / 2;
   begin
      Assert
        (Scan_Fork_Token (Context, Ctx_Start, Anchor) = Fork_Token,
         "Non-zero Ctx_Start should shift positions correctly");
   end Test_Scan_Fork_Ctx_Start;

   procedure Test_Scan_Fork_No_Uuid (T : in out Test) is
      pragma Unreferenced (T);
      --  Two consecutive slashes — UUID part is empty.
      Bad     : constant String := "fork+99//3";
      Anchor  : constant Natural := Bad'Length / 2;
   begin
      Assert
        (Scan_Fork_Token (Bad, 0, Anchor) = "",
         "Empty UUID part should not be recognised as a fork token");
   end Test_Scan_Fork_No_Uuid;

   procedure Test_Scan_Fork_No_Turn (T : in out Test) is
      pragma Unreferenced (T);
      --  Trailing slash but no turn digits.
      Bad    : constant String := "fork+99/abcdef-1234/";
      Anchor : constant Natural := Bad'Length / 2;
   begin
      Assert
        (Scan_Fork_Token (Bad, 0, Anchor) = "",
         "Missing turn number should not be recognised as a fork token");
   end Test_Scan_Fork_No_Turn;

end Tool_URI_Tests;
