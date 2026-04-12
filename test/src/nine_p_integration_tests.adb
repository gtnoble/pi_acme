with AUnit.Assertions;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;   use GNATCOLL.OS.Process;
with Nine_P;                use Nine_P;
with Nine_P.Client;         use Nine_P.Client;

package body Nine_P_Integration_Tests is

   use AUnit.Assertions;

   --  ── Guard helper ──────────────────────────────────────────────────────

   function Acme_Running return Boolean is
   begin
      return Ada.Directories.Exists (Namespace & "/acme");
   exception
      when others => return False;
   end Acme_Running;

   --  Run "/usr/local/plan9/bin/9p read <path>" and return stdout.
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

   --  ── Tests ─────────────────────────────────────────────────────────────

   procedure Test_Ns_Mount_Acme (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS : Nine_P.Client.Fs := Ns_Mount ("acme");
         pragma Unreferenced (FS);
      begin
         Assert (True, "Ns_Mount should not raise");
      end;
   end Test_Ns_Mount_Acme;

   procedure Test_Read_Acme_Index (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS   : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         F    : aliased Nine_P.Client.File :=
           Open (FS'Access, "/index", O_READ);
         Data : constant Byte_Array := Read (F'Access);
      begin
         Assert (Data'Length > 0, "Acme /index should be non-empty");
         --  Cross-validate: 9p should return the same content.
         declare
            Via_9p  : constant String := Read_Via_9p ("acme/index");
            Via_Ada : String (1 .. Data'Length);
         begin
            for I in Data'Range loop
               Via_Ada (I - Data'First + 1) := Character'Val (Data (I));
            end loop;
            Assert (Via_Ada = Via_9p,
                    "Our client and 9p should read identical index data");
         end;
      end;
   end Test_Read_Acme_Index;

   procedure Test_Open_New_Ctl (T : in out Test) is
      pragma Unreferenced (T);
   begin
      if not Acme_Running then return; end if;
      declare
         FS   : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         F    : aliased Nine_P.Client.File :=
           Open (FS'Access, "/new/ctl", O_READ);
         Data : constant Byte_Array := Read (F'Access);
      begin
         Assert (Data'Length > 0, "/new/ctl should return a window ID");
         --  First token should be a positive integer (the window ID).
         --  Acme right-justifies each field in an 11-char column, so the
         --  data begins with leading spaces; skip them before collecting
         --  the non-whitespace token.
         declare
            Text     : String (1 .. Data'Length);
            Tok      : Unbounded_String;
            In_Token : Boolean := False;
         begin
            for I in Data'Range loop
               Text (I - Data'First + 1) := Character'Val (Data (I));
            end loop;
            for C of Text loop
               if C in ' ' | ASCII.LF | ASCII.CR | ASCII.HT then
                  exit when In_Token;
               else
                  In_Token := True;
                  Append (Tok, C);
               end if;
            end loop;
            declare
               Win_Id : constant Natural :=
                 Natural'Value (To_String (Tok));
            begin
               Assert (Win_Id > 0,
                       "Window ID from /new/ctl should be > 0");
               --  Clean up: delete the newly-created window.
               declare
                  Id_S  : constant String := To_String (Tok);
                  Del   : aliased Nine_P.Client.File :=
                    Open (FS'Access, "/" & Id_S & "/ctl", O_WRITE);
                  Dummy : constant Natural :=
                    Write (Del'Access, "delete" & ASCII.LF);
                  pragma Unreferenced (Dummy);
               begin
                  null;
               end;
            end;
         end;
      end;
   end Test_Open_New_Ctl;

   --  Write to a new window via our Ada client and read back via 9p.
   procedure Test_Client_Matches_9p (T : in out Test) is
      pragma Unreferenced (T);
      Marker : constant String := "pi_acme_integration_test_marker";
   begin
      if not Acme_Running then return; end if;
      declare
         FS    : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Ctl_F : aliased Nine_P.Client.File :=
           Open (FS'Access, "/new/ctl", O_READ);
         Ctl   : constant Byte_Array := Read (Ctl_F'Access);
         Win_S : String (1 .. Ctl'Length);
         Tok   : Unbounded_String;
      begin
         for I in Ctl'Range loop
            Win_S (I - Ctl'First + 1) := Character'Val (Ctl (I));
         end loop;
         --  Skip leading spaces: acme right-justifies each ctl field in
         --  an 11-char column, so the ID is preceded by spaces.
         declare
            In_Token : Boolean := False;
         begin
            for C of Win_S loop
               if C in ' ' | ASCII.LF | ASCII.CR | ASCII.HT then
                  exit when In_Token;
               else
                  In_Token := True;
                  Append (Tok, C);
               end if;
            end loop;
         end;
         declare
            Id_S   : constant String := To_String (Tok);
            Body_F : aliased Nine_P.Client.File :=
              Open (FS'Access, "/" & Id_S & "/body", O_WRITE);
            Addr_F : aliased Nine_P.Client.File :=
              Open (FS'Access, "/" & Id_S & "/addr", O_WRITE);
            Data_F : aliased Nine_P.Client.File :=
              Open (FS'Access, "/" & Id_S & "/data", O_WRITE);
            Dummy  : Natural;
         begin
            --  Write addr="$" then data=Marker (atomic append)
            Dummy := Write (Addr_F'Access, "$");
            Dummy := Write (Data_F'Access, Marker);
            pragma Unreferenced (Dummy, Body_F);

            --  Read back via 9p
            declare
               Via_9p : constant String :=
                 Read_Via_9p ("acme/" & Id_S & "/body");
            begin
               Assert
                 (Ada.Strings.Fixed.Index (Via_9p, Marker) > 0,
                  "9p should see text written by our Ada client");
            end;

            --  Clean up
            declare
               Del   : aliased Nine_P.Client.File :=
                 Open (FS'Access, "/" & Id_S & "/ctl", O_WRITE);
               Dummy2 : constant Natural :=
                 Write (Del'Access, "delete" & ASCII.LF);
               pragma Unreferenced (Dummy2);
            begin
               null;
            end;
         end;
      end;
   end Test_Client_Matches_9p;

end Nine_P_Integration_Tests;
