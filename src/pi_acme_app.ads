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
with GNATCOLL.JSON;
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
      function Pending_Stats      return Boolean;
      function Context_Window     return Natural;
      function Turn_Input_Tokens  return Natural;
      function Turn_Output_Tokens return Natural;
      function Turn_Count         return Natural;
      function Win_Name           return String;

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
      procedure Set_Has_Text_Delta (Value : Boolean);
      procedure Set_Pending_Stats  (Value : Boolean);
      procedure Set_Context_Window (N     : Natural);
      procedure Set_Turn_Tokens    (Input, Output : Natural);
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
      P_Has_Text_Delta : Boolean := False;
      P_Pending_Stats : Boolean := False;
      P_Ctx_Win       : Natural := 0;
      P_Turn_In       : Natural := 0;
      P_Turn_Out      : Natural := 0;
      P_Win_Name      : Ada.Strings.Unbounded.Unbounded_String;
      P_Shutdown      : Boolean := False;
      P_Turn_Count    : Natural := 0;
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
      No_Tools   : Boolean := False;
   end record;

   --  ── Entry point ──────────────────────────────────────────────────────

   procedure Run (Opts : Options);

   --  ── Session history ──────────────────────────────────────────────────

   --  Read the JSONL session file for UUID and replay the full conversation
   --  history into Win.  Searches all session directories (not just the
   --  current working directory) so sessions from other projects are found.
   --  Restores State.Turn_Tokens from the last assistant usage block so
   --  that the status line and +stats window are accurate immediately after
   --  a session reload.  Appends a turn footer when rendering completes.
   --  Writes an error message to Win if the session file cannot be located
   --  or read.
   procedure Render_Session_History
     (UUID  : String;
      Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State);

   --  Append the live end-of-turn footer to Win using the current values in
   --  State, and increment State.Turn_Count.  The footer format is:
   --
   --    [ctx ... | ^... out | provider/model] fork+PID/UUID/N
   --    ════════════════════════════════════════════════════════════
   --
   --  where the bracketed summary is omitted when no summary parts are
   --  available.  Used by Dispatch_Pi_Event when get_session_stats returns.
   procedure Append_Live_Turn_Footer
     (Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State;
      PID   : String);

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

   --  ── Edit diff helper ─────────────────────────────────────────────────

   --  Run `diff -u` on Old_Text vs New_Text, strip the ---/+++/@@ unified
   --  diff header lines, and return the remaining body lines joined by
   --  ASCII.LF.  Truncates to Max_L body lines (default 30) and appends a
   --  "… N more lines" trailer when the diff exceeds the limit.
   --
   --  Returns "(no changes)" when Old_Text = New_Text or when the diff
   --  produces no body lines.  Returns "(diff error)" if the `diff`
   --  subprocess cannot be started.
   --
   --  Matches the behaviour of the Python reference's edit_diff_lines().
   function Edit_Diff_Lines
     (Old_Text : String;
      New_Text : String;
      Max_L    : Positive := 30) return String;

   --  ── JSON display utilities ────────────────────────────────────────────

   --  Return a human-readable string for a scalar JSON value suitable for
   --  display in tool-call argument summaries.
   --
   --  Strings are returned as-is (no quotation marks).  Integers, booleans,
   --  and floats are serialised by GNATCOLL.JSON.Write (e.g. 42, true,
   --  3.14).  Null, object, and array values return "...".
   function JSON_Scalar_Image
     (Val : GNATCOLL.JSON.JSON_Value) return String;

   --  ── Tool call URI helpers ─────────────────────────────────────────────

   --  Return the first 16 hex characters of the SHA-256 digest of Tool_Id,
   --  matching the token computed by the Python reference implementation:
   --    hashlib.sha256(tool_id.encode()).hexdigest()[:16]
   function Hash_Tool_Id (Tool_Id : String) return String;

   --  Scan Context (a substring of the acme body starting at rune Ctx_Start)
   --  for a llm-chat+.../tool/... URI that contains rune position Anchor.
   --  Returns the first matching token string, or "" if none is found.
   --
   --  Token pattern:  llm-chat+ [0-9a-f-]+ /tool/ [0-9a-f]+
   --
   --  Local byte positions in Context are converted to approximate body rune
   --  offsets by adding Ctx_Start.  This is exact for the ASCII-only tokens
   --  this function scans for; any multi-byte UTF-8 characters that precede
   --  the token in the context window introduce only a small positive error
   --  that is acceptable for click-position matching.
   function Scan_Tool_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String;

   --  Scan Context for a fork+PID/SESSION-UUID/TURN-N token that contains
   --  rune position Anchor.  Returns the token string, or "".
   --
   --  Token pattern:  fork+ [0-9]+ / [0-9a-f-]+ / [0-9]+
   --
   --  The same ASCII-only approximation for rune offsets applies here.
   function Scan_Fork_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String;

end Pi_Acme_App;
