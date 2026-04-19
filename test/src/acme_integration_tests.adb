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

   --  ── Replace_Match: pattern found ─────────────────────────────────────
   --
   --  Write a body containing a unique placeholder token, replace it in-
   --  place, and verify that the substitution is visible and the
   --  surrounding text is preserved.

   procedure Test_Replace_Match_Simple (T : in out Test) is
      pragma Unreferenced (T);
      Before  : constant String := "line one" & ASCII.LF;
      Pending : constant String := "PENDING:abc123ef";
      After   : constant String := ASCII.LF & "line three" & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Append (Win, FS'Access,
                             Before & Pending & After);
         Acme.Window.Replace_Match (Win, FS'Access,
                                    "/" & Pending & "/",
                                    "DONE");
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "DONE") > 0,
               "Replacement text should appear in body");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, Pending) = 0,
               "Placeholder should be gone after replacement");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "line one") > 0,
               "Text before placeholder should be preserved");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "line three") > 0,
               "Text after placeholder should be preserved");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Replace_Match_Simple;

   --  ── Replace_Match: pattern absent ────────────────────────────────────
   --
   --  Calling Replace_Match when the pattern does not exist should be
   --  silent: no exception, and the body must be unchanged.

   procedure Test_Replace_Match_No_Match (T : in out Test) is
      pragma Unreferenced (T);
      Content : constant String := "unchanged content" & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Append (Win, FS'Access, Content);
         --  Pattern that is not present — must not raise.
         Acme.Window.Replace_Match (Win, FS'Access,
                                    "/NOMATCH_XYZ_99/",
                                    "REPLACED");
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, Content) > 0,
               "Original content must be intact after a no-match replace");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "REPLACED") = 0,
               "Replacement text must not appear when pattern is absent");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Replace_Match_No_Match;

   --  ── Replace_Match: parallel tool blocks ──────────────────────────────
   --
   --  Simulate two tool blocks whose start events arrive before either
   --  end event — the interleaved-parallel case.  Each placeholder is
   --  uniquely identified by a token embedded in the pending-close line,
   --  so closing them out-of-order still leaves the blocks sequential and
   --  correctly attributed.

   procedure Test_Replace_Match_Parallel_Blocks (T : in out Test) is
      pragma Unreferenced (T);
      Tok1     : constant String := "PENDING:tok1a2b3c";
      Tok2     : constant String := "PENDING:tok2d4e5f";
      Block1   : constant String :=
        ASCII.LF & "[tool1]" & ASCII.LF & Tok1 & ASCII.LF;
      Block2   : constant String :=
        ASCII.LF & "[tool2]" & ASCII.LF & Tok2 & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         --  Both tool blocks open before either closes.
         Acme.Window.Append (Win, FS'Access, Block1);
         Acme.Window.Append (Win, FS'Access, Block2);

         --  tool2 finishes first.
         Acme.Window.Replace_Match (Win, FS'Access,
                                    "/" & Tok2 & "/", "DONE2");
         --  tool1 finishes second.
         Acme.Window.Replace_Match (Win, FS'Access,
                                    "/" & Tok1 & "/", "DONE1");

         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
            Pos_Tool1 : constant Natural :=
              Ada.Strings.Fixed.Index (Body_Text, "[tool1]");
            Pos_Done1 : constant Natural :=
              Ada.Strings.Fixed.Index (Body_Text, "DONE1");
            Pos_Tool2 : constant Natural :=
              Ada.Strings.Fixed.Index (Body_Text, "[tool2]");
            Pos_Done2 : constant Natural :=
              Ada.Strings.Fixed.Index (Body_Text, "DONE2");
         begin
            Assert (Pos_Tool1 > 0, "[tool1] header present");
            Assert (Pos_Done1 > 0, "DONE1 close present");
            Assert (Pos_Tool2 > 0, "[tool2] header present");
            Assert (Pos_Done2 > 0, "DONE2 close present");

            --  Placeholders must be gone.
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, Tok1) = 0,
               "Placeholder tok1 must be replaced");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, Tok2) = 0,
               "Placeholder tok2 must be replaced");

            --  Block order in body: tool1 before tool2
            --  (appended in that order; replacements do not reorder).
            Assert (Pos_Tool1 < Pos_Tool2,
                    "[tool1] must appear before [tool2]");
            Assert (Pos_Done1 < Pos_Tool2,
                    "DONE1 must appear before [tool2] header");
            Assert (Pos_Done2 > Pos_Tool2,
                    "DONE2 must appear after [tool2] header");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Replace_Match_Parallel_Blocks;

   --  ── Clear: erase content ─────────────────────────────────────────────
   --
   --  Replace_Match ("1,$", "") must remove all existing body text, leaving
   --  the window empty.  This is the first step of the Clear tag command.

   procedure Test_Clear_Body_Erases_Content (T : in out Test) is
      pragma Unreferenced (T);
      Content : constant String :=
        "turn 1 response" & ASCII.LF
        & "turn 2 response" & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Append (Win, FS'Access, Content);
         --  Step 1 of the Clear command: erase the whole body.
         Acme.Window.Replace_Match (Win, FS'Access, "1,$", "");
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "turn 1 response") = 0,
               "Body must not contain old content after Replace_Match "
               & """1,$""");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text, "turn 2 response") = 0,
               "Body must not contain old content after Replace_Match "
               & """1,$""");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Clear_Body_Erases_Content;

   --  ── Clear: full two-step sequence ────────────────────────────────────
   --
   --  The Clear tag command is: Replace_Match ("1,$", "") then
   --  Append (status_line & LF).  After the sequence the old conversation
   --  text must be gone and the new status line must be the only content.

   procedure Test_Clear_Body_Restores_Status (T : in out Test) is
      pragma Unreferenced (T);
      --  Sentinel strings that must NOT survive Clear.
      Old_Content : constant String :=
        "old conversation content" & ASCII.LF;
      --  Plain ASCII status marker; avoids raw multi-byte UTF-8 literals.
      Status_Line : constant String :=
        "CLEAR_STATUS_MARKER" & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         Acme.Window.Append (Win, FS'Access, Old_Content);
         --  Replicate the Clear command: erase then write status line.
         Acme.Window.Replace_Match (Win, FS'Access, "1,$", "");
         Acme.Window.Append        (Win, FS'Access, Status_Line);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Text,
                                        "old conversation content") = 0,
               "Old content must be absent after the Clear sequence");
            Assert
              (Ada.Strings.Fixed.Index (Body_Text,
                                        "CLEAR_STATUS_MARKER") > 0,
               "Status line must be present after the Clear sequence");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Clear_Body_Restores_Status;

   --  ── Clear on an already-empty body ───────────────────────────────────
   --
   --  Invoking the Clear sequence on a window whose body is already empty
   --  must not raise an exception.  Replace_Match silently ignores address
   --  errors; the subsequent Append must still place the status line in the
   --  body.

   procedure Test_Clear_Body_On_Empty_Body (T : in out Test) is
      pragma Unreferenced (T);
      --  Plain ASCII status marker; avoids raw multi-byte UTF-8 literals.
      Status_Line : constant String := "CLEAR_STATUS_MARKER" & ASCII.LF;
   begin
      if not Acme_Running then return; end if;
      declare
         FS  : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Win : Acme.Window.Win          :=
           Acme.Window.New_Win (FS'Access);
         Id  : constant String :=
           Natural_Image (Acme.Window.Id (Win));
      begin
         --  Body is empty — Clear must not raise.
         Acme.Window.Replace_Match (Win, FS'Access, "1,$", "");
         Acme.Window.Append        (Win, FS'Access, Status_Line);
         declare
            Body_Text : constant String :=
              Read_Via_9p ("acme/" & Id & "/body");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Body_Text,
                                        "CLEAR_STATUS_MARKER") > 0,
               "Status line must be present even when body was empty");
         end;
         Acme.Window.Delete (Win, FS'Access);
      end;
   end Test_Clear_Body_On_Empty_Body;

end Acme_Integration_Tests;
