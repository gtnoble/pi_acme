with AUnit.Assertions;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with Pi_RPC;                 use Pi_RPC;

package body Pi_Interface_Tests is

   use AUnit.Assertions;

   Model : constant String := "github-copilot/gpt-5-mini";

   --  ── One-shot event collector ────────────────────────────────────────
   --
   --  Reading from pi is blocking.  We use a protected flag as the
   --  synchronisation point and a task as the reader, with Ada's
   --  `select ... or delay` for the timeout.

   protected type Done_Flag is
      procedure Signal;
      entry Wait;
   private
      Complete : Boolean := False;
   end Done_Flag;

   protected body Done_Flag is
      procedure Signal is begin Complete := True; end;
      entry Wait when Complete is begin null; end;
   end Done_Flag;

   --  JSON helpers
   --
   --  All three guards check V.Kind first: GNATCOLL's Has_Field accesses
   --  the object-discriminant variant directly and raises Constraint_Error
   --  when called on a JSON_Null or any non-object value.

   function Str (V : JSON_Value; F : UTF8_String) return String is
   begin
      if V.Kind /= JSON_Object_Type then
         return "";
      end if;
      if V.Has_Field (F) and then V.Get (F).Kind = JSON_String_Type then
         return V.Get (F).Get;
      end if;
      return "";
   end Str;

   function Obj (V : JSON_Value; F : UTF8_String) return JSON_Value is
   begin
      if V.Kind /= JSON_Object_Type then
         return JSON_Null;
      end if;
      if V.Has_Field (F) and then V.Get (F).Kind = JSON_Object_Type then
         return V.Get (F);
      end if;
      return JSON_Null;
   end Obj;

   function Int (V : JSON_Value; F : UTF8_String) return Natural is
   begin
      if V.Kind /= JSON_Object_Type then
         return 0;
      end if;
      if V.Has_Field (F) and then V.Get (F).Kind = JSON_Int_Type then
         return Natural (Long_Integer'(V.Get (F).Get));
      end if;
      return 0;
   end Int;

   --  ── Test_Get_State ───────────────────────────────────────────────────
   --
   --  Verifies that pi responds to get_state with a well-formed response
   --  containing the model provider, model id, and a session UUID.

   procedure Test_Get_State (T : in out Test) is
      pragma Unreferenced (T);

      Proc : Process := Start
        (No_Session    => True,
         Model         => Model,
         Cwd   => Ada.Directories.Current_Directory);

      Provider   : Unbounded_String;
      Model_Id   : Unbounded_String;
      Session_Id : Unbounded_String;
      Got_State  : Boolean := False;

      Flag : Done_Flag;

      task Reader;
      task body Reader is
      begin
         Send (Proc, "{""type"":""get_state""}");
         loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit when Line = "";
               R := Read (Line);
               if R.Success then
                  declare
                     Ev : constant JSON_Value := R.Value;
                  begin
                     if Str (Ev, "type") = "response"
                       and then Str (Ev, "command") = "get_state"
                     then
                        declare
                           Data : constant JSON_Value := Obj (Ev, "data");
                           M    : constant JSON_Value := Obj (Data, "model");
                        begin
                           Provider   :=
                             To_Unbounded_String (Str (M, "provider"));
                           Model_Id   := To_Unbounded_String (Str (M, "id"));
                           Session_Id := To_Unbounded_String
                             (Str (Data, "sessionId"));
                           Got_State  := True;
                           Flag.Signal;
                           exit;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Reader;

   begin
      select
         Flag.Wait;
      or
         delay 15.0;
      end select;
      Terminate_Process (Proc);

      Assert (Got_State,
              "Should receive a get_state response");
      Assert (To_String (Provider) = "github-copilot",
              "Provider should be github-copilot, got: "
              & To_String (Provider));
      Assert (To_String (Model_Id)'Length > 0,
              "Model id should be non-empty");
      Assert (To_String (Session_Id)'Length > 0,
              "Session ID should be non-empty UUID");
   end Test_Get_State;

   --  ── Test_Set_Model ────────────────────────────────────────────────────
   --
   --  Sends a set_model RPC to switch to gpt-5-mini and verifies the
   --  response carries the model id and a positive contextWindow.

   procedure Test_Model_Select_Event (T : in out Test) is
      pragma Unreferenced (T);

      Proc : Process := Start
        (Cwd => Ada.Directories.Current_Directory);

      Got_Response   : Boolean := False;
      Resp_Model_Id  : Unbounded_String;
      Resp_Ctx       : Natural := 0;

      Flag : Done_Flag;

      task Reader;
      task body Reader is
      begin
         Send (Proc, "{""type"":""get_state""}");
         Send (Proc,
               "{""type"":""set_model"","
               & """provider"":""github-copilot"","
               & """modelId"":""gpt-5-mini""}");
         loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit when Line = "";
               R := Read (Line);
               if R.Success then
                  declare
                     Ev : constant JSON_Value := R.Value;
                  begin
                     if Str (Ev, "type") = "response"
                       and then Str (Ev, "command") = "set_model"
                     then
                        Resp_Model_Id :=
                          To_Unbounded_String (Str (Obj (Ev, "data"), "id"));
                        Resp_Ctx :=
                          Int (Obj (Ev, "data"), "contextWindow");
                        Got_Response := True;
                        Flag.Signal;
                        exit;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Reader;

   begin
      select
         Flag.Wait;
      or
         delay 15.0;
      end select;
      Terminate_Process (Proc);

      Assert (Got_Response,
              "set_model should return a response");
      Assert (To_String (Resp_Model_Id) = "gpt-5-mini",
              "set_model response id should be gpt-5-mini, got: "
              & To_String (Resp_Model_Id));
      Assert (Resp_Ctx > 0,
              "set_model response should include contextWindow");
   end Test_Model_Select_Event;

   --  ── Test_Full_Prompt_Cycle ───────────────────────────────────────────
   --
   --  Uses a single pi process to verify the complete streaming lifecycle:
   --  agent_start → text_delta events → agent_end, plus message_end
   --  carrying a non-zero output token count.
   --  Replaces separate Test_Simple_Prompt and Test_Message_End_Tokens
   --  to keep total API calls low.

   procedure Test_Simple_Prompt (T : in out Test) is
      pragma Unreferenced (T);

      Proc : Process := Start
        (No_Session    => True,
         Model         => Model,
         Cwd   => Ada.Directories.Current_Directory);

      Got_Agent_Start : Boolean := False;
      Got_Agent_End   : Boolean := False;
      Output_Tokens   : Natural := 0;
      Response_Text   : Unbounded_String;

      Flag : Done_Flag;

      task Reader;
      task body Reader is
      begin
         Send (Proc, "{""type"":""get_state""}");
         Send (Proc,
               "{""type"":""prompt"","
               & """message"":"""
               & "Reply with only the word PONG"
               & " and nothing else.""}");
         loop
            declare
               Line    : constant String := Read_Line (Proc);
               R       : Read_Result;
            begin
               exit when Line = "";
               R := Read (Line);
               if R.Success then
                  declare
                     Ev      : constant JSON_Value := R.Value;
                     Ev_Type : constant String     := Str (Ev, "type");
                  begin
                     if Ev_Type = "agent_start" then
                        Got_Agent_Start := True;

                     elsif Ev_Type = "message_update" then
                        declare
                           Sub : constant JSON_Value :=
                             Obj (Ev, "assistantMessageEvent");
                        begin
                           if Str (Sub, "type") = "text_delta" then
                              Append (Response_Text, Str (Sub, "delta"));
                           end if;
                        end;

                     elsif Ev_Type = "message_end" then
                        --  Two message_end events per turn; accumulate output
                        --  tokens (user message has none, assistant has them).
                        declare
                           N : constant Natural :=
                             Int (Obj (Obj (Ev, "message"), "usage"),
                                  "output");
                        begin
                           if N > 0 then
                              Output_Tokens := Output_Tokens + N;
                           end if;
                        end;

                     elsif Ev_Type = "agent_end" then
                        Got_Agent_End := True;
                        Flag.Signal;
                        exit;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Reader;

   begin
      select
         Flag.Wait;
      or
         delay 30.0;
      end select;
      Terminate_Process (Proc);

      Assert (Got_Agent_Start,
              "Should receive agent_start event");
      Assert (Got_Agent_End,
              "Should receive agent_end event within 30 seconds");
      Assert (Ada.Strings.Fixed.Index
                (To_String (Response_Text), "PONG") > 0,
              "Response should contain PONG, got: "
              & To_String (Response_Text));
      Assert (Output_Tokens > 0,
              "message_end should carry non-zero output token count");
   end Test_Simple_Prompt;

   --  ── Test_Abort ────────────────────────────────────────────────────────
   --
   --  Verifies that sending abort while an agent cycle is in progress
   --  causes pi to emit agent_end.
   --
   --  The abort is intentionally deferred until agent_start has been
   --  observed.  Sending abort before agent_start is a race: pi may
   --  cancel the queued prompt without ever opening an agent cycle, so
   --  agent_end would never arrive.

   procedure Test_Abort (T : in out Test) is
      pragma Unreferenced (T);

      Proc : Process := Start
        (No_Session => True,
         Model      => Model,
         Cwd        => Ada.Directories.Current_Directory);

      Got_Agent_Start : Boolean := False;
      Got_Agent_End   : Boolean := False;
      Flag            : Done_Flag;

      task Reader;
      task body Reader is
      begin
         Send (Proc, "{""type"":""get_state""}");
         Send (Proc,
               "{""type"":""prompt"","
               & """message"":""Count from 1 to 1000 very slowly.""}");

         --  Phase 1 — wait for agent_start, then send abort.
         Phase_1 : loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit Phase_1 when Line = "";
               R := Read (Line);
               if R.Success
                 and then Str (R.Value, "type") = "agent_start"
               then
                  Got_Agent_Start := True;
                  Send (Proc, "{""type"":""abort""}");
                  exit Phase_1;
               end if;
            end;
         end loop Phase_1;

         --  Phase 2 — wait for agent_end produced by the abort.
         Phase_2 : loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit Phase_2 when Line = "";
               R := Read (Line);
               if R.Success
                 and then Str (R.Value, "type") = "agent_end"
               then
                  Got_Agent_End := True;
                  Flag.Signal;
                  exit Phase_2;
               end if;
            end;
         end loop Phase_2;

         Flag.Signal;
      exception
         when others => Flag.Signal;
      end Reader;

   begin
      select
         Flag.Wait;
      or
         delay 20.0;
      end select;
      Terminate_Process (Proc);

      Assert (Got_Agent_Start,
              "agent_start should arrive before abort is sent");
      Assert (Got_Agent_End,
              "agent_end should arrive within 20 s after abort");
   end Test_Abort;

   procedure Test_Message_End_Tokens (T : in out Test) is
      pragma Unreferenced (T);
   begin
      null;  --  Token count is verified in Test_Simple_Prompt
   end Test_Message_End_Tokens;

   --  ── Test_Restart ──────────────────────────────────────────────────────
   --
   --  Verifies that Pi_RPC.Restart terminates the original subprocess and
   --  starts a fresh one whose get_state responds successfully.

   procedure Test_Restart (T : in out Test) is
      pragma Unreferenced (T);

      Proc : Process := Start
        (No_Session => True,
         Model      => Model,
         Cwd        => Ada.Directories.Current_Directory);

      --  Synchronisation between the reader task and the main task.
      --  Flag1 fires once the first get_state response arrives.
      --  Flag_Restarted fires once the main task completes Restart.
      --  Flag2 fires once the second get_state response arrives.

      Flag1           : Done_Flag;
      Flag_Restarted  : Done_Flag;
      Flag2           : Done_Flag;

      Got_State_1   : Boolean := False;
      Got_State_2   : Boolean := False;

      task Reader;
      task body Reader is
      begin
         --  Phase 1 — first get_state.
         Send (Proc, "{""type"":""get_state""}");
         Phase_1 : loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit Phase_1 when Line = "";
               R := Read (Line);
               if R.Success
                 and then Str (R.Value, "type") = "response"
                 and then Str (R.Value, "command") = "get_state"
               then
                  Got_State_1 := True;
                  Flag1.Signal;
                  exit Phase_1;
               end if;
            end;
         end loop Phase_1;
         Flag1.Signal;   --  No-op if already signalled (e.g. EOF first).

         --  Wait for the main task to finish calling Restart.
         Flag_Restarted.Wait;

         --  Phase 2 — get_state from the restarted process.
         Send (Proc, "{""type"":""get_state""}");
         Phase_2 : loop
            declare
               Line : constant String := Read_Line (Proc);
               R    : Read_Result;
            begin
               exit Phase_2 when Line = "";
               R := Read (Line);
               if R.Success
                 and then Str (R.Value, "type") = "response"
                 and then Str (R.Value, "command") = "get_state"
               then
                  Got_State_2 := True;
                  Flag2.Signal;
                  exit Phase_2;
               end if;
            end;
         end loop Phase_2;
         Flag2.Signal;
      exception
         when others =>
            Flag1.Signal;
            Flag2.Signal;
      end Reader;

   begin
      select
         Flag1.Wait;
      or
         delay 15.0;
      end select;

      Assert (Got_State_1,
              "Phase 1: should receive get_state response before Restart");

      --  Restart replaces the subprocess in place; the reader task will
      --  get EOF on the old stdout and then resume reading the new one.
      Restart (Proc);
      Flag_Restarted.Signal;

      select
         Flag2.Wait;
      or
         delay 15.0;
      end select;

      Terminate_Process (Proc);

      Assert (Got_State_2,
              "Phase 2: should receive get_state response after Restart");
   end Test_Restart;

end Pi_Interface_Tests;
