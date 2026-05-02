--  Pi_Acme_App.Dispatch body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with Nine_P.Client;          use Nine_P.Client;
with Pi_Acme_App.Utils;      use Pi_Acme_App.Utils;

package body Pi_Acme_App.Dispatch is

   --  Build the one-line status string.
   function Format_Status
     (State : App_State;
      Extra : String := "ready") return String
   is
      Model_Text   : constant String  := State.Current_Model;
      Agent_Text   : constant String  := State.Current_Agent;
      Session_Text : constant String  := State.Session_Id;
      Think_Text   : constant String  := State.Current_Thinking;
      Input_Tokens : constant Natural := State.Turn_Input_Tokens;
      Ctx_Window   : constant Natural := State.Context_Window;

      Model_Part   : constant String :=
        (if Model_Text'Length > 0
         then " [" & Model_Text & "]"
         else "");
      Agent_Part   : constant String :=
        (if Agent_Text'Length > 0
         then " <" & Agent_Stem (Agent_Text) & ">"
         else "");
      Think_Part   : constant String :=
        (if Think_Text'Length > 0 then " ~" & Think_Text else "");
      Session_Part : constant String :=
        (if Session_Text'Length >= 8
         then " session:"
              & Session_Text (Session_Text'First
                               .. Session_Text'First + 7)
         else "");
      Context_Part : constant String :=
        (if Input_Tokens > 0 and then Ctx_Window > 0
         then " " & Format_Kilo (Input_Tokens)
              & "/" & Format_Kilo (Ctx_Window)
              & " (" & Natural_Image (Input_Tokens * 100 / Ctx_Window)
              & "%)"
         else "");
   begin
      return UC_BULLET & " " & Extra
             & Agent_Part & Model_Part & Think_Part
             & Context_Part & Session_Part;
   end Format_Status;

   --  Append a live turn footer using the current state fields and advance
   --  the turn counter.
   procedure Append_Live_Turn_Footer
     (Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State;
      PID   : String)
   is
      Input_Tokens      : constant Natural :=
        State.Turn_Input_Tokens;
      Output_Tokens     : constant Natural :=
        State.Turn_Output_Tokens;
      Ctx_Window        : constant Natural :=
        State.Context_Window;
      Model_Text        : constant String  :=
        State.Current_Model;
      Turn_Cost_Dmil    : constant Natural :=
        State.Turn_Cost_Dmil;
      Session_Cost_Dmil : constant Natural :=
        State.Session_Cost_Dmil;
   begin
      State.Increment_Turn_Count;
      Acme.Window.Append
        (Win, FS,
         Format_Turn_Footer
           (Turn_N            => State.Turn_Count,
            UUID              => State.Session_Id,
            PID               => PID,
            Input_Tokens      => Input_Tokens,
            Output_Tokens     => Output_Tokens,
            Ctx_Window        => Ctx_Window,
            Model_Text        => Model_Text,
            Turn_Cost_Dmil    => Turn_Cost_Dmil,
            Session_Cost_Dmil => Session_Cost_Dmil));
   end Append_Live_Turn_Footer;

   --  ── Open_Sub_Window ───────────────────────────────────────────────────
   --
   --  Create a new acme window named  Parent/Sub, write Content, mark clean.

   procedure Open_Sub_Window
     (FS      : not null access Nine_P.Client.Fs;
      Parent  : String;
      Sub     : String;
      Content : String)
   is
      W : Acme.Window.Win := Acme.Window.New_Win (FS);
   begin
      Acme.Window.Set_Name (W, FS, Parent & "/" & Sub);
      if Content'Length > 0 then
         Acme.Window.Append (W, FS, Content);
      end if;
      Acme.Window.Ctl (W, FS, "clean");
   exception
      when Ex : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "Open_Sub_Window failed: "
            & Ada.Exceptions.Exception_Information (Ex));
   end Open_Sub_Window;

   procedure Dispatch_Pi_Event
     (Event   :        JSON_Value;
      Win     : in out Acme.Window.Win;
      FS      : not null access Nine_P.Client.Fs;
      State   : in out App_State;
      Section : in out Section_Kind;
      Proc    : in out Pi_RPC.Process;
      PID     :        String)
   is
      Kind : constant String := Get_String (Event, "type");
   begin

      --  ── agent_start ───────────────────────────────────────────────────
      if Kind = "agent_start" then
         State.Set_Streaming (True);
         State.Set_Text_Emitted (False);
         State.Set_Has_Text_Delta (False);
         State.Set_Has_Tool_In_Turn (False);
         State.Set_Last_Stop_Reason ("");
         State.Set_Last_Error_Message ("");
         Section := No_Section;
         Acme.Window.Replace_Line1
           (Win, FS, Format_Status (State, "running"));

      --  ── agent_end ─────────────────────────────────────────────────────
      elsif Kind = "agent_end" then
         State.Set_Streaming (False);
         Section := No_Section;
         if State.Was_Aborted then
            Acme.Window.Append
              (Win, FS, ASCII.LF & "[STOP] Aborted." & ASCII.LF);
            State.Set_Aborted (False);
         elsif not State.Text_Emitted
           and then not State.Is_Retrying
         then
            --  No text and no retry in flight: either the context is too
            --  long (the most common cause) or a non-retryable error
            --  occurred.  If auto-retry is handling a transient API error
            --  it will emit auto_retry_start right after this event, which
            --  sets Is_Retrying and suppresses this message on all
            --  subsequent retry attempts.
            declare
               Err_Msg : constant String := State.Last_Error_Message;
            begin
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF
                  & UC_WARN
                  & " No response from pi"
                  & (if Err_Msg'Length > 0
                     then ": " & Err_Msg
                     else " -- context may be too long, or a temporary"
                          & " error occurred. Try New.")
                  & ASCII.LF);
            end;
         end if;
         --  Emit the turn footer and request stats when the agent's final
         --  LLM call ended normally.  pi sets stopReason "stop" or "length"
         --  on the last text-producing call; intermediate tool-calling turns
         --  use "toolUse".  agent_end fires exactly once per user prompt
         --  (not once per internal LLM call), so there is no risk of a
         --  premature footer.
         declare
            Stop : constant String := State.Last_Stop_Reason;
         begin
            if Stop = "stop" or else Stop = "length" then
               State.Set_Pending_Stats (True);
               Pi_RPC.Send (Proc, "{""type"":""get_session_stats""}");
            end if;
         end;
         Acme.Window.Replace_Line1
           (Win, FS, Format_Status (State, "ready"));
      elsif Kind = "message_update" then
         declare
            Sub      : constant JSON_Value :=
              Get_Object (Event, "assistantMessageEvent");
            Sub_Kind : constant String     := Get_String (Sub, "type");
         begin
            if Sub_Kind = "thinking_delta" then
               if Section /= Thinking_Section then
                  Acme.Window.Append
                    (Win, FS, ASCII.LF & UC_BOX_V & " ");
                  Section := Thinking_Section;
               end if;
               declare
                  Text_Delta : constant String := Get_String (Sub, "delta");
                  Start : Natural         := Text_Delta'First;
               begin
                  --  Indent continuation lines; write chunks to keep
                  --  multi-byte UTF-8 sequences intact across 9P writes.
                  for I in Text_Delta'Range loop
                     if Text_Delta (I) = ASCII.LF then
                        if I > Start then
                           Acme.Window.Append
                             (Win, FS, Text_Delta (Start .. I - 1));
                        end if;
                        Acme.Window.Append
                          (Win, FS,
                           "" & ASCII.LF & UC_BOX_V & " ");
                        Start := I + 1;
                     end if;
                  end loop;
                  if Start <= Text_Delta'Last then
                     Acme.Window.Append
                       (Win, FS, Text_Delta (Start .. Text_Delta'Last));
                  end if;
               end;

            elsif Sub_Kind = "thinking_end" then
               Acme.Window.Append
                 (Win, FS, "" & ASCII.LF & ASCII.LF);
               Section := No_Section;

            elsif Sub_Kind = "text_delta" then
               if Section /= Text_Section then
                  if Section /= No_Section then
                     Acme.Window.Append (Win, FS, "" & ASCII.LF);
                  end if;
                  Section := Text_Section;
               end if;
               State.Set_Text_Emitted (True);
               State.Set_Has_Text_Delta (True);
               Acme.Window.Append
                 (Win, FS, Get_String (Sub, "delta"));

            elsif Sub_Kind = "text_end" then
               Section := No_Section;
            end if;
         end;

      --  ── tool_execution_start ──────────────────────────────────────────
      elsif Kind = "tool_execution_start" then
         State.Set_Text_Emitted (True);
         State.Set_Has_Tool_In_Turn (True);
         declare
            Tool    : constant String     := Get_String (Event, "toolName");
            Args    : constant JSON_Value := Get_Object (Event, "args");
            Tool_Id : constant String     :=
              Get_String (Event, "toolCallId");
            Tok     : constant String     :=
              (if Tool_Id'Length > 0
               then Hash_Tool_Id (Tool_Id)
               else "");
            Sess    : constant String     := State.Session_Id;
         begin
            if Section /= No_Section then
               Acme.Window.Append (Win, FS, "" & ASCII.LF & ASCII.LF);
            else
               Acme.Window.Append (Win, FS, "" & ASCII.LF);
            end if;
            if Sess'Length > 0 and then Tok'Length > 0 then
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_BOX_TL & " " & UC_GEAR & " " & Tool
                  & " llm-chat+" & Sess & "/tool/" & Tok);
            else
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_BOX_TL & " " & UC_GEAR & " " & Tool);
            end if;
            --  Show key args.  For the edit tool, display the file path
            --  followed by a compact unified diff of oldText vs newText,
            --  matching the Python reference's edit_diff_lines() output.
            if Tool = "edit" then
               declare
                  Edit_Path : constant String :=
                    Get_String (Args, "path");
                  Diff_Body : constant String :=
                    Edit_Diff_Lines
                      (Get_String (Args, "oldText"),
                       Get_String (Args, "newText"));
                  Diff_Pos  : Natural := Diff_Body'First;
               begin
                  Acme.Window.Append
                    (Win, FS,
                     ASCII.LF & UC_BOX_V & " path: " & Edit_Path);
                  --  Append each diff body line with the │ prefix.
                  for I in Diff_Body'Range loop
                     if Diff_Body (I) = ASCII.LF then
                        Acme.Window.Append
                          (Win, FS,
                           ASCII.LF & UC_BOX_V & " "
                           & Diff_Body (Diff_Pos .. I - 1));
                        Diff_Pos := I + 1;
                     end if;
                  end loop;
                  if Diff_Pos <= Diff_Body'Last then
                     Acme.Window.Append
                       (Win, FS,
                        ASCII.LF & UC_BOX_V & " "
                        & Diff_Body (Diff_Pos .. Diff_Body'Last));
                  end if;
               end;
            elsif Args.Kind = JSON_Object_Type then
               declare
                  procedure Show_Field
                    (Name  : UTF8_String;
                     Value : JSON_Value)
                  is
                  begin
                     if Name not in "oldText" | "newText" then
                        Acme.Window.Append
                          (Win, FS,
                           ASCII.LF
                           & Format_Tool_Field
                               (Name, JSON_Scalar_Image (Value)));
                     end if;
                  end Show_Field;
               begin
                  Args.Map_JSON_Object (Show_Field'Access);
               end;
            end if;
            --  Append a pending-close placeholder that embeds the token.
            --  tool_execution_end will find and replace it in-place via
            --  acme's regexp addr mechanism.  When no token is available
            --  the placeholder is omitted and the end handler falls back
            --  to appending the close marker normally.
            if Tok'Length > 0 then
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_BOX_BL & " " & UC_ELLIP & Tok
                  & ASCII.LF & ASCII.LF);
            end if;
            Section := Tool_Section;
         end;

      --  ── tool_execution_end ────────────────────────────────────────────
      elsif Kind = "tool_execution_end" then
         declare
            Tool_Id : constant String :=
              Get_String (Event, "toolCallId");
            Tok     : constant String :=
              (if Tool_Id'Length > 0
               then Hash_Tool_Id (Tool_Id)
               else "");
         begin
            if Tok'Length > 0 then
               --  Replace the pending-close placeholder written by
               --  tool_execution_start in-place via acme regexp addr.
               if Get_Boolean (Event, "isError") then
                  declare
                     Result  : constant String  :=
                       Get_String (Event, "result");
                     Preview : constant Natural :=
                       (if Result'Length > 80
                        then Result'First + 79
                        else Result'Last);
                  begin
                     Acme.Window.Replace_Match
                       (Win, FS,
                        "/" & UC_BOX_BL & " " & UC_ELLIP & Tok & "/",
                        UC_BOX_BL & " " & UC_CROSS & " "
                        & Result (Result'First .. Preview));
                  end;
               else
                  Acme.Window.Replace_Match
                    (Win, FS,
                     "/" & UC_BOX_BL & " " & UC_ELLIP & Tok & "/",
                     UC_BOX_BL & " " & UC_CHECK);
               end if;
            else
               --  No token: fall back to appending the close marker.
               if Get_Boolean (Event, "isError") then
                  declare
                     Result  : constant String  :=
                       Get_String (Event, "result");
                     Preview : constant Natural :=
                       (if Result'Length > 80
                        then Result'First + 79
                        else Result'Last);
                  begin
                     Acme.Window.Append
                       (Win, FS,
                        ASCII.LF & UC_BOX_BL & " " & UC_CROSS & " "
                        & Result (Result'First .. Preview)
                        & ASCII.LF & ASCII.LF);
                  end;
               else
                  Acme.Window.Append
                    (Win, FS,
                     "" & ASCII.LF
                     & UC_BOX_BL & " " & UC_CHECK & ASCII.LF & ASCII.LF);
               end if;
            end if;
            Section := No_Section;
         end;

      --  ── message_end (token counts and turn cost) ─────────────────────
      elsif Kind = "message_end" then
         declare
            Msg   : constant JSON_Value := Get_Object (Event, "message");
            Usage : constant JSON_Value := Get_Object (Msg, "usage");
         begin
            if Get_String (Msg, "role") = "assistant" then
               --  Track the stop reason so agent_end can detect whether
               --  this was the agent's final text turn ("stop", "length")
               --  or an intermediate tool-calling turn ("toolUse").
               declare
                  Stop : constant String := Get_String (Msg, "stopReason");
                  Err  : constant String := Get_String (Msg, "errorMessage");
               begin
                  State.Set_Last_Stop_Reason (Stop);
                  if Stop = "error" then
                     State.Set_Last_Error_Message (Err);
                  else
                     State.Set_Last_Error_Message ("");
                  end if;
               end;
               if Usage.Kind = JSON_Object_Type then
                  declare
                     Input_Count  : constant Natural :=
                       Get_Integer (Usage, "input")
                       + Get_Integer (Usage, "cacheRead")
                       + Get_Integer (Usage, "cacheWrite");
                     Output_Count : constant Natural :=
                       Get_Integer (Usage, "output");
                     Cost_Val     : constant JSON_Value :=
                       Get_Object (Usage, "cost");
                     Turn_Cost    : constant Natural :=
                       (if Cost_Val.Kind = JSON_Object_Type
                        then Get_Cost_Dmil (Cost_Val, "total")
                        else 0);
                  begin
                     if Input_Count > 0 or else Output_Count > 0 then
                        State.Set_Turn_Tokens (Input_Count, Output_Count);
                     end if;
                     if Turn_Cost > 0 then
                        State.Set_Turn_Cost (Turn_Cost);
                     end if;
                  end;
               end if;
            end if;
         end;

      --  ── auto_retry_start ──────────────────────────────────────────────
      --  Emitted by pi before each retry attempt.  Show a compact notice
      --  so the user can see why the turn is being retried and how long
      --  the backoff delay is.
      --
      --  NOTE: pi emits agent_end BEFORE this event.  Setting Is_Retrying
      --  here means the flag is True for all subsequent agent_end events
      --  within the same retry sequence (i.e. the 2nd, 3rd, … failed
      --  attempt), suppressing the spurious "No response" message for
      --  those attempts.  The very first failure is shown once, followed
      --  immediately by this retry notice.
      elsif Kind = "auto_retry_start" then
         State.Set_Is_Retrying (True);
         declare
            Attempt     : constant Natural :=
              Get_Integer (Event, "attempt");
            Max_Att     : constant Natural :=
              Get_Integer (Event, "maxAttempts");
            Delay_Ms    : constant Natural :=
              Get_Integer (Event, "delayMs");
            Err_Msg     : constant String  :=
              Get_String  (Event, "errorMessage");
            Delay_S_Str : constant String  :=
              (if Delay_Ms >= 1000
               then Natural_Image (Delay_Ms / 1000) & "s"
               else Natural_Image (Delay_Ms) & "ms");
         begin
            Acme.Window.Append
              (Win, FS,
               ASCII.LF
               & UC_RETRY & " Retry "
               & Natural_Image (Attempt)
               & "/" & Natural_Image (Max_Att)
               & " in " & Delay_S_Str
               & ": " & Err_Msg
               & ASCII.LF);
            Acme.Window.Replace_Line1
              (Win, FS, Format_Status (State, "retrying"));
         end;

      --  ── auto_retry_end ────────────────────────────────────────────────
      --  Emitted when the retry sequence concludes (success or exhausted).
      --  On success pi immediately continues streaming so no extra note is
      --  needed.  On failure show the final error prominently.
      elsif Kind = "auto_retry_end" then
         State.Set_Is_Retrying (False);
         if not Get_Boolean (Event, "success") then
            declare
               Final_Err : constant String := Get_String (Event, "finalError");
               Attempts  : constant Natural := Get_Integer (Event, "attempt");
            begin
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF
                  & UC_CROSS & " Retry failed after "
                  & Natural_Image (Attempts)
                  & (if Attempts = 1 then " attempt" else " attempts")
                  & (if Final_Err'Length > 0
                     then ": " & Final_Err
                     else "")
                  & ASCII.LF);
            end;
         end if;

      --  ── auto_compaction_start ────────────────────────────────────────
      --  Emitted when pi begins auto-compacting the context (either because
      --  the context overflowed or because the configured threshold was
      --  crossed).  Show a compact notice and update the tag.
      elsif Kind = "auto_compaction_start" then
         State.Set_Compacting (True);
         declare
            Reason : constant String := Get_String (Event, "reason");
            Label  : constant String :=
              (if Reason = "overflow"
               then "Overflow: compacting context" & UC_ELLIP
               else "Compacting context" & UC_ELLIP);
         begin
            Acme.Window.Append
              (Win, FS,
               ASCII.LF & UC_GEAR & " " & Label & ASCII.LF);
         end;
         Acme.Window.Replace_Line1
           (Win, FS, Format_Status (State, "compacting"));

      --  ── auto_compaction_end ───────────────────────────────────────────
      --  Emitted when auto-compaction finishes (success, aborted, or
      --  error).  The three cases are distinguished by the "errorMessage",
      --  "aborted", and "willRetry" fields.
      elsif Kind = "auto_compaction_end" then
         State.Set_Compacting (False);
         declare
            Err_Msg    : constant String  :=
              Get_String  (Event, "errorMessage");
            Is_Aborted : constant Boolean := Get_Boolean (Event, "aborted");
            Will_Retry : constant Boolean := Get_Boolean (Event, "willRetry");
         begin
            if Err_Msg'Length > 0 then
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_WARN & " Compaction failed: "
                  & Err_Msg & ASCII.LF);
            elsif Is_Aborted then
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_CROSS & " Compaction aborted." & ASCII.LF);
            elsif Will_Retry then
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_CHECK
                  & " Context compacted, retrying" & UC_ELLIP
                  & ASCII.LF);
            else
               Acme.Window.Append
                 (Win, FS,
                  ASCII.LF & UC_CHECK & " Context compacted." & ASCII.LF);
            end if;
         end;
         Acme.Window.Replace_Line1
           (Win, FS,
            Format_Status
              (State,
               (if State.Is_Streaming then "running" else "ready")));

      --  ── model_select ─────────────────────────────────────────────────
      --  Emitted by pi when the active model changes (e.g. on startup
      --  before the get_state response arrives, or when cycleModel fires).
      --  Update our cached model/context-window so the tag and status line
      --  stay accurate.  Mirrors the handling in the Python reference.
      elsif Kind = "model_select" then
         declare
            Model_Val  : constant JSON_Value := Get_Object (Event, "model");
            Provider   : constant String     :=
              Get_String  (Model_Val, "provider");
            Model_Id   : constant String     :=
              Get_String  (Model_Val, "id");
            Ctx_Window : constant Natural    :=
              Get_Integer (Model_Val, "contextWindow");
         begin
            if Provider'Length > 0 and then Model_Id'Length > 0 then
               State.Set_Model (Provider & "/" & Model_Id);
            end if;
            if Ctx_Window > 0 then
               State.Set_Context_Window (Ctx_Window);
            end if;
         end;
         Acme.Window.Replace_Line1
           (Win, FS,
            Format_Status
              (State,
               (if State.Is_Streaming then "running" else "ready")));

      --  ── extension_error ───────────────────────────────────────────────
      --  Emitted by rpc-mode when an extension event handler throws.
      elsif Kind = "extension_error" then
         declare
            Ext_Path : constant String := Get_String (Event, "extensionPath");
            Evt_Name : constant String := Get_String (Event, "event");
            Err_Msg  : constant String := Get_String (Event, "error");
         begin
            Acme.Window.Append
              (Win, FS,
               ASCII.LF & "[!] Extension error"
               & (if Ext_Path'Length > 0 then " in " & Ext_Path else "")
               & (if Evt_Name'Length > 0 then " (" & Evt_Name & ")" else "")
               & ": " & Err_Msg & ASCII.LF);
         end;

      --  ── extension_ui_request ──────────────────────────────────────────
      --  Emitted by rpc-mode for extension UI calls.
      --
      --  Fire-and-forget methods (notify, setStatus, setWidget, setTitle,
      --  set_editor_text): only "notify" produces user-visible output; the
      --  rest are no-ops in an acme context.
      --
      --  Blocking methods (select, confirm, input, editor): pi awaits a
      --  matching extension_ui_response on stdin.  Without one, any
      --  extension that opens a dialog hangs indefinitely.  We immediately
      --  respond with cancelled:true so control returns to the extension.
      elsif Kind = "extension_ui_request" then
         declare
            Method : constant String := Get_String (Event, "method");
            Id     : constant String := Get_String (Event, "id");
         begin
            if Method = "notify" then
               declare
                  Msg : constant String := Get_String (Event, "message");
               begin
                  if Msg'Length > 0 then
                     Acme.Window.Append
                       (Win, FS,
                        ASCII.LF & UC_BULLET & " " & Msg & ASCII.LF);
                  end if;
               end;
            elsif Method in "select" | "confirm" | "input" | "editor" then
               --  Blocking dialog: respond cancelled so the extension does
               --  not hang.  Interactive dialogs are not implemented in the
               --  acme frontend.
               if Id'Length > 0 then
                  Pi_RPC.Send
                    (Proc,
                     "{""type"":""extension_ui_response"","
                     & """id"":""" & Id & ""","
                     & """cancelled"":true}");
               end if;
            end if;
            --  setStatus, setWidget, setTitle, set_editor_text:
            --  silently ignored — not applicable to an acme window.
         end;

      --  ── response (RPC reply) ──────────────────────────────────────────
      elsif Kind = "response" then
         if not Get_Boolean (Event, "success") then
            --  Clear compacting flag if a compact command failed so the
            --  button becomes usable again.
            if Get_String (Event, "command") = "compact" then
               State.Set_Compacting (False);
            end if;
            Acme.Window.Append
              (Win, FS,
               ASCII.LF & UC_WARN & " pi error: "
               & Get_String (Event, "error") & ASCII.LF);
            Acme.Window.Replace_Line1
              (Win, FS, Format_Status (State, "error"));
         else
            declare
               Command   : constant String     :=
                 Get_String (Event, "command");
               Data      : constant JSON_Value :=
                 Get_Object (Event, "data");
            begin
               if Command = "get_state" then
                  declare
                     Session_Id_V : constant String :=
                       Get_String (Data, "sessionId");
                     Think_Level  : constant String :=
                       Get_String (Data, "thinkingLevel");
                     Model_Val    : constant JSON_Value :=
                       Get_Object (Data, "model");
                  begin
                     if Session_Id_V'Length > 0 then
                        State.Set_Session_Id (Session_Id_V);
                     end if;
                     if Think_Level'Length > 0 then
                        State.Set_Thinking (Think_Level);
                     end if;
                     declare
                        Provider   : constant String  :=
                          Get_String (Model_Val, "provider");
                        Model_Id   : constant String  :=
                          Get_String (Model_Val, "id");
                        Ctx_Window : constant Natural :=
                          Get_Integer (Model_Val, "contextWindow");
                     begin
                        if Provider'Length > 0
                          and then Model_Id'Length > 0
                          and then State.Current_Model'Length = 0
                        then
                           State.Set_Model (Provider & "/" & Model_Id);
                        end if;
                        if Ctx_Window > 0 then
                           State.Set_Context_Window (Ctx_Window);
                        end if;
                     end;
                  end;
                  Acme.Window.Replace_Line1
                    (Win, FS, Format_Status (State, "ready"));

               elsif Command = "abort" then
                  State.Set_Aborted (True);

               elsif Command = "new_session" then
                  State.Set_Turn_Tokens (0, 0);
                  State.Set_Turn_Cost (0);
                  State.Set_Session_Stats (0, 0, 0, 0, 0, 0);
                  State.Reset_Turn_Count;
                  State.Set_Is_Retrying (False);
                  Pi_RPC.Send (Proc, "{""type"":""get_state""}");

               elsif Command = "get_session_stats" then
                  --  Store cumulative session stats before building the
                  --  turn footer so that Session_Cost_Dmil is populated
                  --  in time for Append_Live_Turn_Footer.
                  declare
                     Tokens_Val : constant JSON_Value :=
                       Get_Object (Data, "tokens");
                  begin
                     State.Set_Session_Stats
                       (Cost_Dmil   => Get_Cost_Dmil (Data, "cost"),
                        Input       =>
                          (if Tokens_Val.Kind = JSON_Object_Type
                           then Get_Integer (Tokens_Val, "input")
                           else 0),
                        Output      =>
                          (if Tokens_Val.Kind = JSON_Object_Type
                           then Get_Integer (Tokens_Val, "output")
                           else 0),
                        Cache_Read  =>
                          (if Tokens_Val.Kind = JSON_Object_Type
                           then Get_Integer (Tokens_Val, "cacheRead")
                           else 0),
                        Cache_Write =>
                          (if Tokens_Val.Kind = JSON_Object_Type
                           then Get_Integer (Tokens_Val, "cacheWrite")
                           else 0),
                        Total       =>
                          (if Tokens_Val.Kind = JSON_Object_Type
                           then Get_Integer (Tokens_Val, "total")
                           else 0));
                  end;
                  if State.Pending_Stats then
                     State.Set_Pending_Stats (False);
                     --  Append turn footer: summary and fork token on the
                     --  same line, followed by the separator rule.
                     Append_Live_Turn_Footer
                       (Win   => Win,
                        FS    => FS,
                        State => State,
                        PID   => PID);
                  end if;
                  Acme.Window.Replace_Line1
                    (Win, FS, Format_Status (State, "ready"));

               elsif Command = "set_model" then
                  --  The response data IS the accepted model object.
                  --  Update state now that pi has confirmed the switch.
                  declare
                     Provider   : constant String  :=
                       Get_String  (Data, "provider");
                     Model_Id   : constant String  :=
                       Get_String  (Data, "id");
                     Ctx_Window : constant Natural :=
                       Get_Integer (Data, "contextWindow");
                  begin
                     if Provider'Length > 0 and then Model_Id'Length > 0 then
                        State.Set_Model (Provider & "/" & Model_Id);
                     end if;
                     if Ctx_Window > 0 then
                        State.Set_Context_Window (Ctx_Window);
                     end if;
                  end;
                  Acme.Window.Replace_Line1
                    (Win, FS,
                     Format_Status
                       (State,
                        (if State.Is_Streaming then "running" else "ready")));

               elsif Command = "set_thinking_level" then
                  --  The new thinking level was already stored in App_State
                  --  by Plumb_Thinking_Task before the command was sent.
                  --  Refresh the tag so the change is visible immediately.
                  Acme.Window.Replace_Line1
                    (Win, FS,
                     Format_Status
                       (State,
                        (if State.Is_Streaming then "running" else "ready")));

               elsif Command = "compact" then
                  --  Manual compaction completed.  Show a summary line with
                  --  the token count before compaction, then return to ready.
                  State.Set_Compacting (False);
                  declare
                     Tokens_Before : constant Natural :=
                       Get_Integer (Data, "tokensBefore");
                  begin
                     Acme.Window.Append
                       (Win, FS,
                        ASCII.LF & UC_CHECK & " Context compacted"
                        & (if Tokens_Before > 0
                           then " (was "
                                & Format_Kilo (Tokens_Before)
                                & " tokens)"
                           else "")
                        & "." & ASCII.LF);
                  end;
                  Acme.Window.Replace_Line1
                    (Win, FS, Format_Status (State, "ready"));

               elsif Command = "get_available_models" then
                  --  Open the +models sub-window populated with only the
                  --  models for which pi has configured API credentials.
                  --  Consume the pending flag regardless of whether the
                  --  response actually contains any models, so a failed
                  --  or empty reply does not leave the flag set forever.
                  if State.Models_Pending then
                     State.Set_Models_Pending (False);
                     declare
                        Models_Val : constant JSON_Value :=
                          (if Data.Has_Field ("models")
                           then Data.Get ("models")
                           else JSON_Null);
                        Parent     : constant String :=
                          Ada.Directories.Current_Directory & "/+pi";
                        Pid_Prefix : constant String := PID & "/";
                        Content    : Unbounded_String;
                     begin
                        if Models_Val.Kind = JSON_Array_Type then
                           declare
                              Arr : constant JSON_Array :=
                                Models_Val.Get;
                           begin
                              for I in 1 .. Length (Arr) loop
                                 declare
                                    M        : constant JSON_Value :=
                                      Get (Arr, I);
                                    Provider : constant String :=
                                      Get_String (M, "provider");
                                    Model_Id : constant String :=
                                      Get_String (M, "id");
                                 begin
                                    if Provider'Length > 0
                                      and then Model_Id'Length > 0
                                    then
                                       Append
                                         (Content,
                                          "model+" & Pid_Prefix
                                          & Provider & "/" & Model_Id
                                          & ASCII.LF);
                                    end if;
                                 end;
                              end loop;
                           end;
                        end if;
                        Open_Sub_Window
                          (FS, Parent, "+models",
                           (if Length (Content) > 0
                            then To_String (Content)
                            else "(no models available)" & ASCII.LF));
                     end;
                  end if;
               end if;
            end;
         end if;

      --  ── unknown event type ────────────────────────────────────────────
      --  Any event type not handled above is shown as a diagnostic line so
      --  that new pi error events or future protocol additions surface in
      --  the window rather than being silently swallowed.
      --  Well-known metadata events emitted by pi-agent-core that carry no
      --  user-visible information (turn_start, turn_end, message_start,
      --  tool_execution_update) are listed explicitly so they remain quiet.
      elsif Kind'Length > 0
        and then Kind not in
          "turn_start" | "turn_end" | "message_start"
          | "tool_execution_update"
      then
         declare
            Err : constant String := Get_String (Event, "error");
            Msg : constant String := Get_String (Event, "errorMessage");
            Detail : constant String :=
              (if Err'Length > 0 then ": " & Err
               elsif Msg'Length > 0 then ": " & Msg
               else "");
         begin
            Acme.Window.Append
              (Win, FS,
               ASCII.LF & "[pi:" & Kind & "]"
               & Detail & ASCII.LF);
         end;
      end if;
   end Dispatch_Pi_Event;

end Pi_Acme_App.Dispatch;
