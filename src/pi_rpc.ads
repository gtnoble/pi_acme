--  Pi_RPC — manage a `pi --mode rpc` subprocess.
--
--  Spawns pi with stdin/stdout/stderr connected to pipes.  Callers write
--  JSON lines to stdin via Send and read events line-by-line from stdout
--  via Read_Line.  Stderr is available via Read_Stderr_Line.
--
--  Process is Limited_Controlled: pipes are closed and the process is
--  terminated automatically when the object goes out of scope.
--
--  Find_Pi locates the pi binary at construction time.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Finalization;
with Ada.Strings.Unbounded;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;

package Pi_RPC is

   Process_Error : exception;

   type Process is limited private;

   --  Locate the pi binary (searches $PATH then known install paths).
   function Find_Pi return String;

   --  Spawn pi --mode rpc.  Optional Session_Id, Model, System_Prompt
   --  add the corresponding flags.  Cwd sets the working directory.
   --  Set No_Session => True to pass --no-session (avoids writing session
   --  files — useful in tests to prevent state sharing between runs).
   --  Set No_Tools => True to pass --no-tools (disables all built-in tools).
   --  Set Extension to a non-empty path to pass --extension PATH, loading
   --  that TypeScript extension into the spawned pi process.
   function Start
     (Session_Id    : String  := "";
      Model         : String  := "";
      System_Prompt : String  := "";
      Cwd           : String  := "";
      No_Session    : Boolean := False;
      No_Tools      : Boolean := False;
      Extension     : String  := "") return Process;

   --  Write Json (a single JSON object, no newline) to pi's stdin.
   procedure Send (P : in out Process; Json : String);

   --  Read one newline-terminated line from pi's stdout.
   --  Blocks until a complete line is available.
   --  Returns "" on EOF (process has exited).
   function Read_Line (P : in out Process) return String;

   --  Read one line from pi's stderr.
   --  Blocks until a complete line is available.
   --  Returns "" on EOF.
   function Read_Stderr_Line (P : in out Process) return String;

   --  True while the process is still running.
   function Is_Alive (P : in out Process) return Boolean;

   --  Send SIGTERM to the process (non-blocking).
   procedure Terminate_Process (P : in out Process);

   --  Close the stdin pipe (signals EOF to the child process).
   procedure Close_Stdin (P : in out Process);

   --  Terminate the running subprocess, spawn a new one with the given
   --  Session_Id and optional Model, and update all internal handles in
   --  place.  The caller must ensure that all concurrent reads on this
   --  process have already returned EOF before calling Restart.
   procedure Restart
     (P          : in out Process;
      Session_Id : String := "";
      Model      : String := "");

   --  Low-level constructor from pre-existing file descriptors.
   --  Intended for testing; for normal use call Start.
   function From_FDs
     (Handle    : GNATCOLL.OS.Process.Process_Handle;
      Stdin_FD  : GNATCOLL.OS.FS.File_Descriptor;
      Stdout_FD : GNATCOLL.OS.FS.File_Descriptor;
      Stderr_FD : GNATCOLL.OS.FS.File_Descriptor) return Process;

private

   use Ada.Strings.Unbounded;

   type Process is new Ada.Finalization.Limited_Controlled with record
      Handle    : GNATCOLL.OS.Process.Process_Handle :=
                    GNATCOLL.OS.Process.Invalid_Handle;
      Stdin_FD  : GNATCOLL.OS.FS.File_Descriptor :=
                    GNATCOLL.OS.FS.Invalid_FD;
      Stdout_FD : GNATCOLL.OS.FS.File_Descriptor :=
                    GNATCOLL.OS.FS.Invalid_FD;
      Stderr_FD : GNATCOLL.OS.FS.File_Descriptor :=
                    GNATCOLL.OS.FS.Invalid_FD;
      --  Partial-line accumulators for Read_Line / Read_Stderr_Line.
      Out_Buffer : Unbounded_String;
      Err_Buffer : Unbounded_String;
   end record;

   overriding procedure Finalize (P : in out Process);

end Pi_RPC;
