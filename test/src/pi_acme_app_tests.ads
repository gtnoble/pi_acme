with AUnit;
with AUnit.Test_Fixtures;

package Pi_Acme_App_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  App_State protected type
   procedure Test_State_Model         (T : in out Test);
   procedure Test_State_Streaming     (T : in out Test);
   procedure Test_State_Tokens        (T : in out Test);
   procedure Test_State_Shutdown      (T : in out Test);
   procedure Test_State_Session_Id    (T : in out Test);

   --  App_State session reload coordination
   procedure Test_State_Request_Consume_Reload  (T : in out Test);
   procedure Test_State_Consume_Clears_Flag     (T : in out Test);
   procedure Test_State_Restart_Done            (T : in out Test);
   procedure Test_State_Restart_Aborted         (T : in out Test);
   procedure Test_State_Reload_Cycle            (T : in out Test);

   --  Nth_Field string utility
   procedure Test_Nth_Field_Basic     (T : in out Test);
   procedure Test_Nth_Field_Tabs      (T : in out Test);
   procedure Test_Nth_Field_Edges     (T : in out Test);

   --  Parse_Session_Token
   procedure Test_Parse_Token_Pid_Match    (T : in out Test);
   procedure Test_Parse_Token_Pid_Mismatch (T : in out Test);
   procedure Test_Parse_Token_Bare         (T : in out Test);
   procedure Test_Parse_Token_Other_Pid    (T : in out Test);
   procedure Test_Parse_Token_Empty        (T : in out Test);
   procedure Test_Parse_Token_Non_Token    (T : in out Test);

   --  App_State Turn_Count
   procedure Test_State_Turn_Count_Increment (T : in out Test);
   procedure Test_State_Turn_Count_Set       (T : in out Test);
   procedure Test_State_Turn_Count_Reset     (T : in out Test);

   --  App_State Is_Retrying — tracks whether an auto-retry sequence is in
   --  flight.  Set by auto_retry_start, cleared by auto_retry_end and
   --  explicit reset points (new_session, session reload).  Used in
   --  agent_end to suppress the repeated "No response" message.
   procedure Test_State_Is_Retrying_Initial     (T : in out Test);
   procedure Test_State_Is_Retrying_Set_And_Clear (T : in out Test);
   procedure Test_State_Is_Retrying_Independent (T : in out Test);

   --  App_State Has_Text_Delta — tracks whether a text_delta arrived in the
   --  current agent turn.
   procedure Test_State_Has_Text_Delta_Initial             (T : in out Test);
   procedure Test_State_Has_Text_Delta_Set_And_Clear       (T : in out Test);
   procedure Test_State_Has_Text_Delta_Independent         (T : in out Test);

   --  App_State Last_Stop_Reason — stopReason from the last assistant
   --  message_end in the current agent run.  "stop"/"length" means the
   --  agent's final LLM call produced a text response; "toolUse" means an
   --  intermediate tool-calling turn (should not occur at agent_end).
   --  Resets to "" at agent_start.  Used to gate the turn footer and stats
   --  request in the agent_end handler.
   procedure Test_State_Last_Stop_Reason_Initial           (T : in out Test);
   procedure Test_State_Last_Stop_Reason_Round_Trip        (T : in out Test);
   procedure Test_State_Last_Stop_Reason_Independent       (T : in out Test);

   --  App_State Last_Error_Message — errorMessage from the last assistant
   --  message_end with stopReason "error".  Empty when the last turn did not
   --  produce an error, or when pi did not supply a message.
   procedure Test_State_Last_Error_Message_Initial         (T : in out Test);
   procedure Test_State_Last_Error_Message_Round_Trip      (T : in out Test);

   --  Pending_Stats is gated by Last_Stop_Reason in Dispatch_Pi_Event.
   --  "stop" and "length" trigger the footer; other reasons do not.
   procedure Test_State_Pending_Stats_Gated_By_Stop_Reason (T : in out Test);

   --  App_State Models_Pending — set by Acme_Event_Task when the Models
   --  tag command is pressed; cleared by Dispatch_Pi_Event when the
   --  get_available_models response arrives and the +models window is opened.
   procedure Test_State_Models_Pending_Initial           (T : in out Test);
   procedure Test_State_Models_Pending_Set_And_Clear     (T : in out Test);
   procedure Test_State_Models_Pending_Independent       (T : in out Test);

   --  Edit_Diff_Lines
   procedure Test_Edit_Diff_No_Change          (T : in out Test);
   procedure Test_Edit_Diff_Single_Substitution (T : in out Test);
   procedure Test_Edit_Diff_Added_Lines        (T : in out Test);
   procedure Test_Edit_Diff_Removed_Lines      (T : in out Test);
   procedure Test_Edit_Diff_No_Headers         (T : in out Test);
   procedure Test_Edit_Diff_Truncation         (T : in out Test);

   --  Edit_Diff_Lines: UTF-8 preservation (-gnatW8 regression)
   --
   --  These tests guard against double-encoding: with -gnatW8, Ada.Text_IO
   --  re-encodes each Latin-1 byte > 16#7F# as UTF-8, turning already-UTF-8
   --  file content into mojibake.  The fix uses Ada.Streams.Stream_IO for
   --  binary temp-file writes; these tests verify that the raw UTF-8 byte
   --  sequences are preserved intact through Edit_Diff_Lines.
   procedure Test_Edit_Diff_Utf8_Context_Line  (T : in out Test);
   procedure Test_Edit_Diff_Utf8_Removed_Line  (T : in out Test);
   procedure Test_Edit_Diff_Utf8_Added_Line    (T : in out Test);
   procedure Test_Edit_Diff_No_Double_Encoding (T : in out Test);

   --  Model in stats summary line
   --  Verify the App_State accessor that gates the model part in the
   --  get_session_stats summary appended at the end of each agentic turn.
   procedure Test_Stats_Model_Part_When_Set   (T : in out Test);
   procedure Test_Stats_Model_Part_When_Empty (T : in out Test);

   --  App_State cost fields
   procedure Test_State_Turn_Cost_Initial       (T : in out Test);
   procedure Test_State_Turn_Cost_Round_Trip    (T : in out Test);
   procedure Test_State_Session_Stats_Initial   (T : in out Test);
   procedure Test_State_Session_Stats_Round_Trip (T : in out Test);
   procedure Test_State_Session_Stats_Reset     (T : in out Test);
   procedure Test_State_Cost_Independent_Of_Tokens (T : in out Test);

   --  JSON_Scalar_Image
   procedure Test_JSON_Scalar_String           (T : in out Test);
   procedure Test_JSON_Scalar_Integer          (T : in out Test);
   procedure Test_JSON_Scalar_Negative_Integer (T : in out Test);
   procedure Test_JSON_Scalar_Boolean_True     (T : in out Test);
   procedure Test_JSON_Scalar_Boolean_False    (T : in out Test);
   procedure Test_JSON_Scalar_Float            (T : in out Test);
   procedure Test_JSON_Scalar_Null             (T : in out Test);
   procedure Test_JSON_Scalar_Object           (T : in out Test);
   procedure Test_JSON_Scalar_Array            (T : in out Test);

   procedure Test_One_Shot_Result_Initial          (T : in out Test);
   procedure Test_One_Shot_Result_First_Write_Wins (T : in out Test);

   --  ── Format_Tool_Field ─────────────────────────────────────────────────

   procedure Test_Format_Tool_Field_Single_Line   (T : in out Test);
   --  Single-line value: returns "│ name: value" with no embedded LF.

   procedure Test_Format_Tool_Field_Two_Lines     (T : in out Test);
   --  Value with one LF: first line has label; second line has │ only.

   procedure Test_Format_Tool_Field_Three_Lines   (T : in out Test);
   --  Value with two LFs: all three lines carry the │ border.

   procedure Test_Format_Tool_Field_Trailing_LF   (T : in out Test);
   --  Value ending with LF: produces a blank-body continuation line.

   procedure Test_Format_Tool_Field_Empty_Value   (T : in out Test);
   --  Empty value: returns "│ name: " (label with no value text).

   procedure Test_Format_Tool_Field_Truncation    (T : in out Test);
   --  Value longer than Max_Len is truncated and ends with "…".

   --  ── Format_Kilo ───────────────────────────────────────────────────────
   --  Format_Kilo formats a Natural as a compact kilo string.
   --  Values below 1000 are returned as plain decimal; values >= 1000 are
   --  expressed as Nk (whole) or N.Mk (with fractional tenth).

   procedure Test_Format_Kilo_Below_Threshold (T : in out Test);
   procedure Test_Format_Kilo_Round_Numbers   (T : in out Test);
   procedure Test_Format_Kilo_Fractional      (T : in out Test);

   --  ── Format_Cost ───────────────────────────────────────────────────────
   --  Format_Cost converts an integer in units of $0.0001 (dmil) to
   --  a "$D.FFFF" string.  0 → "$0.0000"; 12345 → "$1.2345".

   procedure Test_Format_Cost_Zero       (T : in out Test);
   procedure Test_Format_Cost_Fractional (T : in out Test);
   procedure Test_Format_Cost_Dollars    (T : in out Test);

   --  ── Agent_Stem ────────────────────────────────────────────────────────
   --  Agent_Stem extracts the basename of an agent path, stripping the
   --  ".agent.md" suffix when present.

   procedure Test_Agent_Stem_With_Extension (T : in out Test);
   procedure Test_Agent_Stem_No_Extension   (T : in out Test);

   --  ── Extract_Plumb_Data ────────────────────────────────────────────────
   --  Extract_Plumb_Data parses a 7-field newline-delimited plumb message
   --  and returns the data field, clipped to ndata bytes so that any
   --  trailing newline added by the plumber is stripped.

   procedure Test_Extract_Plumb_Data_Basic                (T : in out Test);
   procedure Test_Extract_Plumb_Data_Strips_Trailing_LF   (T : in out Test);
   procedure Test_Extract_Plumb_Data_Too_Few_Fields        (T : in out Test);
   procedure Test_Extract_Plumb_Data_Empty                (T : in out Test);

   --  ── Get_Cost_Dmil ────────────────────────────────────────────────────
   --  Get_Cost_Dmil reads a JSON float or integer cost field and converts
   --  it to integer dmil units ($0.0001) using round-half-up arithmetic.
   --  Returns 0 for absent, zero, or negative values.

   procedure Test_Get_Cost_Dmil_Float_Value    (T : in out Test);
   procedure Test_Get_Cost_Dmil_Zero_Float     (T : in out Test);
   procedure Test_Get_Cost_Dmil_Integer_Zero   (T : in out Test);
   procedure Test_Get_Cost_Dmil_Absent_Field   (T : in out Test);
   procedure Test_Get_Cost_Dmil_Negative_Float (T : in out Test);

   --  ── Format_Status ─────────────────────────────────────────────────────
   --  Format_Status builds the one-line status string placed in the first
   --  body line of the +pi window.  Parts (model, agent, thinking, context,
   --  session) are included only when the corresponding App_State fields
   --  are populated.

   procedure Test_Format_Status_Default        (T : in out Test);
   procedure Test_Format_Status_Custom_Extra   (T : in out Test);
   procedure Test_Format_Status_With_Model     (T : in out Test);
   procedure Test_Format_Status_With_Session   (T : in out Test);
   procedure Test_Format_Status_With_Context   (T : in out Test);
   procedure Test_Format_Status_With_Thinking  (T : in out Test);

end Pi_Acme_App_Tests;
