with AUnit.Assertions;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Session_Lister;        use Session_Lister;

package body Session_Lister_Tests is

   use AUnit.Assertions;

   --  ── Encode_Cwd ────────────────────────────────────────────────────────

   procedure Test_Encode_Cwd_Absolute (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Encode_Cwd ("/home/user/proj") = "--home-user-proj--",
              "Absolute path encoding");
      Assert (Encode_Cwd ("/home/gtnoble/Projects/pi_acme")
              = "--home-gtnoble-Projects-pi_acme--",
              "Deeper absolute path");
   end Test_Encode_Cwd_Absolute;

   procedure Test_Encode_Cwd_Relative (T : in out Test) is
      pragma Unreferenced (T);
   begin
      --  A path not starting with '/' is kept as-is (slashes -> dashes).
      Assert (Encode_Cwd ("foo/bar") = "--foo-bar--",
              "Relative path encoding");
   end Test_Encode_Cwd_Relative;

   procedure Test_Encode_Cwd_Empty (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Encode_Cwd ("") = "----", "Empty path -> '----'");
      Assert (Encode_Cwd ("/") = "----",
              "Root '/' -> '----' (leading slash stripped, nothing left)");
   end Test_Encode_Cwd_Empty;

   --  ── Format_Timestamp ─────────────────────────────────────────────────

   procedure Test_Format_Timestamp (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert
        (Format_Timestamp ("2024-01-15T10:30:00.000Z") = "2024-01-15 10:30",
         "ISO timestamp with Z suffix");
      Assert
        (Format_Timestamp ("2025-12-31T23:59:00+00:00") = "2025-12-31 23:59",
         "ISO timestamp with offset");
   end Test_Format_Timestamp;

   procedure Test_Format_Timestamp_Short (T : in out Test) is
      pragma Unreferenced (T);
   begin
      --  Short/empty timestamps are returned verbatim.
      Assert (Format_Timestamp ("2024") = "2024",     "Short string verbatim");
      Assert (Format_Timestamp ("") = "",             "Empty string verbatim");
   end Test_Format_Timestamp_Short;

   --  ── Parse_Session_File ────────────────────────────────────────────────

   --  Write lines to a temp file and return its path.
   function Write_Temp (Lines : String) return String is
      Path : constant String := "/tmp/test_pi_session.jsonl";
      F    : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Lines);
      Ada.Text_IO.Close (F);
      return Path;
   end Write_Temp;

   procedure Test_Parse_Session_Full (T : in out Test) is
      pragma Unreferenced (T);
      Path : constant String := Write_Temp
        ("{""type"":""session"","
         & """id"":""abc-def-123"","
         & """timestamp"":""2024-06-01T12:00:00Z""}"
         & ASCII.LF
         & "{""type"":""session_info"",""name"":""My Session""}"
         & ASCII.LF
         & "{""type"":""message"","
         & """message"":{""role"":""user"","
         & """content"":[{""type"":""text"",""text"":""Hello pi""}]}}"
         & ASCII.LF);
      Info : constant Session_Info := Parse_Session_File (Path);
   begin
      Assert (To_String (Info.UUID)    = "abc-def-123",
              "UUID should be 'abc-def-123'");
      Assert (To_String (Info.Name)    = "My Session",
              "Name should be 'My Session'");
      Assert (To_String (Info.Date)    = "2024-06-01 12:00",
              "Date should be '2024-06-01 12:00'");
      Assert (To_String (Info.Snippet) = "Hello pi",
              "Snippet should be 'Hello pi'");
   end Test_Parse_Session_Full;

   procedure Test_Parse_Session_No_Name (T : in out Test) is
      pragma Unreferenced (T);
      Path : constant String := Write_Temp
        ("{""type"":""session"","
         & """id"":""xyz-789"","
         & """timestamp"":""2024-03-10T08:15:00Z""}"
         & ASCII.LF);
      Info : constant Session_Info := Parse_Session_File (Path);
   begin
      Assert (To_String (Info.UUID)    = "xyz-789",
              "UUID should be parsed");
      Assert (To_String (Info.Name)    = "",
              "Name should be empty when absent");
      Assert (To_String (Info.Snippet) = "",
              "Snippet should be empty when no messages");
      Assert (To_String (Info.Date)    = "2024-03-10 08:15",
              "Date should be formatted");
   end Test_Parse_Session_No_Name;

   procedure Test_Parse_Session_Bad_Json (T : in out Test) is
      pragma Unreferenced (T);
      Path : constant String := Write_Temp
        ("this is not json" & ASCII.LF
         & "also not json" & ASCII.LF);
      Info : constant Session_Info := Parse_Session_File (Path);
   begin
      Assert (To_String (Info.UUID) = "",
              "UUID should be empty when file has no valid session record");
   end Test_Parse_Session_Bad_Json;

   --  ── Find_Session_File ─────────────────────────────────────────────────
   --
   --  These tests create temporary JSONL files under a dedicated test slug
   --  inside $HOME/.pi/agent/sessions/ and clean them up afterward.

   --  Directory slug used exclusively by these tests.
   Sessions_Test_Dir_A : constant String :=
     Ada.Environment_Variables.Value ("HOME", "")
     & "/.pi/agent/sessions/--pi-acme-test--";

   Sessions_Test_Dir_B : constant String :=
     Ada.Environment_Variables.Value ("HOME", "")
     & "/.pi/agent/sessions/--pi-acme-test-B--";

   --  Create JSONL file containing UUID in its name under Dir.
   --  Returns the full path of the created file.
   function Write_Session_File
     (Dir  : String;
      UUID : String) return String
   is
      Path : constant String := Dir & "/" & UUID & ".jsonl";
      F    : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Dir) then
         Ada.Directories.Create_Directory (Dir);
      end if;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line
        (F,
         "{""type"":""session"","
         & """id"":""" & UUID & ""","
         & """timestamp"":""2024-01-01T00:00:00Z""}");
      Ada.Text_IO.Close (F);
      return Path;
   end Write_Session_File;

   --  Delete the test JSONL file if it exists.
   procedure Delete_Session_File (Dir : String; UUID : String) is
      Path : constant String := Dir & "/" & UUID & ".jsonl";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_Session_File;

   procedure Test_Find_Session_File_Found (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-find-found";
      Path : constant String :=
        Write_Session_File (Sessions_Test_Dir_A, UUID);
   begin
      Assert (Find_Session_File (UUID) = Path,
              "Find_Session_File should return the full path of "
              & "the matching file");
      Delete_Session_File (Sessions_Test_Dir_A, UUID);
   exception
      when others =>
         Delete_Session_File (Sessions_Test_Dir_A, UUID);
         raise;
   end Test_Find_Session_File_Found;

   procedure Test_Find_Session_File_Not_Found (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String :=
        "test-piacme-no-such-uuid-xyzzy-99999999";
   begin
      --  This UUID should not match any real session file.
      Assert (Find_Session_File (UUID) = "",
              "Find_Session_File should return empty when UUID not found");
   end Test_Find_Session_File_Not_Found;

   procedure Test_Find_Session_File_Any_Dir (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-find-any-dir";
      Path : constant String :=
        Write_Session_File (Sessions_Test_Dir_B, UUID);
   begin
      --  File is in a different directory slug; should still be found.
      Assert (Find_Session_File (UUID) = Path,
              "Find_Session_File should locate sessions in any "
              & "subdirectory, not just the current CWD slug");
      Delete_Session_File (Sessions_Test_Dir_B, UUID);
   exception
      when others =>
         Delete_Session_File (Sessions_Test_Dir_B, UUID);
         raise;
   end Test_Find_Session_File_Any_Dir;

   --  ── Fork_Session ──────────────────────────────────────────────────────
   --
   --  Test directory used for fork source files.
   Sessions_Fork_Dir : constant String :=
     Ada.Environment_Variables.Value ("HOME", "")
     & "/.pi/agent/sessions/--pi-acme-fork-test--";

   --  Target CWD for forked sessions (maps to the fork test dir).
   Fork_Target_Cwd : constant String := "/pi-acme-fork-test";

   --  Build a two-turn session JSONL string.
   --  Turn 1: user "Hello" / assistant "World"
   --  Turn 2: user "Foo"   / assistant "Bar"
   function Two_Turn_JSONL (UUID : String) return String is
   begin
      return
        "{""type"":""session"",""id"":""" & UUID & ""","
        & """timestamp"":""2024-01-01T00:00:00Z""}" & ASCII.LF
        & "{""type"":""session_info"",""name"":""Original""}" & ASCII.LF
        --  Turn 1
        & "{""type"":""message"",""message"":{""role"":""user"","
        & """content"":[{""type"":""text"",""text"":""Hello""}]}}"
        & ASCII.LF
        & "{""type"":""message"",""message"":{""role"":""assistant"","
        & """content"":[{""type"":""text"",""text"":""World""}]}}"
        & ASCII.LF
        --  Turn 2
        & "{""type"":""message"",""message"":{""role"":""user"","
        & """content"":[{""type"":""text"",""text"":""Foo""}]}}"
        & ASCII.LF
        & "{""type"":""message"",""message"":{""role"":""assistant"","
        & """content"":[{""type"":""text"",""text"":""Bar""}]}}"
        & ASCII.LF;
   end Two_Turn_JSONL;

   --  Write a JSONL string as a session file under Sessions_Fork_Dir.
   procedure Write_Fork_Source (UUID : String; Content : String) is
      Path : constant String :=
        Sessions_Fork_Dir & "/" & UUID & ".jsonl";
      F    : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Sessions_Fork_Dir) then
         Ada.Directories.Create_Directory (Sessions_Fork_Dir);
      end if;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Content);
      Ada.Text_IO.Close (F);
   end Write_Fork_Source;

   --  Delete the source session file from Sessions_Fork_Dir.
   procedure Delete_Fork_Source (UUID : String) is
      Path : constant String :=
        Sessions_Fork_Dir & "/" & UUID & ".jsonl";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_Fork_Source;

   --  Delete a fork-result session by its UUID from the target dir.
   procedure Delete_Fork_Result (UUID : String) is
      Target_Dir : constant String := Sessions_Dir (Fork_Target_Cwd);
      Path       : constant String :=
        Target_Dir & "/" & UUID & ".jsonl";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_Fork_Result;

   --  Read the whole content of Path as a String.
   function Read_File (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Buf : Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Buf, Ada.Text_IO.Get_Line (F) & ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Buf);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         return "";
   end Read_File;

   --  Fork after turn 1 of a two-turn session; verify the result file
   --  contains turn 1 messages but not turn 2, and carries a fork name.
   procedure Test_Fork_Session_One_Turn (T : in out Test) is
      pragma Unreferenced (T);
      Src_UUID : constant String := "test-fork-src-one-turn";
   begin
      Write_Fork_Source (Src_UUID, Two_Turn_JSONL (Src_UUID));
      declare
         New_UUID : constant String :=
           Fork_Session (Src_UUID, 1, Fork_Target_Cwd);
      begin
         Assert (New_UUID'Length > 0,
                 "Fork_Session should return a non-empty UUID");
         declare
            Content : constant String :=
              Read_File (Sessions_Dir (Fork_Target_Cwd)
                         & "/" & New_UUID & ".jsonl");
         begin
            Assert (Ada.Strings.Fixed.Index (Content, "Hello") > 0,
                    "Fork @1 should contain turn-1 user message");
            Assert (Ada.Strings.Fixed.Index (Content, "World") > 0,
                    "Fork @1 should contain turn-1 assistant message");
            Assert (Ada.Strings.Fixed.Index (Content, "Foo") = 0,
                    "Fork @1 must not contain turn-2 user message");
            Assert (Ada.Strings.Fixed.Index (Content, "Bar") = 0,
                    "Fork @1 must not contain turn-2 assistant message");
            Assert (Ada.Strings.Fixed.Index (Content, "Fork of") > 0,
                    "Fork result should carry a fork session name");
            Assert (Ada.Strings.Fixed.Index (Content, "@1") > 0,
                    "Fork name should include the turn number");
         end;
         Delete_Fork_Result (New_UUID);
      end;
      Delete_Fork_Source (Src_UUID);
   exception
      when others =>
         Delete_Fork_Source (Src_UUID);
         raise;
   end Test_Fork_Session_One_Turn;

   --  Fork after turn 2 (the last turn); both turns must be present.
   procedure Test_Fork_Session_Second_Turn (T : in out Test) is
      pragma Unreferenced (T);
      Src_UUID : constant String := "test-fork-src-two-turn";
   begin
      Write_Fork_Source (Src_UUID, Two_Turn_JSONL (Src_UUID));
      declare
         New_UUID : constant String :=
           Fork_Session (Src_UUID, 2, Fork_Target_Cwd);
      begin
         Assert (New_UUID'Length > 0,
                 "Fork @2 should succeed for a two-turn session");
         declare
            Content : constant String :=
              Read_File (Sessions_Dir (Fork_Target_Cwd)
                         & "/" & New_UUID & ".jsonl");
         begin
            Assert (Ada.Strings.Fixed.Index (Content, "Hello") > 0,
                    "Fork @2 should contain turn-1 user message");
            Assert (Ada.Strings.Fixed.Index (Content, "Foo") > 0,
                    "Fork @2 should contain turn-2 user message");
            Assert (Ada.Strings.Fixed.Index (Content, "Bar") > 0,
                    "Fork @2 should contain turn-2 assistant message");
         end;
         Delete_Fork_Result (New_UUID);
      end;
      Delete_Fork_Source (Src_UUID);
   exception
      when others =>
         Delete_Fork_Source (Src_UUID);
         raise;
   end Test_Fork_Session_Second_Turn;

   --  Requesting a turn that does not exist returns "".
   procedure Test_Fork_Session_Beyond_End (T : in out Test) is
      pragma Unreferenced (T);
      Src_UUID : constant String := "test-fork-src-beyond";
   begin
      Write_Fork_Source (Src_UUID, Two_Turn_JSONL (Src_UUID));
      Assert (Fork_Session (Src_UUID, 99, Fork_Target_Cwd) = "",
              "Fork beyond last turn should return empty string");
      Delete_Fork_Source (Src_UUID);
   exception
      when others =>
         Delete_Fork_Source (Src_UUID);
         raise;
   end Test_Fork_Session_Beyond_End;

   --  Non-existent source UUID returns "".
   procedure Test_Fork_Session_Missing_Src (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert
        (Fork_Session ("no-such-uuid-xyzzy-999999", 1, Fork_Target_Cwd) = "",
         "Fork with non-existent source should return empty string");
   end Test_Fork_Session_Missing_Src;

end Session_Lister_Tests;