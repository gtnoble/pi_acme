with AUnit;
with AUnit.Test_Fixtures;

package Acme_Event_Parser_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Rc-token parsing
   procedure Test_Unquoted_Token    (T : in out Test);
   procedure Test_Quoted_Token      (T : in out Test);
   procedure Test_Escaped_Quote     (T : in out Test);

   --  Full event line parsing
   procedure Test_Parse_Execute     (T : in out Test);
   procedure Test_Parse_Look        (T : in out Test);
   procedure Test_Parse_Quoted_Text (T : in out Test);
   procedure Test_Parse_Invalid     (T : in out Test);
   procedure Test_Parse_Empty       (T : in out Test);

end Acme_Event_Parser_Tests;
