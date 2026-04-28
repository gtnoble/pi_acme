with AUnit.Assertions;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with GNATCOLL.JSON;           use GNATCOLL.JSON;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;     use GNATCOLL.OS.Process;
with Nine_P.Client;

package body Subagent_Integration_Tests is

   use AUnit.Assertions;

   Model : constant String := "github-copilot/gpt-5-mini";

   --  ── Helpers ──────────────────────────────────────────────────────────

   --  True when the acme 9P server socket is present in the namespace.
   function Acme_Running return Boolean is
   begin
      return Ada.Directories.Exists
               (Nine_P.Client.Namespace & "/acme");
   exception
      when others => return False;
   end Acme_Running;

   --  Locate the pi_acme binary under test.  Checks ../bin/pi_acme
   --  relative to the test working directory first, then the PI_ACME_BIN
   --  environment variable.  Returns "" when the binary cannot be found.
   function Find_Pi_Acme return String is
      Candidate : constant String := "../bin/pi_acme";
   begin
      if Ada.Directories.Exists (Candidate) then
         return Candidate;
      end if;
      declare
         Env_Bin : constant String :=
           Ada.Environment_Variables.Value ("PI_ACME_BIN", "");
      begin
         if Env_Bin'Length > 0
           and then Ada.Directories.Exists (Env_Bin)
         then
            return Env_Bin;
         end if;
      end;
      return "";
   end Find_Pi_Acme;

   --  Return everything before the first newline in S, or S itself when
   --  no newline is present.
   function First_Line (S : String) return String is
   begin
      for I in S'Range loop
         if S (I) = ASCII.LF then
            return S (S'First .. I - 1);
         end if;
      end loop;
      return S;
   end First_Line;

   --  Extract a string field from a JSON object value.  Returns "" on
   --  any type mismatch or missing field rather than raising an exception,
   --  so callers can assert on the result instead of catching errors.
   function Json_Str
     (V : JSON_Value;
      F : UTF8_String) return String
   is
   begin
      if V.Kind /= JSON_Object_Type then
         return "";
      end if;
      if V.Has_Field (F)
        and then V.Get (F).Kind = JSON_String_Type
      then
         return V.Get (F).Get;
      end if;
      return "";
   end Json_Str;

   --  Synchronisation flag: the Reader task signals this once the
   --  subprocess has exited and its output has been captured.  The main
   --  task uses select/or delay to impose a wall-clock timeout.
   protected type Done_Flag is
      procedure Signal;
      entry     Wait;
   private
      Complete : Boolean := False;
   end Done_Flag;

   protected body Done_Flag is
      procedure Signal is
      begin
         Complete := True;
      end Signal;

      entry Wait when Complete is
      begin
         null;
      end Wait;
   end Done_Flag;

   --  ── Test_One_Shot_Returns_Json ────────────────────────────────────────
   --
   --  Verifies the complete happy path: pi_acme --one-shot prints one JSON
   --  line whose "output" field contains "PONG" and whose "session_id" is
   --  a 36-character UUID.

   procedure Test_One_Shot_Returns_Json (T : in out Test) is
      pragma Unreferenced (T);

      Pi_Acme    : constant String := Find_Pi_Acme;
      Stdout_Out : Unbounded_String;
      Got_Result : Boolean         := False;
      Flag       : Done_Flag;

      task Runner;
      task body Runner is
         use GNATCOLL.OS.FS;
         Stdout_R, Stdout_W : File_Descriptor;
         Null_In            : File_Descriptor;
         Null_Err           : File_Descriptor;
         Args               : Argument_List;
         Handle             : Process_Handle;
         Exit_Code          : Integer;
         pragma Unreferenced (Exit_Code);
      begin
         Open_Pipe (Stdout_R, Stdout_W);
         Null_In  := Open (Null_File, Read_Mode);
         Null_Err := Open (Null_File, Write_Mode);
         Args.Append (Pi_Acme);
         Args.Append ("--one-shot");
         Args.Append ("--model");
         Args.Append (Model);
         Args.Append ("--prompt");
         Args.Append
           ("Reply with only the word PONG and nothing else.");
         Handle := Start
           (Args   => Args,
            Stdin  => Null_In,
            Stdout => Stdout_W,
            Stderr => Null_Err,
            Cwd    => Ada.Directories.Current_Directory);
         Close (Null_In);
         Close (Null_Err);
         Close (Stdout_W);
         Stdout_Out := GNATCOLL.OS.FS.Read (Stdout_R);
         Close (Stdout_R);
         Exit_Code  := Wait (Handle);
         Got_Result := True;
         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Runner;

   begin
      if not Acme_Running then
         return;
      end if;
      if Pi_Acme'Length = 0 then
         Assert (False, "pi_acme binary not found at ../bin/pi_acme");
         return;
      end if;

      select
         Flag.Wait;
      or
         delay 60.0;
      end select;

      Assert (Got_Result,
              "One-shot subprocess must complete within 60 s");
      declare
         Raw : constant String :=
           First_Line (To_String (Stdout_Out));
         R   : constant Read_Result := Read (Raw);
      begin
         Assert (R.Success,
                 "stdout must be valid JSON, got: " & Raw);
         declare
            Output_Text : constant String :=
              Json_Str (R.Value, "output");
            Session_Id  : constant String :=
              Json_Str (R.Value, "session_id");
         begin
            Assert
              (Output_Text'Length > 0,
               "JSON must have a non-empty ""output"" field");
            Assert
              (Ada.Strings.Fixed.Index (Output_Text, "PONG") > 0,
               "output should contain ""PONG"", got: " & Output_Text);
            Assert
              (Session_Id'Length = 36,
               "session_id must be a 36-character UUID, got: "
               & Session_Id);
         end;
      end;
   end Test_One_Shot_Returns_Json;

   --  ── Test_One_Shot_Fresh_Session_Each_Run ─────────────────────────────
   --
   --  Verifies that --one-shot implies --no-session: two consecutive
   --  invocations each start a fresh pi session, so the returned
   --  session_id values must differ.

   procedure Test_One_Shot_Fresh_Session_Each_Run (T : in out Test) is
      pragma Unreferenced (T);

      Pi_Acme : constant String := Find_Pi_Acme;
      Out_1   : Unbounded_String;
      Out_2   : Unbounded_String;
      Done_1  : Boolean         := False;
      Done_2  : Boolean         := False;
      Flag    : Done_Flag;

      --  Invoke pi_acme --one-shot once and store stdout in Result.
      --  Sets Done to True on successful completion.
      procedure Run_One_Shot
        (Result : out Unbounded_String;
         Done   : out Boolean)
      is
         use GNATCOLL.OS.FS;
         Stdout_R, Stdout_W : File_Descriptor;
         Null_In            : File_Descriptor;
         Null_Err           : File_Descriptor;
         Args               : Argument_List;
         Handle             : Process_Handle;
         Exit_Code          : Integer;
         pragma Unreferenced (Exit_Code);
      begin
         Open_Pipe (Stdout_R, Stdout_W);
         Null_In  := Open (Null_File, Read_Mode);
         Null_Err := Open (Null_File, Write_Mode);
         Args.Append (Pi_Acme);
         Args.Append ("--one-shot");
         Args.Append ("--model");
         Args.Append (Model);
         Args.Append ("--prompt");
         Args.Append ("Reply with the single word PONG.");
         Handle := Start
           (Args   => Args,
            Stdin  => Null_In,
            Stdout => Stdout_W,
            Stderr => Null_Err,
            Cwd    => Ada.Directories.Current_Directory);
         Close (Null_In);
         Close (Null_Err);
         Close (Stdout_W);
         Result    := GNATCOLL.OS.FS.Read (Stdout_R);
         Close (Stdout_R);
         Exit_Code := Wait (Handle);
         Done      := True;
      end Run_One_Shot;

      task Runner;
      task body Runner is
      begin
         Run_One_Shot (Out_1, Done_1);
         Run_One_Shot (Out_2, Done_2);
         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Runner;

   begin
      if not Acme_Running then
         return;
      end if;
      if Pi_Acme'Length = 0 then
         Assert (False, "pi_acme binary not found at ../bin/pi_acme");
         return;
      end if;

      select
         Flag.Wait;
      or
         delay 90.0;
      end select;

      Assert (Done_1, "First one-shot run must complete within 90 s");
      Assert (Done_2, "Second one-shot run must complete within 90 s");

      --  Extract both session IDs and verify they differ.
      declare
         --  Parse the session_id from a raw one-shot stdout string.
         function Extract_Session_Id (Raw : String) return String is
            Line : constant String      := First_Line (Raw);
            R    : constant Read_Result := Read (Line);
         begin
            if not R.Success then
               return "";
            end if;
            return Json_Str (R.Value, "session_id");
         end Extract_Session_Id;

         Sess_1 : constant String :=
           Extract_Session_Id (To_String (Out_1));
         Sess_2 : constant String :=
           Extract_Session_Id (To_String (Out_2));
      begin
         Assert
           (Sess_1'Length = 36,
            "First run must return a UUID session_id, got: " & Sess_1);
         Assert
           (Sess_2'Length = 36,
            "Second run must return a UUID session_id, got: " & Sess_2);
         Assert
           (Sess_1 /= Sess_2,
            "Two --one-shot runs must use distinct sessions; "
            & "both returned: " & Sess_1);
      end;
   end Test_One_Shot_Fresh_Session_Each_Run;

end Subagent_Integration_Tests;
