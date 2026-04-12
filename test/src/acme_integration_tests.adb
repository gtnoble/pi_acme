with AUnit.Assertions;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;    use GNATCOLL.OS.Process;
with Nine_P;                 use Nine_P;
with Nine_P.Client;          use Nine_P.Client;
with Acme;
with Acme.Window;
with Acme.Event_Parser;
with Acme.Raw_Events;

package body Acme_Integration_Tests is

   use AUnit.Assertions;

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

   --  Run 9p read and return the output as a String.
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

   --  ── New_Win ───────────────────────────────────────────────────────────

   procedure Test_New_Win_Has_Valid_Id (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
      begin
         Assert (Acme.Window.Id (Win) > 0,
                 "New window should have a positive ID");
         --  Verify the window actually exists via 9p
         declare
            Id_String : constant String :=
              Natural_Image (Acme.Window.Id (Win));
            Ctl       : constant String :=
              Read_Via_9p ("acme/" & Id_String & "/ctl");
         begin
            Assert (Ctl'Length > 0,
                    "9p should see the new window's ctl file");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_New_Win_Has_Valid_Id;

   --  ── Append visible via 9p ────────────────────────────────────────────

   procedure Test_Append_Visible_Via_9p (T : in out Test) is
      pragma Unreferenced (T);
      Marker : constant String := "acme_ada_test_content";
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Append (Win, FS'Access, Marker);
         --  Verify via 9p
         declare
            Body_Via_9p : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Via_9p, Marker) > 0,
               "9p should see text appended by Acme.Window.Append");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Append_Visible_Via_9p;

   --  ── Set_Name ─────────────────────────────────────────────────────────

   procedure Test_Set_Name (T : in out Test) is
      pragma Unreferenced (T);
      Name : constant String := "/tmp/+ada_test_win";
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Set_Name (Win, FS'Access, Name);
         declare
            Tag : constant String :=
              Read_Via_9p ("acme/" & Id & "/tag");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Tag, "+ada_test_win") > 0,
               "tag file should contain the new window name");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Set_Name;

   --  ── Selection_Text returns empty for a fresh window ───────────────────

   procedure Test_Selection_Empty (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
      begin
         declare
            Sel : constant String :=
              Acme.Window.Selection_Text (Win, FS'Access);
         begin
            Assert (Sel = "",
                    "Fresh window selection should be empty");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Selection_Empty;

   --  ── Raw event parser with a live event file ───────────────────────────
   --
   --  We create a window then validate that the raw parser can decode
   --  a known-good event byte sequence correctly.

   procedure Test_Raw_Event_From_Live (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);

         --  Build a valid raw event: "MX0 4 0 4 Send\n"
         Raw_Event : constant Byte_Array :=
           (Character'Pos ('M'), Character'Pos ('X'),
            Character'Pos ('0'), Character'Pos (' '),
            Character'Pos ('4'), Character'Pos (' '),
            Character'Pos ('0'), Character'Pos (' '),
            Character'Pos ('4'), Character'Pos (' '),
            Character'Pos ('S'), Character'Pos ('e'),
            Character'Pos ('n'), Character'Pos ('d'),
            Character'Pos (ASCII.LF));

         Parser : Acme.Raw_Events.Event_Parser;
         Ev     : Acme.Event_Parser.Event;
      begin
         --  Feed raw bytes directly to the parser (no I/O needed).
         Acme.Raw_Events.Feed (Parser, Raw_Event);
         Assert (Acme.Raw_Events.Next_Event (Parser, Ev),
                 "Parser should decode injected raw event");
         Assert (Ev.C1 = 'M',                  "C1 = M");
         Assert (Ev.C2 = 'X',                  "C2 = X");
         Assert (To_String (Ev.Text) = "Send", "Text = Send");
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Raw_Event_From_Live;

end Acme_Integration_Tests;
