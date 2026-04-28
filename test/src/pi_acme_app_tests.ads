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
   --  current agent turn; used to gate the turn separator on agent_end so
   --  that tool-only (or error/retry) turns do not emit a spurious separator.
   procedure Test_State_Has_Text_Delta_Initial             (T : in out Test);
   procedure Test_State_Has_Text_Delta_Set_And_Clear       (T : in out Test);
   procedure Test_State_Has_Text_Delta_Independent         (T : in out Test);
   procedure Test_State_Pending_Stats_Gated_By_Text_Delta  (T : in out Test);

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

end Pi_Acme_App_Tests;
