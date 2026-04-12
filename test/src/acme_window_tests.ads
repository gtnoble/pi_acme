with AUnit;
with AUnit.Test_Fixtures;

package Acme_Window_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Pure path-generation helpers (no live acme connection)
   procedure Test_Win_File_Path     (T : in out Test);
   procedure Test_Event_Path        (T : in out Test);
   procedure Test_Win_File_Path_Id1 (T : in out Test);

end Acme_Window_Tests;
