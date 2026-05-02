--  Pi_Acme_App body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;
with Nine_P;                 use Nine_P;
with Nine_P.Client;          use Nine_P.Client;
with Nine_P.Proto;
with Acme.Event_Parser;
with Acme.Raw_Events;
with Acme.Window;
with Pi_RPC;
with Pi_Acme_App.History;    use Pi_Acme_App.History;
with Pi_Acme_App.Dispatch;   use Pi_Acme_App.Dispatch;
with Pi_Acme_App.Utils;      use Pi_Acme_App.Utils;
with Session_Lister;         use Session_Lister;

package body Pi_Acme_App is

   --  POSIX getpid() — used to build window-specific selector tokens.
   function Getpid return Integer;
   pragma Import (C, Getpid, "getpid");

   --  ── App_State body ────────────────────────────────────────────────────

   protected body App_State is

      function Session_Id         return String  is
        (To_String (P_Session_Id));
      function Current_Model      return String  is
        (To_String (P_Model));
      function Current_Agent      return String  is
        (To_String (P_Agent));
      function Current_Thinking   return String  is
        (To_String (P_Thinking));
      function Is_Streaming       return Boolean is (P_Streaming);
      function Is_Compacting      return Boolean is (P_Compacting);
      function Was_Aborted        return Boolean is (P_Aborted);
      function Is_Retrying        return Boolean is (P_Is_Retrying);
      function Text_Emitted       return Boolean is (P_Text_Emitted);
      function Has_Tool_In_Turn return Boolean is (P_Has_Tool_In_Turn);
      function Pending_Stats      return Boolean is (P_Pending_Stats);
      function Models_Pending     return Boolean is (P_Models_Pending);
      function Context_Window     return Natural is (P_Ctx_Win);
      function Turn_Input_Tokens  return Natural is (P_Turn_In);
      function Turn_Output_Tokens return Natural is (P_Turn_Out);
      function Turn_Count         return Natural is (P_Turn_Count);
      function Turn_Cost_Dmil     return Natural is (P_Turn_Cost);
      function Session_Cost_Dmil  return Natural is (P_Sess_Cost);
      function Session_Input_Tokens  return Natural is (P_Sess_In);
      function Session_Output_Tokens return Natural is (P_Sess_Out);
      function Session_Cache_Read    return Natural is (P_Sess_Cache_R);
      function Session_Cache_Write   return Natural is (P_Sess_Cache_W);
      function Session_Total_Tokens  return Natural is (P_Sess_Total);
      function Win_Name           return String  is
        (To_String (P_Win_Name));

      procedure Set_Session_Id (Id : String) is
      begin
         P_Session_Id := To_Unbounded_String (Id);
      end Set_Session_Id;

      procedure Set_Model (Model : String) is
      begin
         P_Model := To_Unbounded_String (Model);
      end Set_Model;

      procedure Set_Agent (Agent : String) is
      begin
         P_Agent := To_Unbounded_String (Agent);
      end Set_Agent;

      procedure Set_Thinking (Level : String) is
      begin
         P_Thinking := To_Unbounded_String (Level);
      end Set_Thinking;

      procedure Set_Streaming (Value : Boolean) is
      begin
         P_Streaming := Value;
      end Set_Streaming;

      procedure Set_Compacting (Value : Boolean) is
      begin
         P_Compacting := Value;
      end Set_Compacting;

      procedure Set_Aborted (Value : Boolean) is
      begin
         P_Aborted := Value;
      end Set_Aborted;

      procedure Set_Is_Retrying (Value : Boolean) is
      begin
         P_Is_Retrying := Value;
      end Set_Is_Retrying;

      procedure Set_Text_Emitted (Value : Boolean) is
      begin
         P_Text_Emitted := Value;
      end Set_Text_Emitted;

      function Has_Text_Delta return Boolean is (P_Has_Text_Delta);

      procedure Set_Has_Text_Delta (Value : Boolean) is
      begin
         P_Has_Text_Delta := Value;
      end Set_Has_Text_Delta;

      procedure Set_Has_Tool_In_Turn (Value : Boolean) is
      begin
         P_Has_Tool_In_Turn := Value;
      end Set_Has_Tool_In_Turn;

      function Last_Stop_Reason return String is
        (To_String (P_Last_Stop_Reason));

      procedure Set_Last_Stop_Reason (Value : String) is
      begin
         P_Last_Stop_Reason := To_Unbounded_String (Value);
      end Set_Last_Stop_Reason;

      function Last_Error_Message return String is
        (To_String (P_Last_Error_Message));

      procedure Set_Last_Error_Message (Value : String) is
      begin
         P_Last_Error_Message := To_Unbounded_String (Value);
      end Set_Last_Error_Message;

      procedure Set_Pending_Stats (Value : Boolean) is
      begin
         P_Pending_Stats := Value;
      end Set_Pending_Stats;

      procedure Set_Models_Pending (Value : Boolean) is
      begin
         P_Models_Pending := Value;
      end Set_Models_Pending;

      procedure Set_Context_Window (N : Natural) is
      begin
         P_Ctx_Win := N;
      end Set_Context_Window;

      procedure Set_Turn_Tokens (Input, Output : Natural) is
      begin
         P_Turn_In  := Input;
         P_Turn_Out := Output;
      end Set_Turn_Tokens;

      procedure Set_Turn_Cost (Dmil : Natural) is
      begin
         P_Turn_Cost := Dmil;
      end Set_Turn_Cost;

      procedure Set_Session_Stats
        (Cost_Dmil   : Natural;
         Input       : Natural;
         Output      : Natural;
         Cache_Read  : Natural;
         Cache_Write : Natural;
         Total       : Natural)
      is
      begin
         P_Sess_Cost    := Cost_Dmil;
         P_Sess_In      := Input;
         P_Sess_Out     := Output;
         P_Sess_Cache_R := Cache_Read;
         P_Sess_Cache_W := Cache_Write;
         P_Sess_Total   := Total;
      end Set_Session_Stats;

      procedure Set_Win_Name (Name : String) is
      begin
         P_Win_Name := To_Unbounded_String (Name);
      end Set_Win_Name;

      procedure Increment_Turn_Count is
      begin
         P_Turn_Count := P_Turn_Count + 1;
      end Increment_Turn_Count;

      procedure Set_Turn_Count (N : Natural) is
      begin
         P_Turn_Count := N;
      end Set_Turn_Count;

      procedure Reset_Turn_Count is
      begin
         P_Turn_Count := 0;
      end Reset_Turn_Count;

      procedure Set_One_Shot_Result (Json : String) is
      begin
         --  First write wins; ignore subsequent calls so that the exception
         --  handler cannot clobber an already-captured success result.
         if Length (P_One_Shot_Result) = 0 then
            P_One_Shot_Result := To_Unbounded_String (Json);
         end if;
      end Set_One_Shot_Result;

      function One_Shot_Result return String is
      begin
         return To_String (P_One_Shot_Result);
      end One_Shot_Result;

      procedure Signal_Shutdown is
      begin
         P_Shutdown := True;
      end Signal_Shutdown;

      entry Wait_Shutdown when P_Shutdown is
      begin
         null;
      end Wait_Shutdown;

      procedure Request_Reload (UUID : String) is
      begin
         P_Reload_UUID      := To_Unbounded_String (UUID);
         P_Reload_Requested := True;
         P_Restart_Complete := False;
         P_Restart_Was_Done := False;
      end Request_Reload;

      procedure Consume_Reload
        (UUID          : out Ada.Strings.Unbounded.Unbounded_String;
         Was_Requested : out Boolean)
      is
      begin
         Was_Requested      := P_Reload_Requested;
         UUID               := P_Reload_UUID;
         P_Reload_Requested := False;
      end Consume_Reload;

      procedure Signal_Restart_Done is
      begin
         P_Restart_Was_Done := True;
         P_Restart_Complete := True;
      end Signal_Restart_Done;

      procedure Signal_Restart_Aborted is
      begin
         P_Restart_Was_Done := False;
         P_Restart_Complete := True;
      end Signal_Restart_Aborted;

      entry Wait_Restart_Complete (Was_Restarted : out Boolean)
        when P_Restart_Complete
      is
      begin
         Was_Restarted      := P_Restart_Was_Done;
         P_Restart_Complete := False;
         P_Restart_Was_Done := False;
      end Wait_Restart_Complete;

   end App_State;

   --  ── Run ───────────────────────────────────────────────────────────────

   procedure Run (Opts : Options) is

      --  Inject PI_ACME_BIN before spawning pi so the subagent extension
      --  can locate the pi_acme binary.  Locate_Exec_On_Path resolves a
      --  bare name via PATH; if that fails, fall back to Command_Name as
      --  invoked (which already contains a path when launched as
      --  ./bin/pi_acme or /usr/local/bin/pi_acme).
      function Inject_Pi_Acme_Bin return Boolean is
         use type GNAT.OS_Lib.String_Access;
         Ptr : GNAT.OS_Lib.String_Access :=
           GNAT.OS_Lib.Locate_Exec_On_Path (Ada.Command_Line.Command_Name);
      begin
         if Ptr /= null then
            Ada.Environment_Variables.Set ("PI_ACME_BIN", Ptr.all);
            GNAT.OS_Lib.Free (Ptr);
         else
            Ada.Environment_Variables.Set
              ("PI_ACME_BIN", Ada.Command_Line.Command_Name);
         end if;
         return True;
      end Inject_Pi_Acme_Bin;

      Env_Injected : constant Boolean := Inject_Pi_Acme_Bin;
      pragma Unreferenced (Env_Injected);

      --  Derive the bundled extension path: lib/pi_acme/subagent_window.ts
      --  sits one level above the binary directory.  Silently omitted if the
      --  file is absent (e.g. a development build before the post-build copy
      --  has run).
      function Subagent_Extension_Path return String is
         Bin_Path : constant String :=
           Ada.Environment_Variables.Value ("PI_ACME_BIN", "");
      begin
         if Bin_Path'Length = 0 then
            return "";
         end if;
         declare
            Bin_Dir    : constant String :=
              Ada.Directories.Containing_Directory (Bin_Path);
            Prefix_Dir : constant String :=
              Ada.Directories.Containing_Directory (Bin_Dir);
            Ext_Path   : constant String :=
              Prefix_Dir & "/lib/pi_acme/subagent_window.ts";
         begin
            return (if Ada.Directories.Exists (Ext_Path)
                    then Ext_Path
                    else "");
         end;
      end Subagent_Extension_Path;

      Cwd       : constant String := Ada.Strings.Fixed.Trim
        (Ada.Command_Line.Command_Name, Ada.Strings.Both);  --  placeholder
      Tag_Extra : constant String :=
        (if Opts.One_Shot
         then " | Stop Steer"
         else " | Send Stop Steer New Compact Clear"
              & " Models Sessions Thinking Stats");

      --  Process ID used to build window-specific selector tokens.
      My_PID : constant String := Natural_Image (Natural (Getpid));

      --  ── List_Sessions_Text ──────────────────────────────────────────
      --
      --  Returns one PID-tagged session token per line:
      --    llm-chat+PID/UUID<TAB>name<TAB>date<TAB>snippet
      --
      --  The PID prefix ensures that button-3 in the +sessions window
      --  routes the plumb message only to this pi-acme instance.
      --  Referencing My_PID directly avoids a redundant string build.
      function List_Sessions_Text return String is
         Sessions : constant Session_Vectors.Vector :=
           List_Sessions (Ada.Directories.Current_Directory);
         Result   : Unbounded_String;
      begin
         Append
           (Result,
            "# Button-3 any llm-chat+ token to load that session."
            & ASCII.LF & ASCII.LF);
         for Session of Sessions loop
            Append
              (Result,
               "llm-chat+" & My_PID & "/" & To_String (Session.UUID)
               & ASCII.HT & To_String (Session.Name)
               & ASCII.HT & To_String (Session.Date)
               & ASCII.HT & To_String (Session.Snippet)
               & ASCII.LF);
         end loop;
         return To_String (Result);
      end List_Sessions_Text;

      --  Shared objects — all tasks close over these:
      Win_FS : aliased Nine_P.Client.Fs  := Ns_Mount ("acme");
      Win    : Acme.Window.Win := Acme.Window.New_Win (Win_FS'Access);
      Proc   : Pi_RPC.Process  := Pi_RPC.Start
        (Session_Id    => To_String (Opts.Session_Id),
         Model         => To_String (Opts.Model),
         System_Prompt => To_String (Opts.Agent),
         No_Tools      => Opts.No_Tools,
         No_Session    => Opts.No_Session,
         Extension     => Subagent_Extension_Path);
      State  : App_State;

      --  ── Inner task declarations ────────────────────────────────────────

      task Pi_Stdout_Task;
      task Pi_Stderr_Task;
      task Acme_Event_Task;
      task Plumb_Model_Task;
      task Plumb_Session_Task;
      task Plumb_Thinking_Task;

      --  ── Pi_Stdout_Task ────────────────────────────────────────────────

      task body Pi_Stdout_Task is
         My_FS        : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Section      : Section_Kind             := No_Section;
         First_Boot   : Boolean                  := True;
         --  When non-empty, the top of Restart_Loop renders this session's
         --  history and shows a loading banner before bootstrapping pi.
         --  Seeded from the command-line --session option so that forked
         --  (and manually resumed) sessions display their conversation
         --  immediately; replenished by the reload path on each subsequent
         --  session switch.
         Pending_UUID : Unbounded_String         := Opts.Session_Id;
         --  True when Pending_UUID was set by the reload path rather than
         --  the initial startup.  Controls whether Signal_Restart_Done is
         --  called after the render to unblock Pi_Stderr_Task; the call is
         --  correct only when Pi_Stderr_Task is actually blocked on
         --  Wait_Restart_Complete, which only happens after its first
         --  stderr EOF (i.e. not during the very first boot).
         Is_Reload    : Boolean                  := False;

         --  ── One-shot tracking (Opts.One_Shot only) ────────────────────
         --  Prompt_Sent        — True once the --prompt message is sent.
         --  Was_Streaming      — previous loop iteration's Is_Streaming
         --                       value; used to detect the agent_end edge.
         --  Saw_Abort          — latches Was_Aborted from State *before*
         --                       Dispatch_Pi_Event clears it at agent_end.
         --  Awaiting_Last_Text — True between sending get_last_assistant_text
         --                       and receiving its response.
         --  One_Shot_Done      — True once the result is stored; causes an
         --                       early exit from Read_Loop.
         Prompt_Sent        : Boolean := False;
         Was_Streaming      : Boolean := False;
         Saw_Abort          : Boolean := False;
         Awaiting_Last_Text : Boolean := False;
         One_Shot_Done      : Boolean := False;
      begin
         Restart_Loop : loop

            --  ① Render phase — fires whenever a session UUID is pending.
            --  Handles both the initial --session startup and every live
            --  reload through a single code path.
            if Length (Pending_UUID) > 0 then
               declare
                  UUID_Str : constant String := To_String (Pending_UUID);
                  Short_Id : constant String :=
                    (if UUID_Str'Length >= 8
                     then UUID_Str (UUID_Str'First
                                    .. UUID_Str'First + 7)
                     else UUID_Str);
               begin
                  Acme.Window.Append
                    (Win, My_FS'Access,
                     ASCII.LF
                     & "[Loading session " & Short_Id & UC_ELLIP & "]"
                     & ASCII.LF);
                  Render_Session_History
                    (UUID  => UUID_Str,
                     Win   => Win,
                     FS    => My_FS'Access,
                     State => State);
               end;
               Pending_UUID := Null_Unbounded_String;
               --  For reloads: unblock Pi_Stderr_Task now that the new pi
               --  process is running and the history render is complete.
               --  Not called on first boot — Pi_Stderr_Task does not wait
               --  on Wait_Restart_Complete until after its first stderr EOF.
               if Is_Reload then
                  Is_Reload := False;
                  State.Signal_Restart_Done;
               end if;
            end if;

            --  ② Bootstrap phase: send get_state and get_session_stats;
            --  send set_model on first boot only (on a reload the model
            --  comes from the session).
            Pi_RPC.Send (Proc, "{""type"":""get_state""}");
            Pi_RPC.Send (Proc, "{""type"":""get_session_stats""}");
            if First_Boot then
               First_Boot := False;
               --  One-shot: disable auto-compaction so that an overflow
               --  does not cause pi to compact the context and silently
               --  re-send the prompt, which would trigger another agent
               --  turn and repeat indefinitely.  In one-shot mode the
               --  task is bounded; if the context is too large for the
               --  model the run should fail rather than loop.
               if Opts.One_Shot then
                  Pi_RPC.Send
                    (Proc,
                     "{""type"":""set_auto_compaction"","
                     & """enabled"":false}");
               end if;
               --  Send set_model only in interactive mode.  In one-shot
               --  mode --no-session is always active so pi starts with the
               --  correct model from the --model CLI flag; sending set_model
               --  would needlessly write to ~/.pi/agent/settings.json,
               --  overwriting the user's preferred default model whenever a
               --  subagent uses a different model.
               if To_String (Opts.Model) /= "" and then not Opts.One_Shot then
                  declare
                     Provider_End : Natural := 0;
                     Model_Spec   : constant String := To_String (Opts.Model);
                  begin
                     for I in Model_Spec'Range loop
                        if Model_Spec (I) = '/' then
                           Provider_End := I - 1;
                           exit;
                        end if;
                     end loop;
                     if Provider_End > 0 then
                        Pi_RPC.Send
                          (Proc,
                           "{""type"":""set_model"",""provider"":"""
                           & Model_Spec (Model_Spec'First .. Provider_End)
                           & """,""modelId"":"""
                           & Model_Spec (Provider_End + 2 .. Model_Spec'Last)
                           & """}");
                     end if;
                  end;
               end if;

               --  One-shot: send the initial prompt supplied via --prompt.
               if Opts.One_Shot
                 and then Length (Opts.Initial_Prompt) > 0
               then
                  declare
                     Prompt : constant String     :=
                       To_String (Opts.Initial_Prompt);
                     Msg    : constant JSON_Value := Create_Object;
                  begin
                     Acme.Window.Append
                       (Win, My_FS'Access,
                        ASCII.LF & UC_TRI_R & " " & Prompt & ASCII.LF);
                     Msg.Set_Field ("type",    Create ("prompt"));
                     Msg.Set_Field ("message", Create (Prompt));
                     Pi_RPC.Send (Proc, Write (Msg));
                     Prompt_Sent := True;
                  end;
               end if;
            end if;

            --  ③ Read phase: dispatch pi JSON events until EOF.
            Read_Loop : loop
               exit Read_Loop when One_Shot_Done;
               declare
                  Line : constant String := Pi_RPC.Read_Line (Proc);
               begin
                  exit Read_Loop when Line'Length = 0;
                  declare
                     Parse_Result : constant Read_Result := Read (Line);
                  begin
                     if Parse_Result.Success then
                        declare
                           Event : constant JSON_Value := Parse_Result.Value;
                           Kind  : constant String     :=
                             Get_String (Event, "type");
                        begin
                           --  One-shot: intercept the get_last_assistant_text
                           --  response before it reaches Dispatch_Pi_Event.
                           if Opts.One_Shot
                             and then Awaiting_Last_Text
                             and then Kind = "response"
                             and then Get_String (Event, "command")
                                      = "get_last_assistant_text"
                           then
                              Awaiting_Last_Text := False;
                              declare
                                 Data   : constant JSON_Value :=
                                   Get_Object (Event, "data");
                                 Output : constant String :=
                                   Get_String (Data, "text");
                                 Result : constant JSON_Value :=
                                   Create_Object;
                              begin
                                 if Output'Length > 0 then
                                    --  Non-empty text: this is the final
                                    --  turn.  Store the result and exit.
                                    Result.Set_Field
                                      ("session_id",
                                       Create (State.Session_Id));
                                    Result.Set_Field
                                      ("output", Create (Output));
                                    State.Set_One_Shot_Result
                                      (Write (Result));
                                    State.Signal_Shutdown;
                                    One_Shot_Done := True;
                                 end if;
                                 --  Empty output means the turn contained
                                 --  only tool calls or whitespace deltas
                                 --  (e.g. GPT-4.1 emits a blank line
                                 --  before tool_use blocks).  Do not exit:
                                 --  keep reading.  The next text-producing
                                 --  agent_end will trigger another fetch
                                 --  and eventually get real content.
                              end;

                           --  One-shot: a failed prompt response means pi
                           --  rejected the turn before emitting agent_start,
                           --  so agent_end will never arrive (e.g. missing
                           --  API key).  Let Dispatch_Pi_Event display the
                           --  ⚠ message as usual, then terminate.
                           elsif Opts.One_Shot
                             and then Prompt_Sent
                             and then Kind = "response"
                             and then Get_String (Event, "command") = "prompt"
                             and then not Get_Boolean (Event, "success")
                           then
                              Dispatch_Pi_Event
                                (Event,
                                 Win, My_FS'Access, State, Section, Proc,
                                 My_PID);
                              declare
                                 Err_Json : constant JSON_Value :=
                                   Create_Object;
                              begin
                                 Err_Json.Set_Field
                                   ("error",
                                    Create ("prompt failed: "
                                            & Get_String (Event, "error")));
                                 State.Set_One_Shot_Result (Write (Err_Json));
                              end;
                              State.Signal_Shutdown;
                              One_Shot_Done := True;

                           else
                              --  One-shot: latch Was_Aborted before
                              --  Dispatch_Pi_Event clears it at agent_end.
                              if Opts.One_Shot
                                and then Kind = "agent_end"
                              then
                                 Saw_Abort := State.Was_Aborted;
                              end if;

                              Dispatch_Pi_Event
                                (Event,
                                 Win, My_FS'Access, State, Section, Proc,
                                 My_PID);

                              --  One-shot: check for the agent_end edge
                              --  (Was_Streaming=True → Is_Streaming=False).
                              if Opts.One_Shot and then Prompt_Sent then
                                 if Was_Streaming
                                   and then not State.Is_Streaming
                                 then
                                    if Saw_Abort then
                                       State.Set_One_Shot_Result
                                         ("{""error"":""aborted""}");
                                       State.Signal_Shutdown;
                                       One_Shot_Done := True;
                                    elsif not State.Is_Retrying
                                      and then
                                        State.Last_Stop_Reason
                                        not in "stop" | "length"
                                      and then not State.Text_Emitted
                                    then
                                       --  Truly empty turn: nothing was
                                       --  shown (no text, no tool calls)
                                       --  and the last LLM call did not
                                       --  end normally.  The agent
                                       --  produced nothing useful.
                                       State.Set_One_Shot_Result
                                         ("{""error"":"
                                          & """No response from pi""}");
                                       State.Signal_Shutdown;
                                       One_Shot_Done := True;
                                    --  Final turn: the last LLM call ended
                                    --  with "stop" or "length", meaning the
                                    --  agent produced a text response.
                                    --  Fetch via get_last_assistant_text.
                                    --  Handles turns that mixed tool calls
                                    --  with a final text response.
                                    elsif not State.Is_Retrying
                                      and then
                                        (State.Last_Stop_Reason = "stop"
                                         or else
                                           State.Last_Stop_Reason = "length")
                                    then
                                       Pi_RPC.Send
                                         (Proc,
                                          "{""type"":"
                                          & """get_last_assistant_text""}");
                                       Awaiting_Last_Text := True;
                                    end if;
                                    Saw_Abort := False;
                                 end if;
                                 Was_Streaming := State.Is_Streaming;
                              end if;
                           end if;
                        end;
                     else
                        --  Non-JSON line on pi stdout — show it verbatim so
                        --  plain-text warnings or startup diagnostics are
                        --  visible rather than silently dropped.
                        Acme.Window.Append
                          (Win, My_FS'Access,
                           ASCII.LF & "[pi] " & Line & ASCII.LF);
                     end if;
                  end;
               end;
            end loop Read_Loop;

            --  ④ EOF phase: handle reload or exit.
            --  On reload: start the new pi process immediately (it stays
            --  silent until get_state is sent in the next iteration's
            --  bootstrap phase) and queue the render for the next iteration.
            declare
               UUID          : Unbounded_String;
               Was_Requested : Boolean;
            begin
               State.Consume_Reload (UUID, Was_Requested);
               if Was_Requested then
                  Pi_RPC.Restart (Proc, To_String (UUID));
                  State.Set_Is_Retrying (False);
                  Section      := No_Section;
                  Pending_UUID := UUID;
                  Is_Reload    := True;
                  --  Restart_Loop continues; render fires next iteration.
               else
                  --  Terminate pi (idempotent when it already exited).
                  --  Closing its pipes lets Pi_Stderr_Task reach EOF on
                  --  stderr and proceed to Wait_Restart_Complete.
                  Pi_RPC.Terminate_Process (Proc);
                  State.Signal_Restart_Aborted;
                  --  Tell the user pi has gone away (visible in the window
                  --  before Run deletes it).
                  Acme.Window.Append
                    (Win, My_FS'Access,
                     ASCII.LF & UC_WARN & " pi exited unexpectedly."
                     & ASCII.LF);
                  --  One-shot: record an error result so the spawning
                  --  extension receives a meaningful response.
                  --  Set_One_Shot_Result is a no-op when a result was already
                  --  stored by the normal agent_end path.
                  if Opts.One_Shot then
                     State.Set_One_Shot_Result
                       ("{""error"":""pi exited without producing output""}");
                  end if;
                  --  Wake Run unconditionally — the window is dead regardless
                  --  of mode.  Matches the exception-handler path above.
                  State.Signal_Shutdown;
                  exit Restart_Loop;
               end if;
            end;

         end loop Restart_Loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Pi_Stdout_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
            Acme.Window.Append
              (Win, My_FS'Access,
               ASCII.LF & UC_WARN & " Lost connection to pi." & ASCII.LF);
            --  One-shot: record a failure result so Run always has a JSON
            --  line to print; Set_One_Shot_Result is a no-op if a result
            --  was already stored.
            if Opts.One_Shot then
               State.Set_One_Shot_Result
                 ("{""error"":""pi connection lost""}");
            end if;
            State.Signal_Restart_Aborted;
            State.Signal_Shutdown;
      end Pi_Stdout_Task;

      --  ── Pi_Stderr_Task ────────────────────────────────────────────────

      task body Pi_Stderr_Task is
         My_FS : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
      begin
         Restart_Loop : loop
            Read_Loop : loop
               declare
                  Line : constant String := Pi_RPC.Read_Stderr_Line (Proc);
               begin
                  exit Read_Loop when Line'Length = 0;
                  Acme.Window.Append
                    (Win, My_FS'Access,
                     ASCII.LF & "[err] " & Line & ASCII.LF);
               end;
            end loop Read_Loop;
            --  EOF: wait for Pi_Stdout_Task to decide restart vs. shutdown.
            declare
               Was_Restarted : Boolean;
            begin
               State.Wait_Restart_Complete (Was_Restarted);
               exit Restart_Loop when not Was_Restarted;
               --  Pi was restarted: resume reading stderr of the new process.
            end;
         end loop Restart_Loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Pi_Stderr_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
      end Pi_Stderr_Task;

      --  ── Acme_Event_Task ───────────────────────────────────────────────
      --
      --  Opens the window event file directly via 9P and parses raw acme
      --  events using Acme.Raw_Events — no external acmeevent process.

      task body Acme_Event_Task is
         My_FS   : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Ev_File : aliased Nine_P.Client.File :=
           Open (My_FS'Access,
                 Acme.Window.Event_Path (Win),
                 O_READ);
         Parser       : Acme.Raw_Events.Event_Parser;
         --  Set to True when the ATC triggering alternative fires so the
         --  task can skip Signal_Shutdown (it was already called by the
         --  task that triggered the shutdown).
         Got_Shutdown : Boolean := False;

         --  Launch  llm-chat-open Token  and wait for it.
         --  On non-zero exit, appends a warning line to the window.
         procedure Run_Llm_Chat_Open (Token : String) is
            use GNATCOLL.OS.FS;
            use GNATCOLL.OS.Process;
            Null_In            : constant File_Descriptor :=
              Open (Null_File, Read_Mode);
            Stderr_R, Stderr_W : File_Descriptor;
            Args               : Argument_List;
            Handle             : Process_Handle;
            Exit_Code          : Integer;
         begin
            Open_Pipe (Stderr_R, Stderr_W);
            Args.Append ("llm-chat-open");
            Args.Append (Token);
            Handle := Start (Args   => Args,
                             Stdin  => Null_In,
                             Stdout => Stderr_W,
                             Stderr => Stderr_W);
            Close (Null_In);
            Close (Stderr_W);
            Exit_Code := Wait (Handle);
            if Exit_Code /= 0 then
               declare
                  Buffer  : String (1 .. 256);
                  Bytes   : Integer;
                  Err_Msg : Unbounded_String;
               begin
                  loop
                     Bytes := Read (Stderr_R, Buffer);
                     exit when Bytes <= 0;
                     Append (Err_Msg, Buffer (1 .. Bytes));
                  end loop;
                  if Length (Err_Msg) > 0 then
                     Acme.Window.Append
                       (Win, My_FS'Access,
                        ASCII.LF & UC_WARN & " llm-chat-open: "
                        & To_String (Err_Msg) & ASCII.LF);
                  end if;
               end;
            end if;
            Close (Stderr_R);
         exception
            when Ex : others =>
               Acme.Window.Append
                 (Win, My_FS'Access,
                  ASCII.LF & UC_WARN & " llm-chat-open error: "
                  & Ada.Exceptions.Exception_Message (Ex) & ASCII.LF);
         end Run_Llm_Chat_Open;

         --  Scan a ±200-rune context window around the click position for
         --  a llm-chat+.../tool/... URI.  If found and the click lands
         --  within the token, launch llm-chat-open and return True.
         function Try_Open_Tool_URI
           (Ev : Acme.Event_Parser.Event) return Boolean
         is
            Anchor    : constant Natural :=
              (if Ev.Eq1 > Ev.Eq0
               then (Ev.Eq0 + Ev.Eq1) / 2
               else Ev.Q0);
            Ctx_Start : constant Natural :=
              (if Anchor > 200 then Anchor - 200 else 0);
            Ctx_End   : constant Natural := Anchor + 200;
         begin
            --  Read_Chars and Scan_Tool_Token are inside a block so that
            --  any P9_Error raised during their elaboration is caught by
            --  the outer "when others" handler below.  (Exceptions raised
            --  during a subprogram body's own declarative-part elaboration
            --  bypass that body's handlers per Ada RM 11.4.)
            declare
               Context : constant String :=
                 Acme.Window.Read_Chars
                   (Win, My_FS'Access, Ctx_Start, Ctx_End);
               Token   : constant String :=
                 Scan_Tool_Token (Context, Ctx_Start, Anchor);
            begin
               if Token'Length = 0 then
                  return False;
               end if;
               Run_Llm_Chat_Open (Token);
               return True;
            end;
         exception
            when others =>
               return False;
         end Try_Open_Tool_URI;

         --  Spawn a new pi_acme window containing the session history of
         --  UUID truncated after After_Turn complete turns.
         procedure Fork_And_Open (UUID : String; After_Turn : Positive) is
            use GNATCOLL.OS.FS;
            use GNATCOLL.OS.Process;
            Cwd      : constant String := Ada.Directories.Current_Directory;
            New_UUID : constant String :=
              Session_Lister.Fork_Session (UUID, After_Turn, Cwd);
            Null_FD  : File_Descriptor;
            Args     : Argument_List;
            Handle   : Process_Handle;
            pragma Unreferenced (Handle);
         begin
            if New_UUID'Length = 0 then
               Acme.Window.Append
                 (Win, My_FS'Access,
                  ASCII.LF & UC_WARN & " Fork failed (turn "
                  & Natural_Image (After_Turn) & " not found in session)."
                  & ASCII.LF);
               return;
            end if;
            Null_FD := Open (Null_File, Read_Mode);
            Args.Append (Ada.Command_Line.Command_Name);
            Args.Append ("--session");
            Args.Append (New_UUID);
            Handle := Start (Args   => Args,
                             Stdin  => Null_FD,
                             Stdout => Null_FD,
                             Stderr => Null_FD,
                             Cwd    => Cwd);
            Close (Null_FD);
            Acme.Window.Append
              (Win, My_FS'Access,
               ASCII.LF & "[Forked -> "
               & New_UUID (New_UUID'First .. New_UUID'First + 7)
               & "...]" & ASCII.LF);
         exception
            when Ex : others =>
               Acme.Window.Append
                 (Win, My_FS'Access,
                  ASCII.LF & UC_WARN & " Fork_And_Open: "
                  & Ada.Exceptions.Exception_Message (Ex) & ASCII.LF);
         end Fork_And_Open;

         --  Scan a ±200-rune context window around the click for a
         --  fork+PID/UUID/N token.  If found and the PID matches this
         --  process, call Fork_And_Open and return True.
         function Try_Fork_URI
           (Ev : Acme.Event_Parser.Event) return Boolean
         is
            Anchor    : constant Natural :=
              (if Ev.Eq1 > Ev.Eq0
               then (Ev.Eq0 + Ev.Eq1) / 2
               else Ev.Q0);
            Ctx_Start : constant Natural :=
              (if Anchor > 200 then Anchor - 200 else 0);
            Ctx_End   : constant Natural := Anchor + 200;
         begin
            --  Read_Chars and Scan_Fork_Token are inside a block so that
            --  any P9_Error raised during their elaboration is caught by
            --  the outer "when others" handler below.  (Exceptions raised
            --  during a subprogram body's own declarative-part elaboration
            --  bypass that body's handlers per Ada RM 11.4.)
            declare
               Context : constant String :=
                 Acme.Window.Read_Chars
                   (Win, My_FS'Access, Ctx_Start, Ctx_End);
               Token   : constant String :=
                 Scan_Fork_Token (Context, Ctx_Start, Anchor);
            begin
               if Token'Length = 0 then
                  return False;
               end if;
               --  Parse "fork+PID/UUID/N" — split on the first and last '/'.
               declare
                  After_Plus  : constant Natural := Token'First + 5;
                  First_Slash : Natural          := 0;
                  Last_Slash  : Natural          := 0;
               begin
                  for I in After_Plus .. Token'Last loop
                     if Token (I) = '/' then
                        if First_Slash = 0 then
                           First_Slash := I;
                        end if;
                        Last_Slash := I;
                     end if;
                  end loop;
                  if First_Slash = 0 or else First_Slash = Last_Slash then
                     return False;
                  end if;
                  declare
                     Token_PID : constant String :=
                       Token (After_Plus .. First_Slash - 1);
                     Sess_UUID : constant String :=
                       Token (First_Slash + 1 .. Last_Slash - 1);
                     Turn_Str  : constant String :=
                       Token (Last_Slash + 1 .. Token'Last);
                     Turn_N    : Positive;
                  begin
                     --  Only handle tokens addressed to this process.
                     if Token_PID /= My_PID then
                        return False;
                     end if;
                     Turn_N := Positive'Value (Turn_Str);
                     Fork_And_Open (Sess_UUID, Turn_N);
                     return True;
                  exception
                     when Constraint_Error =>
                        return False;
                  end;
               end;
            end;
         exception
            when others =>
               return False;
         end Try_Fork_URI;

      begin
         Event_Loop : loop
            --  Wrap each blocking read in an ATC select so that
            --  Signal_Shutdown (from any task) immediately unblocks this
            --  task rather than leaving it stuck in a 9P read forever.
            select
               State.Wait_Shutdown;
               Got_Shutdown := True;
            then abort
               declare
                  Data : constant Byte_Array :=
                    Read_Once (Ev_File'Access);
               begin
                  exit Event_Loop when Data'Length = 0;
                  Acme.Raw_Events.Feed (Parser, Data);
                  loop
                     declare
                        Ev : Acme.Event_Parser.Event;
                     begin
                        exit when not
                          Acme.Raw_Events.Next_Event (Parser, Ev);
                        declare
                           C2   : constant Character := Ev.C2;
                           Text : constant String    :=
                             Ada.Strings.Fixed.Trim
                               (To_String (Ev.Text), Ada.Strings.Both);
                        begin
                           if C2 in 'X' | 'x' then
                              if Text = "Send" then
                                 declare
                                    Sel : constant String :=
                                      Acme.Window.Selection_Text
                                        (Win, My_FS'Access);
                                 begin
                                    if Sel'Length > 0 then
                                       if State.Is_Streaming
                                         or else State.Is_Retrying
                                       then
                                          Acme.Window.Append
                                            (Win, My_FS'Access,
                                             ASCII.LF & UC_WARN
                                             & " Agent is running"
                                             & (if State.Is_Retrying
                                                then " (retrying)"
                                                else "")
                                             & " -- use Steer to redirect"
                                             & " or Stop first."
                                             & ASCII.LF);
                                       else
                                          Acme.Window.Append
                                            (Win, My_FS'Access,
                                             ASCII.LF & UC_TRI_R
                                             & " " & Sel & ASCII.LF);
                                          declare
                                             Msg : constant JSON_Value :=
                                               Create_Object;
                                          begin
                                             Msg.Set_Field
                                               ("type", Create ("prompt"));
                                             Msg.Set_Field
                                               ("message", Create (Sel));
                                             Pi_RPC.Send
                                               (Proc, Write (Msg));
                                          end;
                                       end if;
                                    end if;
                                 end;
                              elsif Text = "Stop" then
                                 Pi_RPC.Send
                                   (Proc, "{""type"":""abort""}");
                              elsif Text = "Steer" then
                                 declare
                                    Sel : constant String :=
                                      Acme.Window.Selection_Text
                                        (Win, My_FS'Access);
                                 begin
                                    if Sel'Length > 0 then
                                       Acme.Window.Append
                                         (Win, My_FS'Access,
                                          ASCII.LF & UC_HOOK_L
                                          & " Steer: " & Sel & ASCII.LF);
                                       declare
                                          Msg : constant JSON_Value :=
                                            Create_Object;
                                       begin
                                          Msg.Set_Field
                                            ("type", Create ("prompt"));
                                          Msg.Set_Field
                                            ("message", Create (Sel));
                                          Msg.Set_Field
                                            ("streamingBehavior",
                                             Create ("steer"));
                                          Pi_RPC.Send
                                            (Proc, Write (Msg));
                                       end;
                                    end if;
                                 end;
                              elsif Text = "New" then
                                 Pi_RPC.Send
                                   (Proc, "{""type"":""new_session""}");
                                 Acme.Window.Append
                                   (Win, My_FS'Access,
                                    ASCII.LF
                                    & UC_HORIZ & UC_HORIZ & " New session "
                                    & UC_HORIZ & UC_HORIZ & ASCII.LF);
                              elsif Text = "Compact" then
                                 --  Guard: do not compact while the agent is
                                 --  streaming or a compaction is
                                 --  already running.
                                 if not State.Is_Streaming
                                   and then not State.Is_Compacting
                                 then
                                    State.Set_Compacting (True);
                                    Acme.Window.Append
                                      (Win, My_FS'Access,
                                       ASCII.LF & UC_GEAR
                                       & " Compacting context"
                                       & UC_ELLIP & ASCII.LF);
                                    Acme.Window.Replace_Line1
                                      (Win, My_FS'Access,
                                       Format_Status (State, "compacting"));
                                    Pi_RPC.Send
                                      (Proc, "{""type"":""compact""}");
                                 end if;
                              elsif Text = "Clear" then
                                 Acme.Window.Replace_Match
                                   (Win, My_FS'Access, "1,$", "");
                                 Acme.Window.Append
                                   (Win, My_FS'Access,
                                    Format_Status (State, "ready")
                                    & ASCII.LF);
                              elsif Text = "Models" then
                                 --  Request the list of models from the
                                 --  running pi process.  Only models for
                                 --  which an API key is configured are
                                 --  returned.  The response handler in
                                 --  Dispatch_Pi_Event opens the sub-window.
                                 State.Set_Models_Pending (True);
                                 Pi_RPC.Send
                                   (Proc,
                                    "{""type"":""get_available_models""}");
                              elsif Text = "Sessions" then
                                 declare
                                    Parent  : constant String :=
                                      Ada.Directories.Current_Directory
                                      & "/+pi";
                                    Content : constant String :=
                                      List_Sessions_Text;
                                 begin
                                    Open_Sub_Window
                                      (My_FS'Access, Parent, "+sessions",
                                       (if Content'Length > 0
                                        then Content
                                        else "(no sessions found)"
                                             & ASCII.LF));
                                 end;
                              elsif Text = "Thinking" then
                                 declare
                                    Parent  : constant String :=
                                      Ada.Directories.Current_Directory
                                      & "/+pi";
                                    Content : constant String :=
                                      "thinking+" & My_PID
                                      & "/low"    & ASCII.LF
                                      & "thinking+" & My_PID
                                      & "/medium" & ASCII.LF
                                      & "thinking+" & My_PID
                                      & "/high"   & ASCII.LF;
                                 begin
                                    Open_Sub_Window
                                      (My_FS'Access, Parent,
                                       "+thinking", Content);
                                 end;
                              elsif Text = "Stats" then
                                 declare
                                    Parent    : constant String :=
                                      Ada.Directories.Current_Directory
                                      & "/+pi";
                                    Turn_In   : constant Natural :=
                                      State.Turn_Input_Tokens;
                                    Turn_Out  : constant Natural :=
                                      State.Turn_Output_Tokens;
                                    Ctx_Win   : constant Natural :=
                                      State.Context_Window;
                                    Sess_In   : constant Natural :=
                                      State.Session_Input_Tokens;
                                    Sess_Out  : constant Natural :=
                                      State.Session_Output_Tokens;
                                    Sess_CR   : constant Natural :=
                                      State.Session_Cache_Read;
                                    Sess_CW   : constant Natural :=
                                      State.Session_Cache_Write;
                                    Sess_Tot  : constant Natural :=
                                      State.Session_Total_Tokens;
                                    Sess_Cost : constant Natural :=
                                      State.Session_Cost_Dmil;
                                    Buf       : Unbounded_String;
                                 begin
                                    Append
                                      (Buf,
                                       "# Session statistics"
                                       & ASCII.LF & ASCII.LF);
                                    Append
                                      (Buf,
                                       "Session:  "
                                       & State.Session_Id & ASCII.LF);
                                    if State.Current_Model'Length > 0 then
                                       Append
                                         (Buf,
                                          "Model:    "
                                          & State.Current_Model);
                                       if Ctx_Win > 0 then
                                          Append
                                            (Buf,
                                             " ("
                                             & Format_Kilo (Ctx_Win)
                                             & " ctx)");
                                       end if;
                                       Append (Buf, "" & ASCII.LF);
                                    end if;
                                    if State.Current_Thinking'Length > 0 then
                                       Append
                                         (Buf,
                                          "Thinking: "
                                          & State.Current_Thinking
                                          & ASCII.LF);
                                    end if;
                                    Append (Buf, "" & ASCII.LF);
                                    --  Session-level cumulative breakdown.
                                    if Sess_Tot > 0 then
                                       Append
                                         (Buf,
                                          "Tokens this session:" & ASCII.LF);
                                       Append
                                         (Buf,
                                          "  Input:        "
                                          & Natural_Image (Sess_In)
                                          & ASCII.LF);
                                       Append
                                         (Buf,
                                          "  Output:       "
                                          & Natural_Image (Sess_Out)
                                          & ASCII.LF);
                                       if Sess_CR > 0 then
                                          Append
                                            (Buf,
                                             "  Cache read:   "
                                             & Natural_Image (Sess_CR)
                                             & ASCII.LF);
                                       end if;
                                       if Sess_CW > 0 then
                                          Append
                                            (Buf,
                                             "  Cache write:  "
                                             & Natural_Image (Sess_CW)
                                             & ASCII.LF);
                                       end if;
                                       Append
                                         (Buf,
                                          "  Total:        "
                                          & Natural_Image (Sess_Tot)
                                          & ASCII.LF);
                                       if Sess_Cost > 0 then
                                          Append
                                            (Buf,
                                             ASCII.LF & "Cost:     "
                                             & Format_Cost (Sess_Cost)
                                             & ASCII.LF);
                                       end if;
                                    else
                                       Append
                                         (Buf,
                                          "(No statistics yet"
                                          & " -- complete a turn first.)"
                                          & ASCII.LF);
                                    end if;
                                    --  Per-turn data from the most
                                    --  recent turn.
                                    if Turn_In > 0 or else Turn_Out > 0 then
                                       Append
                                         (Buf,
                                          ASCII.LF & "Last turn:" & ASCII.LF);
                                       if Turn_Out > 0 then
                                          Append
                                            (Buf,
                                             "  Output:  "
                                             & Natural_Image (Turn_Out)
                                             & ASCII.LF);
                                       end if;
                                       if Turn_In > 0
                                         and then Ctx_Win > 0
                                       then
                                          Append
                                            (Buf,
                                             "  Context: "
                                             & Natural_Image (Turn_In)
                                             & "/"
                                             & Natural_Image (Ctx_Win)
                                             & " ("
                                             & Natural_Image
                                                 (Turn_In * 100 / Ctx_Win)
                                             & "%)" & ASCII.LF);
                                       end if;
                                    end if;
                                    Open_Sub_Window
                                      (My_FS'Access, Parent, "+stats",
                                       To_String (Buf));
                                 end;
                              else
                                 Acme.Window.Send_Event
                                   (Win, My_FS'Access,
                                    Ev.C1, Ev.C2, Ev.Q0, Ev.Q1);
                              end if;
                           elsif C2 in 'L' | 'l' then
                              --  Try to find a llm-chat+.../tool/... URI near
                              --  the click before falling back to the plumber.
                              --  acme's expand() stops at punctuation, so many
                              --  click positions on the URI send no event at
                              --  all or send a truncated token; we work around
                              --  this by reading a small context window and
                              --  scanning for the pattern ourselves.
                              if not Try_Fork_URI (Ev)
                                and then not Try_Open_Tool_URI (Ev)
                              then
                                 Acme.Window.Send_Event
                                   (Win, My_FS'Access,
                                    Ev.C1, Ev.C2, Ev.Q0, Ev.Q1);
                              end if;
                           end if;
                        end;
                     end;
                  end loop;
               end;
            end select;
            exit Event_Loop when Got_Shutdown;
         end loop Event_Loop;
         --  Normal exit: window closed or EOF.  Signal the main task.
         State.Signal_Shutdown;
      exception
         when Ex : Nine_P.Proto.P9_Error =>
            --  "deleted window" is the normal error returned by the acme
            --  9P server when the user closes the window; treat it as a
            --  clean exit rather than a fault.
            if Ada.Exceptions.Exception_Message (Ex) /= "deleted window" then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "Acme_Event_Task terminated: "
                  & Ada.Exceptions.Exception_Information (Ex));
            end if;
            State.Signal_Shutdown;
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Acme_Event_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
            State.Signal_Shutdown;
      end Acme_Event_Task;

      --  ── Plumb_Model_Task ──────────────────────────────────────────────

      task body Plumb_Model_Task is
         Pl_FS        : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         My_FS        : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         Port         : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-model", O_READ);
         Got_Shutdown : Boolean := False;
      begin
         Plumb_Loop : loop
            select
               State.Wait_Shutdown;
               Got_Shutdown := True;
            then abort
               declare
                  Raw  : constant Byte_Array :=
                    Nine_P.Client.Read_Once (Port'Access);
                  Data : constant String := Extract_Plumb_Data (Raw);
               begin
                  exit Plumb_Loop when Raw'Length = 0;
                  --  Token format: model+PID/PROVIDER/MODELID
                  --  Only handle messages destined for this process.
                  if Data'Length > 0 then
                     declare
                        First_Slash : Natural := 0;
                     begin
                        for I in Data'Range loop
                           if Data (I) = '/' then
                              First_Slash := I;
                              exit;
                           end if;
                        end loop;
                        if First_Slash > 0
                          and then Data (Data'First .. First_Slash - 1)
                                   = "model+" & My_PID
                        then
                           --  Rest is PROVIDER/MODELID — split on next '/'.
                           declare
                              Rest         : constant String :=
                                Data (First_Slash + 1 .. Data'Last);
                              Second_Slash : Natural := 0;
                           begin
                              for I in Rest'Range loop
                                 if Rest (I) = '/' then
                                    Second_Slash := I;
                                    exit;
                                 end if;
                              end loop;
                              if Second_Slash > 0 then
                                 declare
                                    Provider : constant String :=
                                      Rest (Rest'First
                                            .. Second_Slash - 1);
                                    Model_Id : constant String :=
                                      Rest (Second_Slash + 1
                                            .. Rest'Last);
                                 begin
                                    Pi_RPC.Send
                                      (Proc,
                                       "{""type"":""set_model"","
                                       & """provider"":"""
                                       & Provider & ""","
                                       & """modelId"":"""
                                       & Model_Id & """}");
                                    Acme.Window.Append
                                      (Win, My_FS'Access,
                                       ASCII.LF & "[Model -> " & Rest
                                       & "]" & ASCII.LF);
                                 end;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end select;
            exit Plumb_Loop when Got_Shutdown;
         end loop Plumb_Loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Plumb_Model_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
      end Plumb_Model_Task;

      --  ── Plumb_Session_Task ────────────────────────────────────────────
      --
      --  Reads the pi-session plumb port.  Tokens written by our own
      --  +sessions window are PID-tagged ("llm-chat+PID/UUID"); bare
      --  "llm-chat+UUID" tokens (no PID, backward-compat) are also
      --  accepted.  Tokens belonging to other pi-acme instances are
      --  silently ignored.

      task body Plumb_Session_Task is
         Pl_FS        : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         Pid_Prefix   : constant String             :=
           "llm-chat+" & My_PID & "/";
         Port         : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-session", O_READ);
         Got_Shutdown : Boolean := False;
      begin
         Plumb_Loop : loop
            select
               State.Wait_Shutdown;
               Got_Shutdown := True;
            then abort
               declare
                  Raw  : constant Byte_Array :=
                    Nine_P.Client.Read_Once (Port'Access);
                  Data : constant String := Extract_Plumb_Data (Raw);
               begin
                  exit Plumb_Loop when Raw'Length = 0;
                  if Data'Length > 0 then
                     declare
                        UUID : constant String :=
                          Parse_Session_Token (Data, Pid_Prefix);
                     begin
                        if UUID'Length > 0 then
                           --  Signal reload and terminate pi;
                           --  Pi_Stdout_Task will call Pi_RPC.Restart
                           --  once it gets EOF.
                           State.Request_Reload (UUID);
                           Pi_RPC.Terminate_Process (Proc);
                        end if;
                     end;
                  end if;
               end;
            end select;
            exit Plumb_Loop when Got_Shutdown;
         end loop Plumb_Loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Plumb_Session_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
      end Plumb_Session_Task;

      --  ── Plumb_Thinking_Task ───────────────────────────────────────────

      task body Plumb_Thinking_Task is
         Pl_FS        : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         My_FS        : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         Port         : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-thinking", O_READ);
         Got_Shutdown : Boolean := False;
      begin
         Plumb_Loop : loop
            select
               State.Wait_Shutdown;
               Got_Shutdown := True;
            then abort
               declare
                  Raw   : constant Byte_Array :=
                    Nine_P.Client.Read_Once (Port'Access);
                  Level : constant String := Extract_Plumb_Data (Raw);
               begin
                  exit Plumb_Loop when Raw'Length = 0;
                  if Level'Length > 0 then
                     --  Token format: "thinking+PID/level"
                     --  Find the last '/' to split PID from level.
                     declare
                        Slash : Natural := 0;
                     begin
                        for I in reverse Level'Range loop
                           if Level (I) = '/' then
                              Slash := I;
                              exit;
                           end if;
                        end loop;
                        declare
                           Plus_Pos  : Natural := 0;
                           Token_PID : Unbounded_String;
                        begin
                           for I in Level'Range loop
                              if Level (I) = '+' then
                                 Plus_Pos := I;
                                 exit;
                              end if;
                           end loop;
                           if Plus_Pos > 0 and then Slash > Plus_Pos then
                              Token_PID :=
                                To_Unbounded_String
                                  (Level (Plus_Pos + 1 .. Slash - 1));
                           end if;
                           if To_String (Token_PID) = My_PID then
                              declare
                                 Parsed : constant String :=
                                   (if Slash > 0
                                    then Level (Slash + 1 .. Level'Last)
                                    else Level);
                              begin
                                 State.Set_Thinking (Parsed);
                                 Pi_RPC.Send
                                   (Proc,
                                    "{""type"":""set_thinking_level"","
                                    & """level"":""" & Parsed & """}");
                                 Acme.Window.Append
                                   (Win, My_FS'Access,
                                    ASCII.LF & "[Thinking -> "
                                    & Parsed & "]" & ASCII.LF);
                              end;
                           end if;
                        end;
                     end;
                  end if;
               end;
            end select;
            exit Plumb_Loop when Got_Shutdown;
         end loop Plumb_Loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Plumb_Thinking_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
      end Plumb_Thinking_Task;

      pragma Unreferenced (Cwd);

   begin
      --  ── Initial window setup ──────────────────────────────────────────
      Acme.Window.Ctl (Win, Win_FS'Access, "cleartag");
      Acme.Window.Append_Tag (Win, Win_FS'Access, Tag_Extra);
      Acme.Window.Set_Name
        (Win, Win_FS'Access,
         Ada.Directories.Current_Directory & "/+pi"
         & (if Length (Opts.Name) > 0
            then ":" & To_String (Opts.Name)
            else ""));
      Acme.Window.Append
        (Win, Win_FS'Access, UC_BULLET & " starting..." & ASCII.LF);
      Acme.Window.Ctl (Win, Win_FS'Access, "clean");

      --  ── Wait for window-closed shutdown ───────────────────────────────
      State.Wait_Shutdown;

      --  ── One-shot teardown ─────────────────────────────────────────────
      --  Print the JSON result line for the spawning extension to read.
      --  If no result was stored (e.g. the user closed the window
      --  manually), emit a generic error object.
      if Opts.One_Shot then
         declare
            Json : constant String := State.One_Shot_Result;
         begin
            Ada.Text_IO.Put_Line
              (if Json'Length > 0
               then Json
               else "{""error"":""subagent closed before producing output""}");
         end;
      end if;

      --  Close the acme window on every exit path.  Silently ignore errors:
      --  the window is already gone when the user closed it manually.
      begin
         Acme.Window.Ctl (Win, Win_FS'Access, "delete");
      exception
         when others => null;  --  window may already be gone
      end;
   end Run;

end Pi_Acme_App;
