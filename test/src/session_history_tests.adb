--  Session_History_Tests body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with AUnit.Assertions;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;   use GNATCOLL.OS.Process;
with Nine_P;
with Nine_P.Client;          use Nine_P.Client;
with Acme;
with Acme.Window;
with Pi_Acme_App;            use Pi_Acme_App;

package body Session_History_Tests is

   use AUnit.Assertions;

   --  ── Helpers ───────────────────────────────────────────────────────────

   function Acme_Running return Boolean is
   begin
      return Ada.Directories.Exists (Namespace & "/acme");
   exception
      when others => return False;
   end Acme_Running;

   --  Natural'Image without the leading space.
   function Natural_Image (N : Natural) return String is
      Image : constant String := Natural'Image (N);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image;

   --  Run "9p read <Path>" and return its output as a String.
   function Read_Via_9p (Path : String) return String is
      use GNATCOLL.OS.FS;
      Stdout_R, Stdout_W : File_Descriptor;
      Args               : Argument_List;
      Handle             : Process_Handle;
   begin
      Open_Pipe (Stdout_R, Stdout_W);
      Args.Append ("/usr/local/plan9/bin/9p");
      Args.Append ("read");
      Args.Append (Path);
      Handle := Start (Args   => Args,
                       Stdout => Stdout_W,
                       Stderr => Null_FD);
      Close (Stdout_W);
      declare
         Result : constant Unbounded_String :=
           GNATCOLL.OS.FS.Read (Stdout_R);
         Dummy  : constant Integer := Wait (Handle);
         pragma Unreferenced (Dummy);
      begin
         Close (Stdout_R);
         return To_String (Result);
      end;
   end Read_Via_9p;

   --  True if Pattern occurs anywhere in Source.
   function Contains (Source : String; Pattern : String) return Boolean is
   begin
      return Ada.Strings.Fixed.Index (Source, Pattern) > 0;
   end Contains;

   --  Session files are written to this directory so they are found by
   --  Find_Session_File without interfering with real sessions.
   Sessions_Test_Dir : constant String :=
     Ada.Environment_Variables.Value ("HOME", "")
     & "/.pi/agent/sessions/--pi-acme-test-render--";

   --  Write a JSONL session file whose filename embeds UUID.
   --  Lines is the full JSONL content supplied by the caller.
   --  Returns the full path of the created file.
   function Write_Session
     (UUID  : String;
      Lines : String) return String
   is
      Path : constant String := Sessions_Test_Dir & "/" & UUID & ".jsonl";
      F    : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Sessions_Test_Dir) then
         Ada.Directories.Create_Directory (Sessions_Test_Dir);
      end if;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (F, Lines);
      Ada.Text_IO.Close (F);
      return Path;
   end Write_Session;

   --  Remove the test session file if it exists.
   procedure Delete_Session (UUID : String) is
      Path : constant String := Sessions_Test_Dir & "/" & UUID & ".jsonl";
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_Session;

   --  Session header line for test JSONL files.
   function Session_Header (UUID : String) return String is
   begin
      return
        "{""type"":""session"","
        & """id"":""" & UUID & ""","
        & """timestamp"":""2024-01-01T00:00:00Z""}"
        & ASCII.LF;
   end Session_Header;

   --  ── Test_Render_File_Not_Found ────────────────────────────────────────

   procedure Test_Render_File_Not_Found (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         UUID  : constant String :=
           "test-piacme-render-notfound-9999";
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         --  UUID is not backed by any file.
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, "not found"),
                    "Window body should contain 'not found' error "
                    & "when session file is missing");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
      end;
   end Test_Render_File_Not_Found;

   --  ── Test_Render_User_Message ──────────────────────────────────────────

   procedure Test_Render_User_Message (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-user";
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Hello world test""}]}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, "Hello world test"),
                    "User message text should appear in the window body");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_User_Message;

   --  ── Test_Render_Assistant_Text ────────────────────────────────────────

   procedure Test_Render_Assistant_Text (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-asst";
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Ping""}]}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""assistant"","
            & """content"":[{""type"":""text"","
            & """text"":""Pong response text""}],"
            & """usage"":{""input"":150,""output"":25,"
            & """cacheRead"":0,""cacheWrite"":0}}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, "Pong response text"),
                    "Assistant text should appear verbatim in window body");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Assistant_Text;

   --  ── Test_Render_Tool_Call_Success ─────────────────────────────────────

   procedure Test_Render_Tool_Call_Success (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-tool-ok";
      --  UC_CHECK  U+2713
      UC_Check : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#9C#)
        & Character'Val (16#93#);
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Read a file""}]}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""assistant"","
            & """content"":[{""type"":""toolCall"","
            & """id"":""tc-ok-001"","
            & """name"":""read"","
            & """arguments"":{""path"":""/test/file.txt""}}],"
            & """usage"":{""input"":200,""output"":15,"
            & """cacheRead"":0,""cacheWrite"":0}}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""toolResult"","
            & """toolCallId"":""tc-ok-001"","
            & """isError"":false,"
            & """content"":[{""type"":""text"","
            & """text"":""file contents here""}]}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, "read"),
                    "Tool name should appear in the window body");
            Assert (Contains (Body_Text, UC_Check),
                    "Check mark should appear for a successful tool call");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Tool_Call_Success;

   --  ── Test_Render_Tool_Call_Error ───────────────────────────────────────

   procedure Test_Render_Tool_Call_Error (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-tool-err";
      --  UC_CROSS  U+2717
      UC_Cross : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#9C#)
        & Character'Val (16#97#);
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Read file""}]}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""assistant"","
            & """content"":[{""type"":""toolCall"","
            & """id"":""tc-err-001"","
            & """name"":""read"","
            & """arguments"":{""path"":""/missing.txt""}}],"
            & """usage"":{""input"":180,""output"":12,"
            & """cacheRead"":0,""cacheWrite"":0}}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""toolResult"","
            & """toolCallId"":""tc-err-001"","
            & """isError"":true,"
            & """content"":[{""type"":""text"","
            & """text"":""File not found: /missing.txt""}]}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, UC_Cross),
                    "Cross mark should appear for a failed tool call");
            Assert (Contains (Body_Text, "File not found"),
                    "First line of error text should appear in the body");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Tool_Call_Error;

   --  ── Test_Render_Thinking_Block ────────────────────────────────────────

   procedure Test_Render_Thinking_Block (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-think";
      --  UC_BOX_V  U+2502
      UC_Box_V : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#94#)
        & Character'Val (16#82#);
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Think about it""}]}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""assistant"","
            & """content"":[{""type"":""thinking"","
            & """thinking"":""Reasoning step one""},"
            & "{""type"":""text"","
            & """text"":""Conclusion text""}],"
            & """usage"":{""input"":250,""output"":30,"
            & """cacheRead"":0,""cacheWrite"":0}}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, UC_Box_V),
                    "Thinking block should be prefixed with vertical bar");
            Assert (Contains (Body_Text, "Reasoning step one"),
                    "Thinking text should appear in the window body");
            Assert (Contains (Body_Text, "Conclusion text"),
                    "Text block after thinking should appear in the body");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Thinking_Block;

   --  ── Test_Render_Model_Change ──────────────────────────────────────────

   procedure Test_Render_Model_Change (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-model";
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""model_change"","
            & """provider"":""anthropic"","
            & """modelId"":""claude-sonnet-test""}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Hello""}]}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, "[Model"),
                    "Model change should render '[Model' prefix");
            Assert (Contains (Body_Text, "anthropic/claude-sonnet-test"),
                    "Model change should include provider/modelId");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Model_Change;

   --  ── Test_Render_Token_Stats ───────────────────────────────────────────

   procedure Test_Render_Token_Stats (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-tokens";
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""Count tokens""}]}}"
            & ASCII.LF
            & "{""type"":""message"","
            & """message"":{""role"":""assistant"","
            & """content"":[{""type"":""text"","
            & """text"":""Done""}],"
            & """usage"":{""input"":1500,"
            & """cacheRead"":300,""cacheWrite"":100,"
            & """output"":42}}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
         pragma Unreferenced (Id);
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         --  input + cacheRead + cacheWrite = 1500 + 300 + 100 = 1900
         Assert
           (State.Turn_Input_Tokens = 1900,
            "Input tokens should be sum of input+cacheRead+cacheWrite "
            & "(1900); got " & Natural'Image (State.Turn_Input_Tokens));
         Assert
           (State.Turn_Output_Tokens = 42,
            "Output tokens should be 42; got "
            & Natural'Image (State.Turn_Output_Tokens));
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Token_Stats;

   --  ── Test_Render_Separator ─────────────────────────────────────────────

   procedure Test_Render_Separator (T : in out Test) is
      pragma Unreferenced (T);
      UUID : constant String := "test-piacme-render-sep";
      --  UC_DBL_H  U+2550  (used in SEPARATOR)
      UC_Dbl_H : constant String :=
        Character'Val (16#E2#)
        & Character'Val (16#95#)
        & Character'Val (16#90#);
   begin
      if not Acme_Running then
         return;
      end if;
      declare
         Path : constant String := Write_Session
           (UUID,
            Session_Header (UUID)
            & "{""type"":""message"","
            & """message"":{""role"":""user"","
            & """content"":[{""type"":""text"","
            & """text"":""One""}]}}"
            & ASCII.LF);
         pragma Unreferenced (Path);
         FS    : aliased Nine_P.Client.Fs :=
           Ns_Mount ("acme");
         Win   : Acme.Window.Win :=
           Acme.Window.New_Win (FS'Access);
         State : App_State;
         Id    : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Render_Session_History (UUID, Win, FS'Access, State);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert (Contains (Body_Text, UC_Dbl_H),
                    "SEPARATOR should be appended after the history");
         end;
         Acme.Window.Ctl (Win, FS'Access, "clean");
         Acme.Window.Ctl (Win, FS'Access, "del");
         Delete_Session (UUID);
      exception
         when others =>
            Delete_Session (UUID);
            raise;
      end;
   end Test_Render_Separator;

end Session_History_Tests;
