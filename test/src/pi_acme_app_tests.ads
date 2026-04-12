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

end Pi_Acme_App_Tests;
