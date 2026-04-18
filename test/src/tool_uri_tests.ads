--  Tool_URI_Tests — unit tests for Hash_Tool_Id and Scan_Tool_Token.
--
--  Both functions are pure (no I/O, no acme required), so every test
--  here runs unconditionally and does not need a live acme instance.
--
--  Hash_Tool_Id expected values were verified against the Python reference:
--    hashlib.sha256(tool_id.encode()).hexdigest()[:16]
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with AUnit;
with AUnit.Test_Fixtures;

package Tool_URI_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  ── Hash_Tool_Id ──────────────────────────────────────────────────────

   --  Empty string produces the SHA-256 of b"".
   procedure Test_Hash_Empty               (T : in out Test);

   --  Known non-empty inputs match Python reference values.
   procedure Test_Hash_Known_Values        (T : in out Test);

   --  Result is always exactly 16 characters.
   procedure Test_Hash_Length              (T : in out Test);

   --  Different inputs always produce different hashes (no collision
   --  for a small representative sample).
   procedure Test_Hash_Distinct            (T : in out Test);

   --  Result contains only lowercase hex characters.
   procedure Test_Hash_Lowercase_Hex       (T : in out Test);

   --  ── Scan_Tool_Token ───────────────────────────────────────────────────

   --  Anchor at start of token, token at start of context.
   procedure Test_Scan_Token_At_Start      (T : in out Test);

   --  Anchor at end of token, token at end of context.
   procedure Test_Scan_Token_At_End        (T : in out Test);

   --  Anchor in the middle of a token surrounded by other text.
   procedure Test_Scan_Token_In_Middle     (T : in out Test);

   --  Anchor is exactly on the first character of the token.
   procedure Test_Scan_Anchor_At_Token_Start (T : in out Test);

   --  Anchor is exactly on the last character of the token.
   procedure Test_Scan_Anchor_At_Token_End   (T : in out Test);

   --  Anchor is one position before the token → no match.
   procedure Test_Scan_Anchor_Before_Token (T : in out Test);

   --  Anchor is one position after the token → no match.
   procedure Test_Scan_Anchor_After_Token  (T : in out Test);

   --  Empty context string → "".
   procedure Test_Scan_Empty_Context       (T : in out Test);

   --  Context contains no llm-chat+ prefix → "".
   procedure Test_Scan_No_Token            (T : in out Test);

   --  Token missing "/tool/" separator → not recognised.
   procedure Test_Scan_No_Tool_Separator   (T : in out Test);

   --  Token with empty hex suffix after "/tool/" → not recognised.
   procedure Test_Scan_Empty_Hex_Suffix    (T : in out Test);

   --  UUID part is empty (nothing between "llm-chat+" and "/tool/")
   --  → not recognised.
   procedure Test_Scan_Empty_Uuid          (T : in out Test);

   --  Non-zero Ctx_Start shifts positions correctly: anchor expressed as
   --  a body rune offset finds the token when Ctx_Start is large.
   procedure Test_Scan_Nonzero_Ctx_Start   (T : in out Test);

   --  Two tokens in the context; anchor selects the second one.
   procedure Test_Scan_Second_Of_Two       (T : in out Test);

   --  ── Scan_Fork_Token ───────────────────────────────────────────────────

   --  Anchor inside a valid fork+PID/UUID/N token → token returned.
   procedure Test_Scan_Fork_Basic          (T : in out Test);

   --  Anchor one position before the token → "".
   procedure Test_Scan_Fork_Before         (T : in out Test);

   --  Anchor one position after the token → "".
   procedure Test_Scan_Fork_After          (T : in out Test);

   --  Empty context → "".
   procedure Test_Scan_Fork_Empty          (T : in out Test);

   --  Non-zero Ctx_Start shifts positions correctly.
   procedure Test_Scan_Fork_Ctx_Start      (T : in out Test);

   --  Missing UUID part (two consecutive slashes) → not recognised.
   procedure Test_Scan_Fork_No_Uuid        (T : in out Test);

   --  Missing turn-N part (trailing slash only) → not recognised.
   procedure Test_Scan_Fork_No_Turn        (T : in out Test);

end Tool_URI_Tests;
