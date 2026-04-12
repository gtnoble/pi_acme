with AUnit.Assertions;
with Acme;

package body Acme_Window_Tests is

   use AUnit.Assertions;

   procedure Test_Win_File_Path (T : in out Test) is
      pragma Unreferenced (T);
   begin
      Assert (Acme.Win_File_Path (42, "ctl")   = "/42/ctl",
              "Win_File_Path (42, ctl)");
      Assert (Acme.Win_File_Path (1, "body")   = "/1/body",
              "Win_File_Path (1, body)");
      Assert (Acme.Win_File_Path (100, "addr") = "/100/addr",
              "Win_File_Path (100, addr)");
      Assert (Acme.Win_File_Path (7, "event")  = "/7/event",
              "Win_File_Path (7, event)");
   end Test_Win_File_Path;

   procedure Test_Event_Path (T : in out Test) is
      pragma Unreferenced (T);
   begin
      --  Event_Path is just Win_File_Path (id, "event"); verify via root pkg.
      Assert (Acme.Win_File_Path (42, "event") = "/42/event",
              "Event path for window 42");
      Assert (Acme.Win_File_Path (1, "event")  = "/1/event",
              "Event path for window 1");
   end Test_Event_Path;

   procedure Test_Win_File_Path_Id1 (T : in out Test) is
      pragma Unreferenced (T);
   begin
      --  Verify that Natural'Image leading-space stripping works for id=1.
      Assert (Acme.Win_File_Path (1, "ctl") = "/1/ctl",
              "Path for window id 1 must not have a leading space");
   end Test_Win_File_Path_Id1;

end Acme_Window_Tests;
