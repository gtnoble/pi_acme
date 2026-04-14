--  pi_acme — Acme frontend for the pi coding agent.
--
--  Usage: pi_acme [--session UUID] [--model PROVIDER/ID]
--                 [--agent NAME] [--no-tools]
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Pi_Acme_App;

procedure Pi_Acme is
   Opts : Pi_Acme_App.Options;
   I    : Positive := 1;
begin
   while I <= Ada.Command_Line.Argument_Count loop
      declare
         Arg : constant String := Ada.Command_Line.Argument (I);
      begin
         if Arg = "--session"
           and then I < Ada.Command_Line.Argument_Count
         then
            I := I + 1;
            Opts.Session_Id :=
              To_Unbounded_String (Ada.Command_Line.Argument (I));
         elsif Arg = "--model"
           and then I < Ada.Command_Line.Argument_Count
         then
            I := I + 1;
            Opts.Model :=
              To_Unbounded_String (Ada.Command_Line.Argument (I));
         elsif Arg = "--agent"
           and then I < Ada.Command_Line.Argument_Count
         then
            I := I + 1;
            Opts.Agent :=
              To_Unbounded_String (Ada.Command_Line.Argument (I));
         elsif Arg = "--no-tools" then
            Opts.No_Tools := True;
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Unknown argument: " & Arg);
         end if;
      end;
      I := I + 1;
   end loop;

   Pi_Acme_App.Run (Opts);
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
end Pi_Acme;
