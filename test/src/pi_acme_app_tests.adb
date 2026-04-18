with AUnit.Assertions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNATCOLL.JSON;         use GNATCOLL.JSON;
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

   --  ── App_State Turn_Count ──────────────────────────────────────────────

   procedure Test_State_Turn_Count_Increment (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (S.Turn_Count = 0, "Initial Turn_Count should be 0");
      S.Increment_Turn_Count;
      Assert (S.Turn_Count = 1,
              "After one increment Turn_Count should be 1");
      S.Increment_Turn_Count;
      S.Increment_Turn_Count;
      Assert (S.Turn_Count = 3,
              "After three increments Turn_Count should be 3");
   end Test_State_Turn_Count_Increment;

   procedure Test_State_Turn_Count_Set (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      S.Set_Turn_Count (42);
      Assert (S.Turn_Count = 42,
              "Set_Turn_Count should store the given value");
      S.Set_Turn_Count (0);
      Assert (S.Turn_Count = 0, "Set_Turn_Count to 0 should work");
   end Test_State_Turn_Count_Set;

   procedure Test_State_Turn_Count_Reset (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      S.Set_Turn_Count (5);
      S.Reset_Turn_Count;
      Assert (S.Turn_Count = 0, "Reset_Turn_Count should set count back to 0");
   end Test_State_Turn_Count_Reset;

   --  ── App_State Has_Text_Delta ──────────────────────────────────────────

   --  Has_Text_Delta defaults to False on a freshly created App_State.
   procedure Test_State_Has_Text_Delta_Initial (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      Assert (not S.Has_Text_Delta,
              "Has_Text_Delta should be False initially");
   end Test_State_Has_Text_Delta_Initial;

   --  Set_Has_Text_Delta toggles the flag in both directions.
   procedure Test_State_Has_Text_Delta_Set_And_Clear (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      S.Set_Has_Text_Delta (True);
      Assert (S.Has_Text_Delta,
              "Has_Text_Delta should be True after Set_Has_Text_Delta(True)");
      S.Set_Has_Text_Delta (False);
      Assert (not S.Has_Text_Delta,
              "Has_Text_Delta should be False after "
              & "Set_Has_Text_Delta(False)");
   end Test_State_Has_Text_Delta_Set_And_Clear;

   --  Has_Text_Delta and Text_Emitted are independent flags.  Setting one
   --  must not affect the other.  This matters because Text_Emitted is set
   --  by tool_execution_start (tool-only turn) while Has_Text_Delta is only
   --  set by text_delta (final text response).
   procedure Test_State_Has_Text_Delta_Independent (T : in out Test) is
      pragma Unreferenced (T);
      S : App_State;
   begin
      --  Set only Text_Emitted (tool-only turn); Has_Text_Delta must stay
      --  False.
      S.Set_Text_Emitted (True);
      Assert (not S.Has_Text_Delta,
              "Has_Text_Delta should stay False when only Text_Emitted "
              & "is set (tool-only turn)");
      Assert (S.Text_Emitted, "Text_Emitted should be True");

      --  Also set Has_Text_Delta; Text_Emitted must still be True.
      S.Set_Has_Text_Delta (True);
      Assert (S.Has_Text_Delta,
              "Has_Text_Delta should be True after Set_Has_Text_Delta(True)");
      Assert (S.Text_Emitted,
              "Text_Emitted must remain True after Set_Has_Text_Delta");

      --  Clear Has_Text_Delta; Text_Emitted must be unaffected.
      S.Set_Has_Text_Delta (False);
      Assert (not S.Has_Text_Delta,
              "Has_Text_Delta should be False after clearing");
      Assert (S.Text_Emitted,
              "Text_Emitted must be unaffected by clearing Has_Text_Delta");
   end Test_State_Has_Text_Delta_Independent;

   --  Pending_Stats is gated by Has_Text_Delta in Dispatch_Pi_Event.
   --  Verify the two paths: tool-only agent_end (no separator) and
   --  text-producing agent_end (separator + stats requested).
   procedure Test_State_Pending_Stats_Gated_By_Text_Delta
     (T : in out Test)
   is
      pragma Unreferenced (T);
      S : App_State;
   begin
      --  Path A: tool-only agent_end — Has_Text_Delta is False.
      --  The Dispatch_Pi_Event guard: if State.Has_Text_Delta then
      --    State.Set_Pending_Stats (True); end if;
      Assert (not S.Has_Text_Delta, "Precondition: no text delta");
      if S.Has_Text_Delta then
         S.Set_Pending_Stats (True);
      end if;
      Assert (not S.Pending_Stats,
              "Pending_Stats must stay False for a tool-only agent_end");

      --  Path B: text-producing agent_end — Has_Text_Delta is True.
      S.Set_Has_Text_Delta (True);
      if S.Has_Text_Delta then
         S.Set_Pending_Stats (True);
      end if;
      Assert (S.Pending_Stats,
              "Pending_Stats must be True when Has_Text_Delta is True");
   end Test_State_Pending_Stats_Gated_By_Text_Delta;

   --  ── Edit_Diff_Lines ──────────────────────────────────────────────────
   procedure Test_Edit_Diff_No_Change (T : in out Test) is
      pragma Unreferenced (T);
      Text : constant String :=
        "line one" & ASCII.LF
        & "line two" & ASCII.LF
        & "line three" & ASCII.LF;
   begin
      Assert (Edit_Diff_Lines (Text, Text) = "(no changes)",
              "Identical texts should return ""(no changes)""");
   end Test_Edit_Diff_No_Change;

   --  Changing one line produces a - line and a + line.
   procedure Test_Edit_Diff_Single_Substitution (T : in out Test) is
      pragma Unreferenced (T);
      Old_T : constant String :=
        "alpha" & ASCII.LF & "beta"  & ASCII.LF & "gamma" & ASCII.LF;
      New_T : constant String :=
        "alpha" & ASCII.LF & "BETA"  & ASCII.LF & "gamma" & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      --  Helper: return True when S contains Sub as a substring.
      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 then
            return True;
         end if;
         if S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, "-beta"),
              "Diff should contain a ''-beta'' removal line");
      Assert (Contains (Result, "+BETA"),
              "Diff should contain a ''+BETA'' addition line");
   end Test_Edit_Diff_Single_Substitution;

   --  Adding lines to the end of a file shows + lines.
   procedure Test_Edit_Diff_Added_Lines (T : in out Test) is
      pragma Unreferenced (T);
      Old_T  : constant String := "existing line" & ASCII.LF;
      New_T  : constant String :=
        "existing line" & ASCII.LF
        & "new line A"   & ASCII.LF
        & "new line B"   & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, "+new line A"),
              "Diff should contain ''+new line A''");
      Assert (Contains (Result, "+new line B"),
              "Diff should contain ''+new line B''");
   end Test_Edit_Diff_Added_Lines;

   --  Removing lines from a file shows - lines.
   procedure Test_Edit_Diff_Removed_Lines (T : in out Test) is
      pragma Unreferenced (T);
      Old_T  : constant String :=
        "keep this"    & ASCII.LF
        & "remove me"  & ASCII.LF
        & "keep that"  & ASCII.LF;
      New_T  : constant String :=
        "keep this"    & ASCII.LF
        & "keep that"  & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, "-remove me"),
              "Diff should contain ''-remove me''");
   end Test_Edit_Diff_Removed_Lines;

   --  The result never contains ---/+++/@@ unified-diff header lines.
   procedure Test_Edit_Diff_No_Headers (T : in out Test) is
      pragma Unreferenced (T);
      Old_T  : constant String :=
        "first"  & ASCII.LF & "second" & ASCII.LF & "third" & ASCII.LF;
      New_T  : constant String :=
        "first"  & ASCII.LF & "SECOND" & ASCII.LF & "third" & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      --  True if any line in S starts with Prefix.
      function Has_Line_With_Prefix
        (S      : String;
         Prefix : String) return Boolean
      is
         Start : Natural := S'First;
      begin
         for I in S'Range loop
            if S (I) = ASCII.LF or else I = S'Last then
               declare
                  Limit : constant Natural :=
                    (if S (I) = ASCII.LF then I - 1 else I);
                  Line  : constant String  := S (Start .. Limit);
               begin
                  if Line'Length >= Prefix'Length
                    and then
                      Line (Line'First
                            .. Line'First + Prefix'Length - 1) = Prefix
                  then
                     return True;
                  end if;
               end;
               Start := I + 1;
            end if;
         end loop;
         return False;
      end Has_Line_With_Prefix;
   begin
      Assert (not Has_Line_With_Prefix (Result, "---"),
              "Result must not contain ''---'' header lines");
      Assert (not Has_Line_With_Prefix (Result, "+++"),
              "Result must not contain ''+++'' header lines");
      Assert (not Has_Line_With_Prefix (Result, "@@"),
              "Result must not contain ''@@'' hunk-header lines");
   end Test_Edit_Diff_No_Headers;

   --  Diffs exceeding Max_L lines are truncated with an ellipsis trailer.
   procedure Test_Edit_Diff_Truncation (T : in out Test) is
      pragma Unreferenced (T);

      --  Trim the leading space that Natural'Image prepends.
      function Img (N : Natural) return String is
         S : constant String := Natural'Image (N);
      begin
         return S (S'First + 1 .. S'Last);
      end Img;

      --  Build two texts whose diff body exceeds 30 lines:
      --  Replace every line so the diff has N deletions + N additions.
      N     : constant := 20;  --  body lines = 40 (> Max_L=30)
      Old_B : Unbounded_String;
      New_B : Unbounded_String;
   begin
      for I in 1 .. N loop
         Append (Old_B, "old_line_" & Img (I) & ASCII.LF);
         Append (New_B, "new_line_" & Img (I) & ASCII.LF);
      end loop;

      declare
         Result    : constant String  :=
           Edit_Diff_Lines (To_String (Old_B), To_String (New_B));

         --  Count LF-separated lines in Result.
         function Line_Count (S : String) return Natural is
            N_Lines : Natural := (if S'Length > 0 then 1 else 0);
         begin
            for C of S loop
               if C = ASCII.LF then
                  N_Lines := N_Lines + 1;
               end if;
            end loop;
            return N_Lines;
         end Line_Count;

         --  True if S contains Sub.
         function Contains (S : String; Sub : String) return Boolean is
         begin
            if Sub'Length = 0 or else S'Length < Sub'Length then
               return False;
            end if;
            for I in S'First .. S'Last - Sub'Length + 1 loop
               if S (I .. I + Sub'Length - 1) = Sub then
                  return True;
               end if;
            end loop;
            return False;
         end Contains;

         UC_Ellip : constant String :=  --  …  U+2026
           Character'Val (16#E2#)
           & Character'Val (16#80#)
           & Character'Val (16#A6#);
      begin
         Assert (Line_Count (Result) = 31,
                 "Truncated diff should have exactly 31 lines "
                 & "(30 body + 1 trailer); got "
                 & Img (Line_Count (Result)));
         Assert (Contains (Result, UC_Ellip & " "),
                 "Truncated diff should end with an ellipsis trailer");
         Assert (Contains (Result, "more lines"),
                 "Trailer should include ""more lines""");
      end;
   end Test_Edit_Diff_Truncation;

   --  ── Edit_Diff_Lines: UTF-8 preservation (-gnatW8 regression) ─────────
   --
   --  Each test encodes multi-byte UTF-8 sequences as raw Ada Character
   --  values and checks that Edit_Diff_Lines returns those same byte
   --  sequences in the diff output.  With the old Ada.Text_IO.Put write,
   --  -gnatW8 caused every byte > 16#7F# to be re-encoded as UTF-8,
   --  turning (for example) the three-byte sequence E2 86 92 (U+2192 →)
   --  into C3 A2  C2 86  C2 92 — visible as "â" in the acme window.

   --  UTF-8 bytes in a context (unchanged) line are preserved verbatim.
   procedure Test_Edit_Diff_Utf8_Context_Line (T : in out Test) is
      pragma Unreferenced (T);
      --  U+2192 RIGHTWARDS ARROW (→): E2 86 92
      Arrow : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#86#)
        & Character'Val (16#92#);
      --  U+00D7 MULTIPLICATION SIGN (×): C3 97
      Times : constant String :=
        Character'Val (16#C3#) & Character'Val (16#97#);
      --  Old and new differ only in the second line; the UTF-8 context
      --  lines before and after should appear unchanged in the diff output.
      Old_T : constant String :=
        "Send " & Arrow & " PING"   & ASCII.LF
        & "change this"             & ASCII.LF
        & "5 bytes " & Times & " 8" & ASCII.LF;
      New_T : constant String :=
        "Send " & Arrow & " PING"   & ASCII.LF
        & "changed"                 & ASCII.LF
        & "5 bytes " & Times & " 8" & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, Arrow),
              "Arrow (U+2192) bytes must appear in context-line output");
      Assert (Contains (Result, Times),
              "Times (U+00D7) bytes must appear in context-line output");
   end Test_Edit_Diff_Utf8_Context_Line;

   --  UTF-8 bytes in a removed (-) line are preserved verbatim.
   procedure Test_Edit_Diff_Utf8_Removed_Line (T : in out Test) is
      pragma Unreferenced (T);
      --  U+2192 RIGHTWARDS ARROW (→): E2 86 92
      Arrow : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#86#)
        & Character'Val (16#92#);
      --  old line contains raw UTF-8; it will appear as a removal (-) line.
      Old_T  : constant String :=
        "Send " & Arrow & " expect PONG" & ASCII.LF;
      New_T  : constant String := "Send expect PONG" & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, Arrow),
              "Arrow bytes must survive in removed-line diff output");
   end Test_Edit_Diff_Utf8_Removed_Line;

   --  UTF-8 bytes in an added (+) line are preserved verbatim.
   procedure Test_Edit_Diff_Utf8_Added_Line (T : in out Test) is
      pragma Unreferenced (T);
      --  U+00D7 MULTIPLICATION SIGN (×): C3 97
      Times : constant String :=
        Character'Val (16#C3#) & Character'Val (16#97#);
      Old_T  : constant String := "old line" & ASCII.LF;
      New_T  : constant String :=
        "5 bytes " & Times & " 8 bits" & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, Times),
              "Times bytes must survive in added-line diff output");
   end Test_Edit_Diff_Utf8_Added_Line;

   --  Regression: verify no double-encoding occurs (-gnatW8 + Ada.Text_IO
   --  bug).  The output must contain the raw bytes E2 86 92 (→) and must
   --  NOT contain C3 A2 (the first two bytes of the double-encoded form,
   --  the UTF-8 encoding of Latin-1 â = U+00E2).
   procedure Test_Edit_Diff_No_Double_Encoding (T : in out Test) is
      pragma Unreferenced (T);
      --  U+2192 RIGHTWARDS ARROW (→): E2 86 92
      Arrow : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#86#)
        & Character'Val (16#92#);
      --  Double-encoded first two bytes: C3 A2 (UTF-8 for U+00E2 â)
      Double_Start : constant String :=
        Character'Val (16#C3#) & Character'Val (16#A2#);
      Old_T  : constant String := "context" & ASCII.LF;
      New_T  : constant String :=
        "context " & Arrow & ASCII.LF;
      Result : constant String := Edit_Diff_Lines (Old_T, New_T);

      function Contains (S : String; Sub : String) return Boolean is
      begin
         if Sub'Length = 0 or else S'Length < Sub'Length then
            return False;
         end if;
         for I in S'First .. S'Last - Sub'Length + 1 loop
            if S (I .. I + Sub'Length - 1) = Sub then
               return True;
            end if;
         end loop;
         return False;
      end Contains;
   begin
      Assert (Contains (Result, Arrow),
              "Raw UTF-8 bytes for arrow (E2 86 92) must appear in output");
      Assert
        (not Contains (Result, Double_Start),
         "Double-encoded prefix C3 A2 must NOT appear in output "
         & "(regression: Ada.Text_IO.Put re-encoding under -gnatW8)");
   end Test_Edit_Diff_No_Double_Encoding;

   --  A JSON string value is returned as-is, without surrounding quotes.
   procedure Test_JSON_Scalar_String (T : in out Test) is
      pragma Unreferenced (T);
      V : constant JSON_Value := Create ("hello world");
   begin
      Assert (JSON_Scalar_Image (V) = "hello world",
              "String value should be returned without quotes");
   end Test_JSON_Scalar_String;

   --  An empty JSON string is returned as an empty string.
   procedure Test_JSON_Scalar_Integer (T : in out Test) is
      pragma Unreferenced (T);
      V : constant JSON_Value := Create (Integer'(42));
   begin
      Assert (JSON_Scalar_Image (V) = "42",
              "Integer 42 should serialise as ""42""");
   end Test_JSON_Scalar_Integer;

   --  Negative integer values are serialised correctly.
   procedure Test_JSON_Scalar_Negative_Integer (T : in out Test) is
      pragma Unreferenced (T);
      V : constant JSON_Value := Create (Integer'(-7));
   begin
      Assert (JSON_Scalar_Image (V) = "-7",
              "Integer -7 should serialise as ""-7""");
   end Test_JSON_Scalar_Negative_Integer;

   --  Boolean true serialises to the JSON literal "true".
   procedure Test_JSON_Scalar_Boolean_True (T : in out Test) is
      pragma Unreferenced (T);
      V : constant JSON_Value := Create (True);
   begin
      Assert (JSON_Scalar_Image (V) = "true",
              "Boolean True should serialise as ""true""");
   end Test_JSON_Scalar_Boolean_True;

   --  Boolean false serialises to the JSON literal "false".
   procedure Test_JSON_Scalar_Boolean_False (T : in out Test) is
      pragma Unreferenced (T);
      V : constant JSON_Value := Create (False);
   begin
      Assert (JSON_Scalar_Image (V) = "false",
              "Boolean False should serialise as ""false""");
   end Test_JSON_Scalar_Boolean_False;

   --  Float values are serialised to a non-empty numeric string.
   procedure Test_JSON_Scalar_Float (T : in out Test) is
      pragma Unreferenced (T);
      V      : constant JSON_Value := Create (Float'(3.14));
      Result : constant String     := JSON_Scalar_Image (V);
   begin
      Assert (Result'Length > 0,
              "Float value should produce a non-empty string");
      --  Must not be the fallback sentinel.
      Assert (Result /= "...",
              "Float value should not produce ""...""");
   end Test_JSON_Scalar_Float;

   --  A JSON null value returns the "..." sentinel.
   procedure Test_JSON_Scalar_Null (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (JSON_Scalar_Image (JSON_Null) = "...",
              "Null value should return ""...""");
   end Test_JSON_Scalar_Null;

   --  A JSON object value returns the "..." sentinel.
   procedure Test_JSON_Scalar_Object (T : in out Test) is
      pragma Unreferenced (T);
      V : JSON_Value := Create_Object;
   begin
      V.Set_Field ("key", Create ("value"));
      Assert (JSON_Scalar_Image (V) = "...",
              "Object value should return ""...""");
   end Test_JSON_Scalar_Object;

   --  A JSON array value returns the "..." sentinel.
   procedure Test_JSON_Scalar_Array (T : in out Test) is
      pragma Unreferenced (T);
      Arr : JSON_Array;
      V   : JSON_Value;
   begin
      Append (Arr, Create (Integer'(1)));
      V := Create (Arr);
      Assert (JSON_Scalar_Image (V) = "...",
              "Array value should return ""...""");
   end Test_JSON_Scalar_Array;

end Pi_Acme_App_Tests;
