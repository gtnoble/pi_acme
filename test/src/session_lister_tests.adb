with AUnit.Assertions;
with Ada.Directories;
with Ada.Environment_Variables;
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

end Session_Lister_Tests;
