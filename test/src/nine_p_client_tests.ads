with AUnit;
with AUnit.Test_Fixtures;

package Nine_P_Client_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Namespace function
   procedure Test_Namespace_Uses_Env      (T : in out Test);
   procedure Test_Namespace_Fallback      (T : in out Test);

   --  Stream-level framing (no socket required)
   procedure Test_Read_Write_Message      (T : in out Test);
   procedure Test_Read_Message_Framing    (T : in out Test);

end Nine_P_Client_Tests;
