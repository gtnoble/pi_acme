--  Pi_Acme_App — main application state and entry point.
--
--  App_State is a protected object holding all mutable state shared between
--  tasks.  Run spawns the acme window, starts pi, and blocks until the
--  window is closed.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded;
with Acme.Window;
with Nine_P.Client;

package Pi_Acme_App is

   --  ── App_State ────────────────────────────────────────────────────────
   --
   --  All fields are read under the shared lock (protected functions) and
   --  written under the exclusive lock (protected procedures).
   --  Signal_Shutdown / Wait_Shutdown implement the application shutdown
   --  barrier.

   protected type App_State is

      --  Readers
      function Session_Id         return String;
      function Current_Model      return String;
      function Current_Agent      return String;
      function Current_Thinking   return String;
      function Is_Streaming       return Boolean;
      function Was_Aborted        return Boolean;
      function Text_Emitted       return Boolean;
      function Pending_Stats      return Boolean;
      function Context_Window     return Natural;
      function Turn_Input_Tokens  return Natural;
      function Turn_Output_Tokens return Natural;
      function Win_Name           return String;

      --  Writers
      procedure Set_Session_Id     (Id    : String);
      procedure Set_Model          (Model : String);
      procedure Set_Agent          (Agent : String);
      procedure Set_Thinking       (Level : String);
      procedure Set_Streaming      (Value : Boolean);
      procedure Set_Aborted        (Value : Boolean);
      procedure Set_Text_Emitted   (Value : Boolean);
      procedure Set_Pending_Stats  (Value : Boolean);
      procedure Set_Context_Window (N     : Natural);
      procedure Set_Turn_Tokens    (Input, Output : Natural);
      procedure Set_Win_Name       (Name  : String);

      --  Session reload coordination.
      --  Plumb_Session_Task calls Request_Reload then terminates the
      --  subprocess.  Pi_Stdout_Task calls Consume_Reload after it gets EOF;
      --  if a reload was requested it restarts the subprocess and calls
      --  Signal_Restart_Done, otherwise it calls Signal_Restart_Aborted.
      --  Pi_Stderr_Task calls Wait_Restart_Complete after its own EOF to
      --  learn whether to resume reading the new subprocess or to exit.
      procedure Request_Reload    (UUID : String);
      procedure Consume_Reload
        (UUID          : out Ada.Strings.Unbounded.Unbounded_String;
         Was_Requested : out Boolean);
      procedure Signal_Restart_Done;
      procedure Signal_Restart_Aborted;
      entry     Wait_Restart_Complete (Was_Restarted : out Boolean);

      --  Shutdown synchronisation
      procedure Signal_Shutdown;
      entry     Wait_Shutdown;

   private
      P_Session_Id    : Ada.Strings.Unbounded.Unbounded_String;
      P_Model         : Ada.Strings.Unbounded.Unbounded_String;
      P_Agent         : Ada.Strings.Unbounded.Unbounded_String;
      P_Thinking      : Ada.Strings.Unbounded.Unbounded_String;
      P_Streaming     : Boolean := False;
      P_Aborted       : Boolean := False;
      P_Text_Emitted  : Boolean := False;
      P_Pending_Stats : Boolean := False;
      P_Ctx_Win       : Natural := 0;
      P_Turn_In       : Natural := 0;
      P_Turn_Out      : Natural := 0;
      P_Win_Name      : Ada.Strings.Unbounded.Unbounded_String;
      P_Shutdown      : Boolean := False;
      --  Session reload
      P_Reload_UUID      : Ada.Strings.Unbounded.Unbounded_String;
      P_Reload_Requested : Boolean := False;
      P_Restart_Complete : Boolean := False;
      P_Restart_Was_Done : Boolean := False;
   end App_State;

   --  ── Options ──────────────────────────────────────────────────────────

   type Options is record
      Session_Id : Ada.Strings.Unbounded.Unbounded_String;
      Model      : Ada.Strings.Unbounded.Unbounded_String;
      Agent      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  ── Entry point ──────────────────────────────────────────────────────

   procedure Run (Opts : Options);

   --  ── Session history ──────────────────────────────────────────────────

   --  Read the JSONL session file for UUID and replay the full conversation
   --  history into Win.  Searches all session directories (not just the
   --  current working directory) so sessions from other projects are found.
   --  Restores State.Turn_Tokens from the last assistant usage block so
   --  that the status line and +stats window are accurate immediately after
   --  a session reload.  Appends a separator line when rendering completes.
   --  Writes an error message to Win if the session file cannot be located
   --  or read.
   procedure Render_Session_History
     (UUID  : String;
      Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State);

   --  ── String utilities ─────────────────────────────────────────────────

   --  Return the N-th (1-based) whitespace-separated token from Text,
   --  or "" if Text has fewer than N tokens.  Whitespace is space or HT.
   function Nth_Field (Text : String; N : Positive) return String;

   --  Extract the session UUID from a plumb session token.
   --  Pid_Prefix must be "llm-chat+PID/" for this pi-acme instance.
   --
   --  Accepts:
   --    "llm-chat+PID/UUID"       → UUID  (PID-tagged for this instance)
   --    "llm-chat+UUID"           → UUID  (bare token, backward-compat)
   --  Rejects (returns ""):
   --    "llm-chat+OTHER_PID/UUID" → ""   (tagged for another instance)
   --    anything else             → ""
   function Parse_Session_Token
     (Data       : String;
      Pid_Prefix : String) return String;

end Pi_Acme_App;
