--  Pi_RPC body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNATCOLL.OS.FS;            use GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;       use GNATCOLL.OS.Process;

package body Pi_RPC is

   --  Thin POSIX binding for kill(2)
   function C_Kill
     (Process_Id : Integer;
      Signal     : Integer) return Integer
     with Import, Convention => C, External_Name => "kill";

   --  ── Find_Pi ───────────────────────────────────────────────────────────

   function Find_Pi return String is
      use Ada.Environment_Variables;
      use type GNAT.OS_Lib.String_Access;
      Ptr : GNAT.OS_Lib.String_Access :=
              GNAT.OS_Lib.Locate_Exec_On_Path ("pi");
   begin
      if Ptr /= null then
         declare
            Result : constant String := Ptr.all;
         begin
            GNAT.OS_Lib.Free (Ptr);
            return Result;
         end;
      end if;
      --  Try the common Node.js install path as a fallback.
      declare
         Home    : constant String :=
           (if Exists ("HOME") then Value ("HOME") else "");
         Node_Pi : constant String :=
           Home & "/Software/node/node_current/bin/pi";
      begin
         if Ada.Directories.Exists (Node_Pi) then
            return Node_Pi;
         end if;
      end;
      return "pi";
   end Find_Pi;

   --  ── Start ─────────────────────────────────────────────────────────────

   function Start
     (Session_Id    : String  := "";
      Model         : String  := "";
      System_Prompt : String  := "";
      Cwd           : String  := "";
      No_Session    : Boolean := False;
      No_Tools      : Boolean := False) return Process
   is
      Stdin_R,  Stdin_W  : File_Descriptor;
      Stdout_R, Stdout_W : File_Descriptor;
      Stderr_R, Stderr_W : File_Descriptor;
      Args : Argument_List;
   begin
      Open_Pipe (Stdin_R,  Stdin_W);
      Open_Pipe (Stdout_R, Stdout_W);
      Open_Pipe (Stderr_R, Stderr_W);

      Args.Append (Find_Pi);
      Args.Append ("--mode");
      Args.Append ("rpc");

      if Session_Id'Length > 0 then
         Args.Append ("--session");
         Args.Append (Session_Id);
      end if;

      if Model'Length > 0 then
         Args.Append ("--model");
         Args.Append (Model);
      end if;

      if System_Prompt'Length > 0 then
         Args.Append ("--system-prompt");
         Args.Append (System_Prompt);
      end if;

      if No_Session then
         Args.Append ("--no-session");
      end if;

      if No_Tools then
         Args.Append ("--no-tools");
      end if;

      return Result : Process do
         Result.Handle := Start
           (Args   => Args,
            Cwd    => Cwd,
            Stdin  => Stdin_R,
            Stdout => Stdout_W,
            Stderr => Stderr_W);
         --  Close the child-side ends in the parent.
         Close (Stdin_R);
         Close (Stdout_W);
         Close (Stderr_W);
         Result.Stdin_FD  := Stdin_W;
         Result.Stdout_FD := Stdout_R;
         Result.Stderr_FD := Stderr_R;
      end return;
   exception
      when Ex : others =>
         --  Best-effort cleanup of all six FDs if spawn fails.
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "Pi_RPC.Start failed: "
            & Ada.Exceptions.Exception_Information (Ex));
         for FD_Index in 1 .. 6 loop
            declare
               Cleanup_FD : constant File_Descriptor :=
                 (case FD_Index is
                    when 1 => Stdin_R,  when 2 => Stdin_W,
                    when 3 => Stdout_R, when 4 => Stdout_W,
                    when 5 => Stderr_R, when others => Stderr_W);
            begin
               if Cleanup_FD /= Invalid_FD then
                  Close (Cleanup_FD);
               end if;
            end;
         end loop;
         raise;
   end Start;

   --  ── Send ──────────────────────────────────────────────────────────────

   procedure Send (P : in out Process; Json : String) is
   begin
      Write (P.Stdin_FD, Json & ASCII.LF);
   end Send;

   --  ── Internal buffered line reader ─────────────────────────────────────
   --
   --  Reads from FD into Buffer until a newline is found, then returns
   --  the line (without the newline) and leaves any remainder in Buffer.
   --  Returns "" on EOF.

   function Next_Line
     (FD     :     File_Descriptor;
      Buffer : in out Unbounded_String) return String
   is
      Chunk      : String (1 .. 4096);
      Bytes_Read : Integer;
   begin
      loop
         --  Scan Buffer for a newline.
         declare
            Current : constant String := To_String (Buffer);
         begin
            for I in Current'Range loop
               if Current (I) = ASCII.LF then
                  declare
                     Line : constant String :=
                       Current (Current'First .. I - 1);
                  begin
                     Buffer :=
                       To_Unbounded_String (Current (I + 1 .. Current'Last));
                     return Line;
                  end;
               end if;
            end loop;
         end;

         --  Need more bytes.
         Bytes_Read := Read (FD, Chunk);
         if Bytes_Read = 0 then
            --  EOF: return any partial content.
            declare
               Last : constant String := To_String (Buffer);
            begin
               Buffer := Null_Unbounded_String;
               return Last;
            end;
         end if;
         Append (Buffer, Chunk (Chunk'First .. Chunk'First + Bytes_Read - 1));
      end loop;
   end Next_Line;

   --  ── Read_Line / Read_Stderr_Line ──────────────────────────────────────

   function Read_Line (P : in out Process) return String is
   begin
      return Next_Line (P.Stdout_FD, P.Out_Buffer);
   end Read_Line;

   function Read_Stderr_Line (P : in out Process) return String is
   begin
      return Next_Line (P.Stderr_FD, P.Err_Buffer);
   end Read_Stderr_Line;

   --  ── Is_Alive / Terminate / Finalize ──────────────────────────────────

   function Is_Alive (P : in out Process) return Boolean is
   begin
      if P.Handle = Invalid_Handle then
         return False;
      end if;
      return State (P.Handle) = RUNNING;
   end Is_Alive;

   procedure Terminate_Process (P : in out Process) is
      Dummy : Integer;
      pragma Unreferenced (Dummy);
   begin
      if P.Handle /= Invalid_Handle and then Is_Alive (P) then
         Dummy := C_Kill (Integer (P.Handle), 15);   --  SIGTERM
      end if;
   end Terminate_Process;

   procedure Close_Stdin (P : in out Process) is
   begin
      if P.Stdin_FD /= Invalid_FD then
         Close (P.Stdin_FD);
         P.Stdin_FD := Invalid_FD;
      end if;
   end Close_Stdin;

   --  ── Restart ───────────────────────────────────────────────────────────

   procedure Restart
     (P          : in out Process;
      Session_Id : String := "";
      Model      : String := "")
   is
   begin
      --  Terminate and reap the old subprocess; close parent-side pipe ends.
      Terminate_Process (P);
      if P.Stdin_FD /= Invalid_FD then
         Close (P.Stdin_FD);
         P.Stdin_FD := Invalid_FD;
      end if;
      if P.Stdout_FD /= Invalid_FD then
         Close (P.Stdout_FD);
         P.Stdout_FD := Invalid_FD;
      end if;
      if P.Stderr_FD /= Invalid_FD then
         Close (P.Stderr_FD);
         P.Stderr_FD := Invalid_FD;
      end if;
      if P.Handle /= Invalid_Handle then
         declare
            Dummy : constant Integer := Wait (P.Handle);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
         P.Handle := Invalid_Handle;
      end if;
      --  Clear partial-line buffers left over from the old process.
      P.Out_Buffer := Null_Unbounded_String;
      P.Err_Buffer := Null_Unbounded_String;
      --  Spawn the replacement subprocess and adopt its handles.
      declare
         New_Proc : Process :=
           Start (Session_Id => Session_Id,
                  Model      => Model);
      begin
         P.Handle    := New_Proc.Handle;
         P.Stdin_FD  := New_Proc.Stdin_FD;
         P.Stdout_FD := New_Proc.Stdout_FD;
         P.Stderr_FD := New_Proc.Stderr_FD;
         --  Prevent New_Proc.Finalize from closing the adopted descriptors.
         New_Proc.Handle    := Invalid_Handle;
         New_Proc.Stdin_FD  := Invalid_FD;
         New_Proc.Stdout_FD := Invalid_FD;
         New_Proc.Stderr_FD := Invalid_FD;
      end;
   end Restart;

   function From_FDs
     (Handle    : GNATCOLL.OS.Process.Process_Handle;
      Stdin_FD  : GNATCOLL.OS.FS.File_Descriptor;
      Stdout_FD : GNATCOLL.OS.FS.File_Descriptor;
      Stderr_FD : GNATCOLL.OS.FS.File_Descriptor) return Process
   is
   begin
      return Result : Process do
         Result.Handle    := Handle;
         Result.Stdin_FD  := Stdin_FD;
         Result.Stdout_FD := Stdout_FD;
         Result.Stderr_FD := Stderr_FD;
      end return;
   end From_FDs;

   overriding procedure Finalize (P : in out Process) is
   begin
      Terminate_Process (P);
      if P.Stdin_FD /= Invalid_FD then
         Close (P.Stdin_FD);
         P.Stdin_FD := Invalid_FD;
      end if;
      if P.Stdout_FD /= Invalid_FD then
         Close (P.Stdout_FD);
         P.Stdout_FD := Invalid_FD;
      end if;
      if P.Stderr_FD /= Invalid_FD then
         Close (P.Stderr_FD);
         P.Stderr_FD := Invalid_FD;
      end if;
      if P.Handle /= Invalid_Handle then
         declare
            Dummy : constant Integer := Wait (P.Handle);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
         P.Handle := Invalid_Handle;
      end if;
   end Finalize;

end Pi_RPC;
