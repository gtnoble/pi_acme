with AUnit;
with AUnit.Test_Fixtures;

package Acme_Integration_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_New_Win_Has_Valid_Id  (T : in out Test);
   procedure Test_Append_Visible_Via_9p (T : in out Test);
   procedure Test_Set_Name             (T : in out Test);
   procedure Test_Selection_Empty      (T : in out Test);
   procedure Test_Raw_Event_From_Live  (T : in out Test);

   --  Replace_Match tests
   procedure Test_Replace_Match_Simple           (T : in out Test);
   procedure Test_Replace_Match_No_Match         (T : in out Test);
   procedure Test_Replace_Match_Parallel_Blocks  (T : in out Test);

   --  Clear tag-command behaviour
   --
   --  These tests verify the two-step sequence used by the Clear tag
   --  command: Replace_Match ("1,$", "") erases the body, then Append
   --  writes the new status line.  They guard against regression to the
   --  previous broken implementation that called Ctl ("addr 1,$") and
   --  Ctl ("data"), which wrote to the ctl file and had no effect on the
   --  body.
   procedure Test_Clear_Body_Erases_Content  (T : in out Test);
   procedure Test_Clear_Body_Restores_Status (T : in out Test);
   procedure Test_Clear_Body_On_Empty_Body   (T : in out Test);

   --  Live end-of-turn footer helper used by get_session_stats responses.
   procedure Test_Append_Live_Turn_Footer          (T : in out Test);
   --  Same helper with non-zero cost fields — verifies "$X.XXXX turn" and
   --  "$X.XXXX session" segments appear in the footer body.
   procedure Test_Append_Live_Turn_Footer_With_Cost (T : in out Test);

end Acme_Integration_Tests;
