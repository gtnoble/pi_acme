with AUnit;
with AUnit.Test_Fixtures;

package Acme_Integration_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_New_Win_Has_Valid_Id  (T : in out Test);
   procedure Test_Append_Visible_Via_9p (T : in out Test);
   procedure Test_Set_Name             (T : in out Test);
   procedure Test_Selection_Empty      (T : in out Test);
   procedure Test_Raw_Event_From_Live  (T : in out Test);

end Acme_Integration_Tests;
