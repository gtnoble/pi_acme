with AUnit;
with AUnit.Test_Fixtures;

package Session_Lister_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Pure functions (no filesystem)
   procedure Test_Encode_Cwd_Absolute   (T : in out Test);
   procedure Test_Encode_Cwd_Relative   (T : in out Test);
   procedure Test_Encode_Cwd_Empty      (T : in out Test);
   procedure Test_Format_Timestamp      (T : in out Test);
   procedure Test_Format_Timestamp_Short (T : in out Test);

   --  Parse_Session_File (writes a temp file)
   procedure Test_Parse_Session_Full     (T : in out Test);
   procedure Test_Parse_Session_No_Name  (T : in out Test);
   procedure Test_Parse_Session_Bad_Json (T : in out Test);
   procedure Test_Parse_Session_Long_Line (T : in out Test);
   --  ^ Regression test: Parse_Session_File must not raise STORAGE_ERROR
   --    when a JSONL line exceeds GNAT's internal Get_Line stack buffer.

   --  Find_Session_File (creates temp files under $HOME/.pi/agent/sessions/)
   procedure Test_Find_Session_File_Found     (T : in out Test);
   procedure Test_Find_Session_File_Not_Found (T : in out Test);
   procedure Test_Find_Session_File_Any_Dir   (T : in out Test);

   --  Fork_Session (creates source + target session files)
   procedure Test_Fork_Session_One_Turn     (T : in out Test);
   procedure Test_Fork_Session_Second_Turn  (T : in out Test);
   procedure Test_Fork_Session_Beyond_End   (T : in out Test);
   procedure Test_Fork_Session_Missing_Src  (T : in out Test);

end Session_Lister_Tests;
