--  pi_list_sessions — print pi sessions for the current directory.
--
--  Output (tab-separated per line):
--    llm-chat+UUID<TAB>name<TAB>date<TAB>snippet
--
--  Button-3 any llm-chat+ token in acme to load that session.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Session_Lister;        use Session_Lister;

procedure Pi_List_Sessions is
   Cwd      : constant String := Ada.Directories.Current_Directory;
   Sessions : constant Session_Vectors.Vector := List_Sessions (Cwd);
begin
   for S of Sessions loop
      Ada.Text_IO.Put_Line
        ("llm-chat+" & To_String (S.UUID)
         & ASCII.HT & To_String (S.Name)
         & ASCII.HT & To_String (S.Date)
         & ASCII.HT & To_String (S.Snippet));
   end loop;
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
end Pi_List_Sessions;
