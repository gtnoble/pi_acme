--  Acme — root package.
--
--  Shared types for the acme text editor 9P interface.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

package Acme is

   subtype Window_Id is Positive;

   --  Build a path to a window-specific file.
   --  E.g. Win_File_Path (42, "ctl") = "/42/ctl"
   function Win_File_Path
     (Id   : Window_Id;
      File : String) return String;

end Acme;
