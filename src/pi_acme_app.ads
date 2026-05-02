--  Pi_Acme_App — main application state and entry point.
--
--  App_State is a protected object holding all mutable state shared between
--  tasks.  Run spawns the acme window, starts pi, and blocks until the
--  window is closed.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Strings.Unbounded;

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
      function Is_Compacting      return Boolean;
      function Was_Aborted        return Boolean;
      function Text_Emitted       return Boolean;
      --  True while an auto-retry sequence is in progress.  Set by
      --  auto_retry_start, cleared by auto_retry_end and explicit reset
      --  points (new_session response, session reload).  Used to suppress
      --  the spurious "No response" message for all but the first failed
      --  attempt: pi emits agent_end before auto_retry_start, so the first
      --  failure always arrives before we know a retry is coming.
      function Is_Retrying        return Boolean;
      --  True only when at least one text_delta arrived in the current
      --  agent turn (tool-only turns leave this False).
      function Has_Text_Delta     return Boolean;
      --  True when tool_execution_start fired in the current agent turn.
      --  Reset at agent_start alongside Has_Text_Delta.
      function Has_Tool_In_Turn   return Boolean;
      --  stopReason from the last assistant message_end event in the
      --  current agent run.  Reset to "" at agent_start.  Possible values
      --  emitted by pi: "stop" (normal completion), "length" (max tokens),
      --  "toolUse" (intermediate turn — another LLM call follows),
      --  "aborted", "error".  A value of "stop" or "length" means the
      --  agent's final LLM call produced a text response; "toolUse" means
      --  more turns are still pending (not possible at agent_end, but
      --  tracked for safety).
      function Last_Stop_Reason   return String;
      --  errorMessage from the last assistant message_end with
      --  stopReason "error".  Empty when the last turn did not produce
      --  an error, or when pi did not supply a message.  Reset at
      --  agent_start alongside Last_Stop_Reason.
      function Last_Error_Message return String;
      function Pending_Stats        return Boolean;
      --  True while waiting for the get_available_models response that will
      --  populate the +models sub-window.  Set by the Acme_Event_Task when
      --  the user presses Models; cleared by Dispatch_Pi_Event when the
      --  response arrives and the sub-window has been opened.
      function Models_Pending       return Boolean;
      function Context_Window     return Natural;
      function Turn_Input_Tokens  return Natural;
      function Turn_Output_Tokens return Natural;
      function Turn_Count            return Natural;
      --  Per-turn cost captured from message_end (units of $0.0001).
      function Turn_Cost_Dmil        return Natural;
      --  Cumulative session stats from the last get_session_stats response.
      function Session_Cost_Dmil     return Natural;
      function Session_Input_Tokens  return Natural;
      function Session_Output_Tokens return Natural;
      function Session_Cache_Read    return Natural;
      function Session_Cache_Write   return Natural;
      function Session_Total_Tokens  return Natural;
      function Win_Name              return String;

      --  Writers
      procedure Set_Session_Id     (Id    : String);
      procedure Set_Model          (Model : String);
      procedure Set_Agent          (Agent : String);
      procedure Set_Thinking       (Level : String);
      procedure Set_Streaming      (Value : Boolean);
      procedure Set_Compacting     (Value : Boolean);
      procedure Set_Aborted        (Value : Boolean);
      procedure Set_Is_Retrying    (Value : Boolean);
      procedure Set_Text_Emitted   (Value : Boolean);
      procedure Set_Has_Text_Delta   (Value : Boolean);
      procedure Set_Has_Tool_In_Turn (Value : Boolean);
      procedure Set_Last_Stop_Reason  (Value : String);
      procedure Set_Last_Error_Message (Value : String);
      procedure Set_Pending_Stats  (Value : Boolean);
      procedure Set_Models_Pending (Value : Boolean);
      procedure Set_Context_Window (N     : Natural);
      procedure Set_Turn_Tokens    (Input, Output : Natural);
      --  Per-turn cost from message_end usage.cost.total (units of $0.0001).
      procedure Set_Turn_Cost      (Dmil : Natural);
      --  Store the full get_session_stats payload atomically.
      procedure Set_Session_Stats
        (Cost_Dmil   : Natural;
         Input       : Natural;
         Output      : Natural;
         Cache_Read  : Natural;
         Cache_Write : Natural;
         Total       : Natural);
      procedure Set_Win_Name       (Name  : String);

      --  Turn counter — incremented after each completed agent turn,
      --  reset on new_session, and restored from history on session reload.
      procedure Increment_Turn_Count;
      procedure Set_Turn_Count     (N     : Natural);
      procedure Reset_Turn_Count;

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

      --  One-shot result: set once by Pi_Stdout_Task before signalling
      --  shutdown; read by Run after Wait_Shutdown returns.  Only the
      --  first call to Set_One_Shot_Result has effect (subsequent calls
      --  are silently ignored), so the exception handler can call it
      --  safely without overwriting an already-captured success result.
      --  Returns "" until a result has been stored.
      procedure Set_One_Shot_Result (Json : String);
      function  One_Shot_Result     return String;

      --  Shutdown synchronisation
      procedure Signal_Shutdown;
      entry     Wait_Shutdown;

   private
      P_Session_Id    : Ada.Strings.Unbounded.Unbounded_String;
      P_Model         : Ada.Strings.Unbounded.Unbounded_String;
      P_Agent         : Ada.Strings.Unbounded.Unbounded_String;
      P_Thinking      : Ada.Strings.Unbounded.Unbounded_String;
      P_Streaming     : Boolean := False;
      P_Compacting    : Boolean := False;
      P_Aborted       : Boolean := False;
      P_Is_Retrying   : Boolean := False;
      P_Text_Emitted  : Boolean := False;
      P_Has_Text_Delta   : Boolean := False;
      P_Has_Tool_In_Turn : Boolean := False;
      P_Last_Stop_Reason  : Ada.Strings.Unbounded.Unbounded_String;
      P_Last_Error_Message : Ada.Strings.Unbounded.Unbounded_String;
      P_Pending_Stats : Boolean := False;
      P_Models_Pending : Boolean := False;
      P_Ctx_Win       : Natural := 0;
      P_Turn_In       : Natural := 0;
      P_Turn_Out      : Natural := 0;
      --  Per-turn cost (units of $0.0001); set from message_end.
      P_Turn_Cost     : Natural := 0;
      --  Cumulative session stats; set from get_session_stats response.
      P_Sess_Cost     : Natural := 0;
      P_Sess_In       : Natural := 0;
      P_Sess_Out      : Natural := 0;
      P_Sess_Cache_R  : Natural := 0;
      P_Sess_Cache_W  : Natural := 0;
      P_Sess_Total    : Natural := 0;
      P_Win_Name      : Ada.Strings.Unbounded.Unbounded_String;
      P_Shutdown      : Boolean := False;
      P_Turn_Count    : Natural := 0;
      --  Session reload
      P_Reload_UUID      : Ada.Strings.Unbounded.Unbounded_String;
      P_Reload_Requested : Boolean := False;
      P_Restart_Complete : Boolean := False;
      P_Restart_Was_Done : Boolean := False;
      --  One-shot result (empty until set)
      P_One_Shot_Result  : Ada.Strings.Unbounded.Unbounded_String;
   end App_State;

   --  ── Options ──────────────────────────────────────────────────────────

   type Options is record
      Session_Id     : Ada.Strings.Unbounded.Unbounded_String;
      Model          : Ada.Strings.Unbounded.Unbounded_String;
      Agent          : Ada.Strings.Unbounded.Unbounded_String;
      No_Tools       : Boolean := False;
      No_Session     : Boolean := False;
      --  When non-empty, sent as the first prompt immediately after the
      --  bootstrap get_state exchange.  Only meaningful with One_Shot.
      Initial_Prompt : Ada.Strings.Unbounded.Unbounded_String;
      --  When True, the window closes and the process exits after the first
      --  complete agent turn, printing a JSON result line to stdout.
      One_Shot       : Boolean := False;
      --  Optional short label appended to the window name as ":Name" so the
      --  acme tagline reads "CWD/+pi:Name | …".  Empty means no suffix.
      Name           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  ── Section_Kind ─────────────────────────────────────────────────────
   --
   --  Tracks which kind of streaming content is currently being appended to
   --  the window body.  Shared between Dispatch_Pi_Event (in
   --  Pi_Acme_App.Dispatch) and the Pi_Stdout_Task in Run.

   type Section_Kind is
     (No_Section, Thinking_Section, Text_Section, Tool_Section);

   --  ── Entry point ──────────────────────────────────────────────────────

   procedure Run (Opts : Options);

end Pi_Acme_App;
