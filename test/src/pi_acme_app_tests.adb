with AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Pi_Acme_App; use Pi_Acme_App;

package body Pi_Acme_App_Tests is

   use AUnit.Assertions;

   --  ── Model ─────────────────────────────────────────────────────────────

   procedure Test_State_Model (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (S.Current_Model = "", "Initial model should be empty");
      S.Set_Model ("anthropic/claude-3-5-sonnet");
      Assert (S.Current_Model = "anthropic/claude-3-5-sonnet",
              "Model should be updated");
      S.Set_Model ("openai/gpt-4o");
      Assert (S.Current_Model = "openai/gpt-4o",
              "Model should be overwritten");
   end Test_State_Model;

   --  ── Streaming flag ───────────────────────────────────────────────────

   procedure Test_State_Streaming (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (not S.Is_Streaming, "Initially not streaming");
      S.Set_Streaming (True);
      Assert (S.Is_Streaming,
              "Should be streaming after Set_Streaming(True)");
      S.Set_Streaming (False);
      Assert (not S.Is_Streaming, "Should stop streaming");
   end Test_State_Streaming;

   --  ── Token counts ─────────────────────────────────────────────────────

   procedure Test_State_Tokens (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (S.Turn_Input_Tokens  = 0, "Initial input tokens = 0");
      Assert (S.Turn_Output_Tokens = 0, "Initial output tokens = 0");
      S.Set_Turn_Tokens (12345, 678);
      Assert (S.Turn_Input_Tokens  = 12345, "Input tokens updated");
      Assert (S.Turn_Output_Tokens = 678,   "Output tokens updated");
      S.Set_Context_Window (200_000);
      Assert (S.Context_Window = 200_000,   "Context window updated");
   end Test_State_Tokens;

   --  ── Shutdown barrier ─────────────────────────────────────────────────

   procedure Test_State_Shutdown (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;

      Completed : Boolean := False;

      task Waiter;
      task body Waiter is
      begin
         S.Wait_Shutdown;
         Completed := True;
      end Waiter;

   begin
      delay 0.05;
      Assert (not Completed, "Waiter should block before Signal_Shutdown");
      S.Signal_Shutdown;
      delay 0.1;
      Assert (Completed, "Waiter should unblock after Signal_Shutdown");
   end Test_State_Shutdown;

   --  ── Session ID ───────────────────────────────────────────────────────

   procedure Test_State_Session_Id (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (S.Session_Id = "", "Initial session ID is empty");
      S.Set_Session_Id ("abc-def-012345");
      Assert (S.Session_Id = "abc-def-012345",
              "Session ID should be stored verbatim");
   end Test_State_Session_Id;

   --  ── Session reload coordination ──────────────────────────────────────

   --  Request_Reload populates the UUID and sets Was_Requested.
   procedure Test_State_Request_Consume_Reload (T : in out Test) is
      pragma Unreferenced (T);
      S             : App_State;
      UUID          : Unbounded_String;
      Was_Requested : Boolean;
   begin
      S.Request_Reload ("dead-beef-1234");
      S.Consume_Reload (UUID, Was_Requested);
      Assert (Was_Requested,
              "Was_Requested should be True after Request_Reload");
      Assert (To_String (UUID) = "dead-beef-1234",
              "UUID should match the value passed to Request_Reload");
   end Test_State_Request_Consume_Reload;

   --  Consume_Reload clears the flag; a second call returns False.
   procedure Test_State_Consume_Clears_Flag (T : in out Test) is
      pragma Unreferenced (T);
      S             : App_State;
      UUID          : Unbounded_String;
      Was_Requested : Boolean;
   begin
      S.Request_Reload ("some-uuid");
      S.Consume_Reload (UUID, Was_Requested);
      Assert (Was_Requested, "First Consume_Reload: Was_Requested = True");
      S.Consume_Reload (UUID, Was_Requested);
      Assert (not Was_Requested,
              "Second Consume_Reload: flag should be cleared");
   end Test_State_Consume_Clears_Flag;

   --  Wait_Restart_Complete blocks until Signal_Restart_Done and returns
   --  Was_Restarted = True.
   procedure Test_State_Restart_Done (T : in out Test) is
      pragma Unreferenced (T);
      S             : App_State;
      Completed     : Boolean := False;
      Was_Restarted : Boolean := False;

      task Waiter;
      task body Waiter is
         Restarted : Boolean;
      begin
         S.Wait_Restart_Complete (Restarted);
         Was_Restarted := Restarted;
         Completed     := True;
      end Waiter;

   begin
      delay 0.05;
      Assert (not Completed,
              "Wait_Restart_Complete should block before signal");
      S.Signal_Restart_Done;
      delay 0.1;
      Assert (Completed,
              "Wait_Restart_Complete should unblock after "
              & "Signal_Restart_Done");
      Assert (Was_Restarted,
              "Was_Restarted should be True after Signal_Restart_Done");
   end Test_State_Restart_Done;

   --  Wait_Restart_Complete blocks until Signal_Restart_Aborted and returns
   --  Was_Restarted = False.
   procedure Test_State_Restart_Aborted (T : in out Test) is
      pragma Unreferenced (T);
      S             : App_State;
      Completed     : Boolean := False;
      Was_Restarted : Boolean := True;   --  Default True; expect False.

      task Waiter;
      task body Waiter is
         Restarted : Boolean;
      begin
         S.Wait_Restart_Complete (Restarted);
         Was_Restarted := Restarted;
         Completed     := True;
      end Waiter;

   begin
      delay 0.05;
      Assert (not Completed,
              "Wait_Restart_Complete should block before signal");
      S.Signal_Restart_Aborted;
      delay 0.1;
      Assert (Completed,
              "Wait_Restart_Complete should unblock after "
              & "Signal_Restart_Aborted");
      Assert (not Was_Restarted,
              "Was_Restarted should be False after Signal_Restart_Aborted");
   end Test_State_Restart_Aborted;

   --  Two consecutive restart cycles: the entry flag is correctly reset
   --  after each wait, so the second wait blocks and then unblocks.
   procedure Test_State_Reload_Cycle (T : in out Test) is
      pragma Unreferenced (T);
      S            : App_State;
      R1_Done      : Boolean := False;
      R1_Restarted : Boolean := False;
      R2_Done      : Boolean := False;
      R2_Restarted : Boolean := True;   --  Default True; expect False.

      task Waiter;
      task body Waiter is
         Restarted : Boolean;
      begin
         S.Wait_Restart_Complete (Restarted);   --  Round 1
         R1_Restarted := Restarted;
         R1_Done      := True;
         S.Wait_Restart_Complete (Restarted);   --  Round 2
         R2_Restarted := Restarted;
         R2_Done      := True;
      end Waiter;

   begin
      delay 0.05;
      Assert (not R1_Done, "Round 1: should block initially");
      S.Signal_Restart_Done;
      delay 0.05;
      Assert (R1_Done,      "Round 1: unblocked by Signal_Restart_Done");
      Assert (R1_Restarted, "Round 1: Was_Restarted = True");
      Assert (not R2_Done,  "Round 2: should block after Round 1 completes");
      S.Signal_Restart_Aborted;
      delay 0.1;
      Assert (R2_Done,
              "Round 2: unblocked by Signal_Restart_Aborted");
      Assert (not R2_Restarted, "Round 2: Was_Restarted = False");
   end Test_State_Reload_Cycle;

   --  ── Nth_Field ────────────────────────────────────────────────────────

   --  Basic space-separated cases.
   procedure Test_Nth_Field_Basic (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Nth_Field ("one two three", 1) = "one",   "Field 1");
      Assert (Nth_Field ("one two three", 2) = "two",   "Field 2");
      Assert (Nth_Field ("one two three", 3) = "three", "Field 3");
      Assert (Nth_Field ("one two three", 4) = "",      "Field 4 absent");
      Assert (Nth_Field ("  leading",     1) = "leading", "Leading spaces");
      Assert (Nth_Field ("a  b",          2) = "b",
              "Multiple spaces between fields");
      Assert (Nth_Field ("single",        1) = "single",
              "Single token, N=1");
      Assert (Nth_Field ("single",        2) = "",
              "Single token, N=2");
   end Test_Nth_Field_Basic;

   --  Tab separators (pi --list-models output uses tabs).
   procedure Test_Nth_Field_Tabs (T : in out Test) is
      pragma Unreferenced (T);
      Line : constant String :=
        "amazon-bedrock" & ASCII.HT
        & "amazon.nova-lite-v1:0" & ASCII.HT
        & "300K";
   begin
      Assert (Nth_Field (Line, 1) = "amazon-bedrock",     "Provider field");
      Assert (Nth_Field (Line, 2) = "amazon.nova-lite-v1:0", "Model field");
      Assert (Nth_Field (Line, 3) = "300K",               "Context field");
      Assert (Nth_Field (Line, 4) = "",                   "Field 4 absent");
   end Test_Nth_Field_Tabs;

   --  Edge cases: empty string, trailing whitespace, N=0 not reachable
   --  (N is Positive), single-char tokens.
   procedure Test_Nth_Field_Edges (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Nth_Field ("",      1) = "", "Empty string");
      Assert (Nth_Field ("   ",   1) = "", "Only spaces");
      Assert (Nth_Field ("a b  ", 2) = "b", "Trailing spaces, field 2");
      Assert (Nth_Field ("a b  ", 3) = "", "Trailing spaces, field 3 absent");
      Assert (Nth_Field ("x",     1) = "x", "Single char");
   end Test_Nth_Field_Edges;

   --  ── Parse_Session_Token ──────────────────────────────────────────────

   --  PID-tagged token matching this instance → bare UUID.
   procedure Test_Parse_Token_Pid_Match (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
      UUID   : constant String := "aabbccdd-1122-3344-5566-aabbccddeeff";
   begin
      Assert
        (Parse_Session_Token ("llm-chat+12345/" & UUID, Prefix) = UUID,
         "PID-tagged token for this instance should return UUID");
   end Test_Parse_Token_Pid_Match;

   --  PID-tagged token for a different instance → "".
   procedure Test_Parse_Token_Pid_Mismatch (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
      UUID   : constant String := "aabbccdd-1122-3344-5566-aabbccddeeff";
   begin
      Assert
        (Parse_Session_Token ("llm-chat+99999/" & UUID, Prefix) = "",
         "PID-tagged token for another instance should return empty");
   end Test_Parse_Token_Pid_Mismatch;

   --  Bare token (no PID, no '/' in UUID part) → UUID (backward-compat).
   procedure Test_Parse_Token_Bare (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
      UUID   : constant String := "aabbccdd11223344";
   begin
      Assert
        (Parse_Session_Token ("llm-chat+" & UUID, Prefix) = UUID,
         "Bare llm-chat+UUID token should return UUID");
   end Test_Parse_Token_Bare;

   --  A bare-looking token that turns out to have a '/' after "llm-chat+"
   --  belongs to another PID → "".
   procedure Test_Parse_Token_Other_Pid (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
   begin
      Assert
        (Parse_Session_Token
           ("llm-chat+99999/uuid-part", Prefix) = "",
         "Token with different PID prefix should return empty");
   end Test_Parse_Token_Other_Pid;

   --  Empty data string → "".
   procedure Test_Parse_Token_Empty (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
   begin
      Assert
        (Parse_Session_Token ("", Prefix) = "",
         "Empty data should return empty string");
   end Test_Parse_Token_Empty;

   --  Unrelated string → "".
   procedure Test_Parse_Token_Non_Token (T : in out Test) is
      pragma Unreferenced (T);
      Prefix : constant String := "llm-chat+12345/";
   begin
      Assert
        (Parse_Session_Token ("model+12345/openai/gpt-4o", Prefix) = "",
         "Non-session token should return empty string");
      Assert
        (Parse_Session_Token ("session:abcd1234", Prefix) = "",
         "session: prefix (not llm-chat+) should return empty string");
   end Test_Parse_Token_Non_Token;

end Pi_Acme_App_Tests;
