--  Acme body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

package body Acme is

   function Win_File_Path
     (Id   : Window_Id;
      File : String) return String
   is
      --  Natural'Image adds a leading space; skip it.
      Id_Image : constant String := Natural'Image (Id);
   begin
      return "/"
             & Id_Image (Id_Image'First + 1 .. Id_Image'Last)
             & "/" & File;
   end Win_File_Path;

end Acme;
