with AUnit;
with AUnit.Test_Fixtures;

--  Integration tests for the Pi_RPC JSON-RPC interface using the
--  github-copilot/gpt-5-mini model (free tier, no cost).
--
--  Each test starts a fresh pi subprocess and interacts with it via
--  the Pi_RPC package.  Tests time out after 30 seconds if the model
--  does not respond.

package Pi_Interface_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  RPC layer
   procedure Test_Get_State          (T : in out Test);
   procedure Test_Model_Select_Event (T : in out Test);

   --  Prompt / response
   procedure Test_Simple_Prompt      (T : in out Test);
   procedure Test_Abort              (T : in out Test);

   --  JSON event parsing
   procedure Test_Message_End_Tokens (T : in out Test);

   --  Pi_RPC.Restart
   procedure Test_Restart            (T : in out Test);

end Pi_Interface_Tests;
