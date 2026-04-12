--  Session_History_Tests — integration tests for Render_Session_History.
--
--  Each test writes a temporary JSONL session file, opens a fresh acme
--  window, calls Render_Session_History, and inspects the window body.
--  All tests are guarded with an Acme_Running check and are silently
--  skipped when acme is not available.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with AUnit;
with AUnit.Test_Fixtures;

package Session_History_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Session file not found → error message written to window.
   procedure Test_Render_File_Not_Found    (T : in out Test);

   --  User message rendered as "▶ <text>".
   procedure Test_Render_User_Message      (T : in out Test);

   --  Assistant plain-text block rendered verbatim.
   procedure Test_Render_Assistant_Text    (T : in out Test);

   --  Successful tool call renders "✓" result line.
   procedure Test_Render_Tool_Call_Success (T : in out Test);

   --  Failed tool call renders "✗" result line with error preview.
   procedure Test_Render_Tool_Call_Error   (T : in out Test);

   --  Thinking block rendered with "│ " prefix.
   procedure Test_Render_Thinking_Block    (T : in out Test);

   --  model_change event renders "[Model → ...]" line.
   procedure Test_Render_Model_Change      (T : in out Test);

   --  Usage block in last assistant message updates State.Turn_Tokens.
   procedure Test_Render_Token_Stats       (T : in out Test);

   --  SEPARATOR line is appended after the history.
   procedure Test_Render_Separator         (T : in out Test);

end Session_History_Tests;
