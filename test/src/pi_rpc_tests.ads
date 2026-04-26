with AUnit;
with AUnit.Test_Fixtures;

package Pi_RPC_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Find_Pi (pure search, no subprocess)
   procedure Test_Find_Pi_Non_Empty      (T : in out Test);

   --  Subprocess I/O via real processes
   procedure Test_Spawn_Echo             (T : in out Test);
   procedure Test_Read_Multiple_Lines    (T : in out Test);
   procedure Test_Stderr_Capture         (T : in out Test);
   procedure Test_Process_Exits          (T : in out Test);
   procedure Test_Send_To_Cat            (T : in out Test);

   --  Regression / edge-case tests for Next_Line
   procedure Test_Read_Very_Long_Line    (T : in out Test);
   --  Read_Line must return partial content when a process exits without
   --  writing a final newline.
   procedure Test_Read_No_Trailing_Newline (T : in out Test);

end Pi_RPC_Tests;
