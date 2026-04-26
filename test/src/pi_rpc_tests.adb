with AUnit.Assertions;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;   use GNATCOLL.OS.Process;
with Pi_RPC;                use Pi_RPC;

package body Pi_RPC_Tests is

   use AUnit.Assertions;

   --  ── Helper: spawn a shell command, return a Pi_RPC.Process ───────────

   function Spawn_Shell (Cmd : String) return Pi_RPC.Process is
      use GNATCOLL.OS.FS;
      use GNATCOLL.OS.Process;
      Stdin_R,  Stdin_W  : File_Descriptor;
      Stdout_R, Stdout_W : File_Descriptor;
      Stderr_R, Stderr_W : File_Descriptor;
      Args : Argument_List;
      H    : Process_Handle;
   begin
      Open_Pipe (Stdin_R,  Stdin_W);
      Open_Pipe (Stdout_R, Stdout_W);
      Open_Pipe (Stderr_R, Stderr_W);
      Args.Append ("/bin/sh");
      Args.Append ("-c");
      Args.Append (Cmd);
      H := Start (Args   => Args,
                  Stdin  => Stdin_R,
                  Stdout => Stdout_W,
                  Stderr => Stderr_W);
      Close (Stdin_R);
      Close (Stdout_W);
      Close (Stderr_W);
      return From_FDs (H, Stdin_W, Stdout_R, Stderr_R);
   end Spawn_Shell;

   --  ── Find_Pi ───────────────────────────────────────────────────────────

   procedure Test_Find_Pi_Non_Empty (T : in out Test) is
      pragma Unreferenced (T);
      Path : constant String := Find_Pi;
   begin
      Assert (Path'Length > 0,
              "Find_Pi should return a non-empty string");
   end Test_Find_Pi_Non_Empty;

   --  ── Subprocess I/O ───────────────────────────────────────────────────

   procedure Test_Spawn_Echo (T : in out Test) is
      pragma Unreferenced (T);
      P    : Pi_RPC.Process := Spawn_Shell ("echo hello");
      Line : constant String := Read_Line (P);
   begin
      Assert (Line = "hello",
              "Read_Line should return 'hello', got: '" & Line & "'");
   end Test_Spawn_Echo;

   procedure Test_Read_Multiple_Lines (T : in out Test) is
      pragma Unreferenced (T);
      P  : Pi_RPC.Process := Spawn_Shell ("printf 'one\ntwo\nthree\n'");
      L1 : constant String := Read_Line (P);
      L2 : constant String := Read_Line (P);
      L3 : constant String := Read_Line (P);
   begin
      Assert (L1 = "one",   "Line 1 should be 'one'");
      Assert (L2 = "two",   "Line 2 should be 'two'");
      Assert (L3 = "three", "Line 3 should be 'three'");
   end Test_Read_Multiple_Lines;

   procedure Test_Stderr_Capture (T : in out Test) is
      pragma Unreferenced (T);
      P    : Pi_RPC.Process := Spawn_Shell ("echo err-msg >&2");
      Line : constant String := Read_Stderr_Line (P);
   begin
      Assert (Line = "err-msg",
              "Stderr line should be 'err-msg', got: '" & Line & "'");
   end Test_Stderr_Capture;

   procedure Test_Process_Exits (T : in out Test) is
      pragma Unreferenced (T);
      P     : Pi_RPC.Process := Spawn_Shell ("true");
      Dummy : constant String := Read_Line (P);
      pragma Unreferenced (Dummy);
   begin
      delay 0.1;
      Assert (not Is_Alive (P),
              "Process should have exited after 'true' completes");
   end Test_Process_Exits;

   procedure Test_Send_To_Cat (T : in out Test) is
      pragma Unreferenced (T);
      P  : Pi_RPC.Process := Spawn_Shell ("cat");
      L1 : constant String := "";
      L2 : constant String := "";
      pragma Unreferenced (L1, L2);
   begin
      Send (P, "first line");
      Send (P, "second line");
      --  Close stdin so cat gets EOF and flushes.
      Close_Stdin (P);
      Assert (Read_Line (P) = "first line",
              "cat should echo 'first line'");
      Assert (Read_Line (P) = "second line",
              "cat should echo 'second line'");
   end Test_Send_To_Cat;

   --  ── Regression / edge-case tests ─────────────────────────────────────

   procedure Test_Read_Very_Long_Line (T : in out Test) is
      pragma Unreferenced (T);
      --  Regression: the old Next_Line called To_String (Buffer) on every
      --  iteration, copying the entire accumulated buffer onto the GNAT
      --  secondary stack.  A 1 MiB line caused STORAGE_ERROR via SIGSEGV
      --  converted by the s-intman signal handler.  The fix uses
      --  Ada.Strings.Unbounded.Index / Slice / Delete so the full buffer is
      --  never materialised on the stack.
      Expected_Length : constant := 1_048_576;
      P    : Pi_RPC.Process :=
               Spawn_Shell ("python3 -c ""print('a' * 1048576)""");
      Line : constant String := Read_Line (P);
   begin
      Assert
        (Line'Length = Expected_Length,
         "Very long line: expected length"
         & Expected_Length'Image
         & ", got" & Line'Length'Image);
   end Test_Read_Very_Long_Line;

   procedure Test_Read_No_Trailing_Newline (T : in out Test) is
      pragma Unreferenced (T);
      --  When a process writes content and exits without a final newline,
      --  Read_Line must return the partial content rather than dropping it.
      P    : Pi_RPC.Process := Spawn_Shell ("printf 'no-newline'");
      Line : constant String := Read_Line (P);
   begin
      Assert
        (Line = "no-newline",
         "Partial line at EOF should be returned, got: '" & Line & "'");
   end Test_Read_No_Trailing_Newline;

end Pi_RPC_Tests;
