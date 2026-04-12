with AUnit;
with AUnit.Test_Fixtures;

package Acme_Raw_Events_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Single events
   procedure Test_Simple_Execute     (T : in out Test);
   procedure Test_Simple_Look        (T : in out Test);
   procedure Test_Keyboard_Insert    (T : in out Test);
   procedure Test_Multi_Digit_Pos    (T : in out Test);

   --  Expansion (flag & 2)
   procedure Test_Flag2_Expansion    (T : in out Test);

   --  Chorded arg (flag & 8)
   procedure Test_Flag8_Chorded      (T : in out Test);

   --  Buffer management
   procedure Test_Incremental_Feed   (T : in out Test);
   procedure Test_Two_Events_One_Feed (T : in out Test);
   procedure Test_Incomplete_Returns_False (T : in out Test);

end Acme_Raw_Events_Tests;
