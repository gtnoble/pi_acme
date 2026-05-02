--  Pi_Acme_App.History body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with Acme.Window;
with Nine_P.Client;          use Nine_P.Client;
with Pi_Acme_App.Utils;      use Pi_Acme_App.Utils;
with Session_Lister;         use Session_Lister;

package body Pi_Acme_App.History is

   --  POSIX getpid() — used to build window-specific selector tokens.
   function Getpid return Integer;
   pragma Import (C, Getpid, "getpid");

   --  ── Session history replay types ──────────────────────────────────────
   --
   --  Used by Render_Session_History to map tool-call IDs to their results
   --  during the first (collection) pass over a session JSONL file.

   type Tool_Result_Entry is record
      Id     : Unbounded_String;
      Text   : Unbounded_String;
      Is_Err : Boolean := False;
   end record;

   package TR_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Tool_Result_Entry);

   --  ── Read_Line ─────────────────────────────────────────────────────────
   --
   --  Read one complete line from File into an Unbounded_String.
   --  Unlike the Ada.Text_IO.Get_Line function form, this never overflows
   --  the stack on very long lines: it uses the fixed-buffer procedure form
   --  in a loop and simply appends each chunk to the result.

   function Read_Line
     (File : Ada.Text_IO.File_Type) return Unbounded_String
   is
      Chunk  : String (1 .. 65_536);   --  64 KiB per iteration
      Last   : Natural;
      Result : Unbounded_String;
   begin
      loop
         Ada.Text_IO.Get_Line (File, Chunk, Last);
         Append (Result, Chunk (1 .. Last));
         exit when Last < Chunk'Last;
      end loop;
      return Result;
   end Read_Line;

   --  ── Render_Session_History ────────────────────────────────────────────
   --
   --  Read the JSONL file for UUID and replay the full conversation history
   --  into the acme window.  Two passes are made over the file:
   --
   --    Pass 1 — collect toolResult entries (id, text, isError) so that
   --             each toolCall block can display its outcome inline.
   --
   --    Pass 2 — render all events in order: model_change, compaction,
   --             user messages (▶ text), assistant messages (thinking │ ,
   --             text, tool-call boxes).
   --
   --  On return, State.Turn_Tokens is updated from the last assistant
   --  message's usage block so that the status line and +stats window show
   --  accurate numbers immediately after a reload.

   procedure Render_Session_History
     (UUID  : String;
      Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State)
   is
      Path         : constant String :=
        Find_Session_File (UUID);
      Tool_Results : TR_Vectors.Vector;
      Buf          : Unbounded_String;
      Last_Input   : Natural         := 0;
      Last_Output  : Natural         := 0;
      Turn_Input   : Natural         := 0;
      Turn_Output  : Natural         := 0;
      Cur_Model    : Unbounded_String :=
        To_Unbounded_String (State.Current_Model);
      PID_Str        : constant String := Natural_Image (Natural (Getpid));
      Turns_Rendered : Natural         := 0;
      In_Turn        : Boolean         := False;
      Saw_Asst_Text  : Boolean         := False;

      --  Append Thinking text to Buf with "│ " prefix on every line.
      procedure Render_Thinking_Block (Thinking : String) is
         Start : Natural := Thinking'First;
      begin
         Append (Buf, ASCII.LF & UC_BOX_V & " ");
         for I in Thinking'Range loop
            if Thinking (I) = ASCII.LF then
               if I > Start then
                  Append (Buf, Thinking (Start .. I - 1));
               end if;
               Append (Buf, "" & ASCII.LF & UC_BOX_V & " ");
               Start := I + 1;
            end if;
         end loop;
         if Start <= Thinking'Last then
            Append (Buf, Thinking (Start .. Thinking'Last));
         end if;
         Append (Buf, "" & ASCII.LF & ASCII.LF);
      end Render_Thinking_Block;

      --  Return the Tool_Result_Entry whose Id matches, or a blank entry.
      function Find_TR (Id : String) return Tool_Result_Entry is
      begin
         for TR of Tool_Results loop
            if To_String (TR.Id) = Id then
               return TR;
            end if;
         end loop;
         return (Id     => Null_Unbounded_String,
                 Text   => Null_Unbounded_String,
                 Is_Err => False);
      end Find_TR;

      --  Return S up to (but not including) the first newline.
      function First_Line (S : String) return String is
      begin
         for I in S'Range loop
            if S (I) = ASCII.LF then
               return S (S'First .. I - 1);
            end if;
         end loop;
         return S;
      end First_Line;

   begin
      if Path'Length = 0 then
         Acme.Window.Append
           (Win, FS,
            "[session file not found for " & UUID & "]" & ASCII.LF);
         return;
      end if;

      --  ── Pass 1: collect tool results ──────────────────────────────────
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line  : constant String      := To_String (Read_Line (File));
               Parse : constant Read_Result := Read (Line);
            begin
               if Parse.Success then
                  declare
                     Ev   : constant JSON_Value := Parse.Value;
                     Kind : constant String     :=
                       Get_String (Ev, "type");
                  begin
                     if Kind = "message" then
                        declare
                           Msg  : constant JSON_Value :=
                             Get_Object (Ev, "message");
                           Role : constant String     :=
                             Get_String (Msg, "role");
                        begin
                           if Role = "toolResult" then
                              declare
                                 Tid    : constant String  :=
                                   Get_String (Msg, "toolCallId");
                                 Is_Err : constant Boolean :=
                                   Get_Boolean (Msg, "isError");
                                 Parts  : Unbounded_String;
                              begin
                                 if Msg.Has_Field ("content")
                                   and then
                                     Msg.Get ("content").Kind
                                     = JSON_Array_Type
                                 then
                                    declare
                                       Content : constant JSON_Array :=
                                         Msg.Get ("content");
                                    begin
                                       for I in 1 .. Length (Content) loop
                                          declare
                                             Block : constant JSON_Value :=
                                               Get (Content, I);
                                          begin
                                             if Block.Kind
                                                = JSON_Object_Type
                                               and then
                                                 Get_String
                                                   (Block, "type")
                                                 = "text"
                                             then
                                                if Length (Parts) > 0 then
                                                   Append
                                                     (Parts, ASCII.LF);
                                                end if;
                                                Append
                                                  (Parts,
                                                   Get_String
                                                     (Block, "text"));
                                             end if;
                                          end;
                                       end loop;
                                    end;
                                 end if;
                                 if Tid'Length > 0 then
                                    Tool_Results.Append
                                      ((Id     =>
                                            To_Unbounded_String (Tid),
                                        Text   => Parts,
                                        Is_Err => Is_Err));
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Ada.Text_IO.Close (File);
      exception
         when Ex : others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            Acme.Window.Append
              (Win, FS,
               "[could not read session file: "
               & Ada.Exceptions.Exception_Message (Ex) & "]"
               & ASCII.LF);
            return;
      end;

      --  ── Pass 2: render conversation history ───────────────────────────
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line  : constant String      := To_String (Read_Line (File));
               Parse : constant Read_Result := Read (Line);
            begin
               if Parse.Success then
                  declare
                     Ev   : constant JSON_Value := Parse.Value;
                     Kind : constant String     :=
                       Get_String (Ev, "type");
                  begin

                     --  ── model_change ──────────────────────────────────
                     if Kind = "model_change" then
                        declare
                           Provider  : constant String :=
                             Get_String (Ev, "provider");
                           Model_Id  : constant String :=
                             Get_String (Ev, "modelId");
                        begin
                           if Provider'Length > 0
                             and then Model_Id'Length > 0
                           then
                              declare
                                 New_Model : constant String :=
                                   Provider & "/" & Model_Id;
                              begin
                                 if New_Model /= To_String (Cur_Model)
                                 then
                                    Cur_Model :=
                                      To_Unbounded_String (New_Model);
                                    Append
                                      (Buf,
                                       "[Model " & UC_TRI_R & " "
                                       & New_Model & "]" & ASCII.LF);
                                 end if;
                              end;
                           end if;
                        end;

                     --  ── compaction ────────────────────────────────────
                     elsif Kind = "compaction" then
                        declare
                           Summary : constant String :=
                             Get_String (Ev, "summary");
                           Start   : Natural         :=
                             Summary'First;
                        begin
                           if Summary'Length > 0 then
                              Append
                                (Buf,
                                 ASCII.LF
                                 & UC_HORIZ & UC_HORIZ & " Compacted "
                                 & Str_Repeat (UC_HORIZ, 47)
                                 & ASCII.LF);
                              for I in Summary'Range loop
                                 if Summary (I) = ASCII.LF then
                                    Append
                                      (Buf,
                                       UC_BOX_V & " "
                                       & Summary (Start .. I - 1)
                                       & ASCII.LF);
                                    Start := I + 1;
                                 end if;
                              end loop;
                              if Start <= Summary'Last then
                                 Append
                                   (Buf,
                                    UC_BOX_V & " "
                                    & Summary (Start .. Summary'Last)
                                    & ASCII.LF);
                              end if;
                              Append
                                (Buf,
                                 UC_HORIZ & UC_HORIZ & " "
                                 & Str_Repeat (UC_HORIZ, 57)
                                 & ASCII.LF);
                           end if;
                        end;

                     --  ── message ───────────────────────────────────────
                     elsif Kind = "message" then
                        declare
                           Msg  : constant JSON_Value :=
                             Get_Object (Ev, "message");
                           Role : constant String     :=
                             Get_String (Msg, "role");
                        begin
                           --  User turn
                           if Role = "user" then
                              --  If the previous turn was complete, emit
                              --  its footer before this user message.
                              if In_Turn and then Saw_Asst_Text then
                                 Turns_Rendered := Turns_Rendered + 1;
                                 Append
                                   (Buf,
                                    Format_Turn_Footer
                                      (Turn_N        => Turns_Rendered,
                                       UUID          => UUID,
                                       PID           => PID_Str,
                                       Input_Tokens  => Turn_Input,
                                       Output_Tokens => Turn_Output,
                                       Ctx_Window    =>
                                         State.Context_Window,
                                       Model_Text    =>
                                         To_String (Cur_Model)));
                              end if;
                              In_Turn       := True;
                              Saw_Asst_Text := False;
                              Turn_Input    := 0;
                              Turn_Output   := 0;
                              if Msg.Has_Field ("content")
                                and then
                                  Msg.Get ("content").Kind
                                  = JSON_Array_Type
                              then
                                 declare
                                    Content : constant JSON_Array :=
                                      Msg.Get ("content");
                                 begin
                                    for I in 1 .. Length (Content) loop
                                       declare
                                          Block : constant JSON_Value :=
                                            Get (Content, I);
                                       begin
                                          if Block.Kind
                                             = JSON_Object_Type
                                            and then
                                              Get_String
                                                (Block, "type")
                                              = "text"
                                          then
                                             declare
                                                Text    : constant
                                                  String :=
                                                    Get_String
                                                      (Block, "text");
                                                Trimmed : constant
                                                  String :=
                                                    Ada.Strings.Fixed
                                                      .Trim
                                                        (Text,
                                                         Ada.Strings
                                                           .Both);
                                             begin
                                                if Trimmed'Length > 0
                                                then
                                                   Append
                                                     (Buf,
                                                      ASCII.LF
                                                      & UC_TRI_R & " "
                                                      & Trimmed
                                                      & ASCII.LF);
                                                end if;
                                             end;
                                          end if;
                                       end;
                                    end loop;
                                 end;
                              end if;

                           --  Assistant turn
                           elsif Role = "assistant" then
                              --  Capture token usage for context restore.
                              declare
                                 Usage : constant JSON_Value :=
                                   Get_Object (Msg, "usage");
                              begin
                                 if Usage.Kind /= JSON_Null_Type then
                                    declare
                                       Input_Count  : constant
                                         Natural :=
                                           Get_Integer (Usage, "input")
                                           + Get_Integer
                                               (Usage, "cacheRead")
                                           + Get_Integer
                                               (Usage, "cacheWrite");
                                       Output_Count : constant
                                         Natural :=
                                           Get_Integer
                                             (Usage, "output");
                                    begin
                                       Turn_Input  := Input_Count;
                                       Turn_Output := Output_Count;
                                       if Input_Count > 0
                                         or else Output_Count > 0
                                       then
                                          Last_Input  := Input_Count;
                                          Last_Output := Output_Count;
                                       end if;
                                    end;
                                 end if;
                              end;
                              --  Render content blocks.
                              if Msg.Has_Field ("content")
                                and then
                                  Msg.Get ("content").Kind
                                  = JSON_Array_Type
                              then
                                 declare
                                    Content        : constant
                                      JSON_Array :=
                                        Msg.Get ("content");
                                    Thinking_Parts : Unbounded_String;
                                 begin
                                    for I in 1 .. Length (Content) loop
                                       declare
                                          Block : constant JSON_Value :=
                                            Get (Content, I);
                                          BType : constant String    :=
                                            Get_String (Block, "type");
                                       begin
                                          --  thinking block
                                          if BType = "thinking" then
                                             declare
                                                Th : constant String :=
                                                  Ada.Strings.Fixed
                                                    .Trim
                                                      (Get_String
                                                         (Block,
                                                          "thinking"),
                                                       Ada.Strings
                                                         .Both);
                                             begin
                                                if Length
                                                     (Thinking_Parts)
                                                   > 0
                                                then
                                                   Append
                                                     (Thinking_Parts,
                                                      "" & ASCII.LF
                                                      & ASCII.LF);
                                                end if;
                                                Append
                                                  (Thinking_Parts, Th);
                                             end;

                                          --  text block
                                          elsif BType = "text" then
                                             declare
                                                Text : constant
                                                  String :=
                                                    Get_String
                                                      (Block, "text");
                                             begin
                                                if Text'Length > 0 then
                                                   if Length
                                                        (Thinking_Parts)
                                                      > 0
                                                   then
                                                      Render_Thinking_Block
                                                        (To_String
                                                           (Thinking_Parts));
                                                      Thinking_Parts :=
                                                        Null_Unbounded_String;
                                                   end if;
                                                   Append (Buf, Text);
                                                   Saw_Asst_Text := True;
                                                end if;
                                             end;

                                          --  toolCall block
                                          elsif BType = "toolCall" then
                                             if Length (Thinking_Parts)
                                                > 0
                                             then
                                                Render_Thinking_Block
                                                  (To_String
                                                     (Thinking_Parts));
                                                Thinking_Parts :=
                                                  Null_Unbounded_String;
                                             end if;
                                             declare
                                                Tool_Id   : constant
                                                  String :=
                                                    Get_String
                                                      (Block, "id");
                                                Tool_Name : constant
                                                  String :=
                                                    Get_String
                                                      (Block, "name");
                                                Args      : constant
                                                  JSON_Value :=
                                                    Get_Object
                                                      (Block,
                                                       "arguments");
                                                TR        : constant
                                                  Tool_Result_Entry :=
                                                    Find_TR (Tool_Id);
                                                Tok       : constant
                                                  String :=
                                                    (if Tool_Id'Length
                                                        > 0
                                                     then Hash_Tool_Id
                                                            (Tool_Id)
                                                     else "");
                                             begin
                                                if UUID'Length > 0
                                                  and then
                                                    Tok'Length > 0
                                                then
                                                   Append
                                                     (Buf,
                                                      ASCII.LF
                                                      & ASCII.LF
                                                      & UC_BOX_TL
                                                      & " " & UC_GEAR
                                                      & " " & Tool_Name
                                                      & " llm-chat+"
                                                      & UUID & "/tool/"
                                                      & Tok);
                                                else
                                                   Append
                                                     (Buf,
                                                      ASCII.LF
                                                      & ASCII.LF
                                                      & UC_BOX_TL
                                                      & " " & UC_GEAR
                                                      & " " & Tool_Name);
                                                end if;
                                                --  Show args.
                                                if Tool_Name = "edit"
                                                  and then
                                                    Args.Kind
                                                    /= JSON_Null_Type
                                                then
                                                   Append
                                                     (Buf,
                                                      ASCII.LF
                                                      & UC_BOX_V
                                                      & " path: "
                                                      & Get_String
                                                          (Args,
                                                           "path"));
                                                elsif Args.Kind
                                                   = JSON_Object_Type
                                                then
                                                   declare
                                                      procedure Show_Arg
                                                        (Name  :
                                                           UTF8_String;
                                                         Value :
                                                           JSON_Value)
                                                      is
                                                         Text  : constant
                                                           String :=
                                                             JSON_Scalar_Image
                                                               (Value);
                                                         Val_S : constant
                                                           String :=
                                                             (if
                                                                Text'Length
                                                                > 200
                                                              then
                                                                Text
                                                                  (Text'First
                                                                   ..
                                                                   Text'First
                                                                   + 196)
                                                                & UC_ELLIP
                                                              else Text);
                                                      begin
                                                         if Name
                                                            not in
                                                              "oldText"
                                                              | "newText"
                                                         then
                                                            Append
                                                              (Buf,
                                                               ASCII.LF
                                                               & UC_BOX_V
                                                               & " "
                                                               & Name
                                                               & ": "
                                                               & Val_S);
                                                         end if;
                                                      end Show_Arg;
                                                   begin
                                                      Args
                                                        .Map_JSON_Object
                                                          (Show_Arg
                                                             'Access);
                                                   end;
                                                end if;
                                                --  Result line.
                                                if TR.Is_Err then
                                                   declare
                                                      Err_Text :
                                                        constant
                                                        String :=
                                                          To_String
                                                            (TR.Text);
                                                      Preview  :
                                                        constant
                                                        String :=
                                                          First_Line
                                                            (Err_Text);
                                                      Display  :
                                                        constant
                                                        String :=
                                                          (if
                                                             Preview
                                                               'Length
                                                             > 80
                                                           then
                                                             Preview
                                                               (Preview
                                                                  'First
                                                                ..
                                                                Preview
                                                                  'First
                                                                  + 79)
                                                           else
                                                             Preview);
                                                   begin
                                                      if Display'Length
                                                         > 0
                                                      then
                                                         Append
                                                           (Buf,
                                                            ASCII.LF
                                                            & UC_BOX_BL
                                                            & " "
                                                            & UC_CROSS
                                                            & " "
                                                            & Display
                                                            & ASCII.LF
                                                            & ASCII.LF);
                                                      else
                                                         Append
                                                           (Buf,
                                                            ASCII.LF
                                                            & UC_BOX_BL
                                                            & " "
                                                            & UC_CROSS
                                                            & ASCII.LF
                                                            & ASCII.LF);
                                                      end if;
                                                   end;
                                                else
                                                   Append
                                                     (Buf,
                                                      ASCII.LF
                                                      & UC_BOX_BL
                                                      & " " & UC_CHECK
                                                      & ASCII.LF
                                                      & ASCII.LF);
                                                end if;
                                             end;
                                          end if;
                                       end;
                                    end loop;
                                    --  Flush any trailing thinking.
                                    if Length (Thinking_Parts) > 0 then
                                       Render_Thinking_Block
                                         (To_String (Thinking_Parts));
                                    end if;
                                 end;
                              end if;
                           end if;
                           --  toolResult role: skip (consumed in pass 1).
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
         Ada.Text_IO.Close (File);
      exception
         when Ex : others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            Acme.Window.Append
              (Win, FS,
               "[error rendering session history: "
               & Ada.Exceptions.Exception_Message (Ex) & "]"
               & ASCII.LF);
            return;
      end;

      --  Append footer for the final rendered turn (if any), then flush.
      if In_Turn and then Saw_Asst_Text then
         Turns_Rendered := Turns_Rendered + 1;
         Append
           (Buf,
            Format_Turn_Footer
              (Turn_N        => Turns_Rendered,
               UUID          => UUID,
               PID           => PID_Str,
               Input_Tokens  => Turn_Input,
               Output_Tokens => Turn_Output,
               Ctx_Window    => State.Context_Window,
               Model_Text    => To_String (Cur_Model)));
      end if;
      if Length (Buf) > 0 then
         Acme.Window.Append (Win, FS, To_String (Buf));
      end if;
      --  Restore turn count so subsequent live turns are numbered correctly.
      State.Set_Turn_Count (Turns_Rendered);
      if Last_Input > 0 or else Last_Output > 0 then
         State.Set_Turn_Tokens (Last_Input, Last_Output);
      end if;
   end Render_Session_History;

end Pi_Acme_App.History;
