--  Session_Lister body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Characters.Handling;
with Ada.Containers.Generic_Array_Sort;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.SHA256;
with GNATCOLL.JSON;          use GNATCOLL.JSON;

package body Session_Lister is

   --  ── Encode_Cwd ────────────────────────────────────────────────────────

   function Encode_Cwd (Cwd : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("--");
      Start  : constant Natural :=
        (if Cwd'Length > 0 and then Cwd (Cwd'First) = '/'
         then Cwd'First + 1
         else Cwd'First);
   begin
      for I in Start .. Cwd'Last loop
         Append (Result, (if Cwd (I) = '/' then '-' else Cwd (I)));
      end loop;
      Append (Result, "--");
      return To_String (Result);
   end Encode_Cwd;

   --  ── Sessions_Dir ──────────────────────────────────────────────────────

   function Sessions_Dir (Cwd : String) return String is
      use Ada.Environment_Variables;
      Home : constant String :=
        (if Exists ("HOME") then Value ("HOME") else "");
   begin
      return Home & "/.pi/agent/sessions/" & Encode_Cwd (Cwd);
   end Sessions_Dir;

   --  ── Format_Timestamp ─────────────────────────────────────────────────

   function Format_Timestamp (Ts : String) return String is
   begin
      if Ts'Length < 16 then
         return Ts;
      end if;
      declare
         Result : String := Ts (Ts'First .. Ts'First + 15);
      begin
         for I in Result'Range loop
            if Result (I) = 'T' then
               Result (I) := ' ';
            end if;
         end loop;
         return Result;
      end;
   end Format_Timestamp;

   --  ── JSON helpers ─────────────────────────────────────────────────────

   --  Safely read a string field; return "" if absent or wrong type.
   function Get_String
     (Val   : JSON_Value;
      Field : UTF8_String) return String
   is
   begin
      if Val.Has_Field (Field)
        and then Val.Get (Field).Kind = JSON_String_Type
      then
         return Val.Get (Field).Get;
      end if;
      return "";
   end Get_String;

   --  Safely read an object field; return JSON_Null if absent or wrong type.
   function Get_Object
     (Val   : JSON_Value;
      Field : UTF8_String) return JSON_Value
   is
   begin
      if Val.Has_Field (Field)
        and then Val.Get (Field).Kind = JSON_Object_Type
      then
         return Val.Get (Field);
      end if;
      return JSON_Null;
   end Get_Object;

   --  Extract the text of the first user message content block.
   function First_User_Text (Message_Event : JSON_Value) return String is
      Msg : JSON_Value;
   begin
      if not Message_Event.Has_Field ("message") then
         return "";
      end if;
      Msg := Message_Event.Get ("message");
      if Get_String (Msg, "role") /= "user" then
         return "";
      end if;
      if not Msg.Has_Field ("content")
        or else Msg.Get ("content").Kind /= JSON_Array_Type
      then
         return "";
      end if;
      declare
         Content : constant JSON_Array := Msg.Get ("content");
      begin
         for I in 1 .. Length (Content) loop
            declare
               Block : constant JSON_Value := Get (Content, I);
            begin
               if Block.Kind = JSON_Object_Type
                 and then Get_String (Block, "type") = "text"
               then
                  declare
                     Text : constant String := Get_String (Block, "text");
                  begin
                     if Text'Length > 0 then
                        --  Collapse whitespace runs to a single space.
                        declare
                           Result   : Unbounded_String;
                           In_Space : Boolean := False;
                        begin
                           for C of Text loop
                              if Ada.Characters.Handling.Is_Space (C) then
                                 if not In_Space then
                                    Append (Result, ' ');
                                    In_Space := True;
                                 end if;
                              else
                                 Append (Result, C);
                                 In_Space := False;
                              end if;
                           end loop;
                           declare
                              Trimmed : constant String :=
                                To_String
                                  (Ada.Strings.Unbounded.Trim
                                     (Result, Ada.Strings.Both));
                           begin
                              if Trimmed'Length <= SNIPPET_MAX then
                                 return Trimmed;
                              end if;
                              return Trimmed
                                       (Trimmed'First
                                        .. Trimmed'First
                                           + SNIPPET_MAX - 1)
                                     & "...";
                           end;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end;
      return "";
   end First_User_Text;

   --  ── Parse_Session_File ────────────────────────────────────────────────

   function Parse_Session_File (Path : String) return Session_Info is
      File   : Ada.Text_IO.File_Type;
      Result : Session_Info;
      Line_N : Natural := 0;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
         begin
            if Line'Length > 0 then
               Line_N := Line_N + 1;
               declare
                  Parse_Result : constant Read_Result := Read (Line);
               begin
                  if Parse_Result.Success then
                     declare
                        Obj  : constant JSON_Value := Parse_Result.Value;
                        Kind : constant String     :=
                          Get_String (Obj, "type");
                     begin
                        if Line_N = 1 and then Kind = "session" then
                           Result.UUID :=
                             To_Unbounded_String
                               (Get_String (Obj, "id"));
                           Result.Date :=
                             To_Unbounded_String
                               (Format_Timestamp
                                  (Get_String (Obj, "timestamp")));

                        elsif Kind = "session_info" then
                           declare
                              Session_Name : constant String :=
                                Get_String (Obj, "name");
                           begin
                              if Session_Name'Length > 0 then
                                 Result.Name :=
                                   To_Unbounded_String (Session_Name);
                              end if;
                           end;

                        elsif Kind = "message"
                          and then Length (Result.Snippet) = 0
                        then
                           declare
                              Snippet : constant String :=
                                First_User_Text (Obj);
                           begin
                              if Snippet'Length > 0 then
                                 Result.Snippet :=
                                   To_Unbounded_String (Snippet);
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
      return Result;
   exception
      when Ex : others =>
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "Parse_Session_File failed for " & Path & ": "
            & Ada.Exceptions.Exception_Information (Ex));
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Result;
   end Parse_Session_File;

   --  ── List_Sessions ─────────────────────────────────────────────────────

   function List_Sessions
     (Cwd : String) return Session_Vectors.Vector
   is
      use Ada.Directories;
      Dir    : constant String := Sessions_Dir (Cwd);
      Result : Session_Vectors.Vector;
   begin
      if not Exists (Dir) then
         return Result;
      end if;

      declare
         Search    : Search_Type;
         Dir_Entry : Directory_Entry_Type;
      begin
         Start_Search (Search, Dir, "*.jsonl",
                       (Ordinary_File => True, others => False));
         while More_Entries (Search) loop
            Get_Next_Entry (Search, Dir_Entry);
            declare
               Info : constant Session_Info :=
                 Parse_Session_File (Full_Name (Dir_Entry));
            begin
               if Length (Info.UUID) > 0 then
                  Result.Append (Info);
               end if;
            end;
         end loop;
         End_Search (Search);
      end;

      --  Sort newest first by Date (ISO strings sort lexicographically).
      declare
         procedure Swap (A, B : in out Session_Info) is
            Tmp : constant Session_Info := A;
         begin
            A := B;
            B := Tmp;
         end Swap;

         function Newer (A, B : Session_Info) return Boolean is
         begin
            return To_String (A.Date) > To_String (B.Date);
         end Newer;

         type Info_Array is
           array (Natural range <>) of Session_Info;

         procedure Sort_Array is new Ada.Containers.Generic_Array_Sort
           (Index_Type   => Natural,
            Element_Type => Session_Info,
            Array_Type   => Info_Array,
            "<"          => Newer);

         Arr : Info_Array (0 .. Natural (Result.Length) - 1);
      begin
         for I in Arr'Range loop
            Arr (I) := Result (I);
         end loop;
         Sort_Array (Arr);
         Result.Clear;
         for Element of Arr loop
            Result.Append (Element);
         end loop;
      end;

      return Result;
   end List_Sessions;

   --  ── Find_Session_File ─────────────────────────────────────────────────

   function Find_Session_File (UUID : String) return String is
      use Ada.Directories;
      use Ada.Environment_Variables;

      Home    : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME")
         else "");
      Root    : constant String := Home & "/.pi/agent/sessions";
      Pattern : constant String := "*" & UUID & "*.jsonl";
      Result  : Unbounded_String;
   begin
      if not Ada.Directories.Exists (Root) then
         return "";
      end if;

      declare
         Dir_Search : Search_Type;
         Dir_Entry  : Directory_Entry_Type;
      begin
         Start_Search
           (Dir_Search, Root, "*",
            (Directory => True, others => False));
         Outer_Loop :
         while More_Entries (Dir_Search) loop
            Get_Next_Entry (Dir_Search, Dir_Entry);
            declare
               Base : constant String := Simple_Name (Dir_Entry);
            begin
               if Base /= "." and then Base /= ".." then
                  declare
                     Sub_Dir    : constant String := Full_Name (Dir_Entry);
                     Sub_Search : Search_Type;
                     Sub_Entry  : Directory_Entry_Type;
                  begin
                     Start_Search
                       (Sub_Search, Sub_Dir, Pattern,
                        (Ordinary_File => True, others => False));
                     if More_Entries (Sub_Search) then
                        Get_Next_Entry (Sub_Search, Sub_Entry);
                        Result :=
                          To_Unbounded_String (Full_Name (Sub_Entry));
                     end if;
                     End_Search (Sub_Search);
                  end;
               end if;
            end;
            exit Outer_Loop when Length (Result) > 0;
         end loop Outer_Loop;
         End_Search (Dir_Search);
      end;

      return To_String (Result);
   exception
      when others => return "";
   end Find_Session_File;

   --  ── Fork_Session ──────────────────────────────────────────────────────

   function Fork_Session
     (Source_UUID : String;
      After_Turn  : Positive;
      Target_Cwd  : String) return String
   is

      --  ── Fork_UUID helper ──────────────────────────────────────────────
      --
      --  Derive a UUID from the SHA-256 of (source UUID / turn / clock).
      --  The first 32 hex characters are formatted as an 8-4-4-4-12 UUID
      --  with the version nibble forced to '4'.  Pi treats session UUIDs
      --  as opaque filename stems, so RFC 4122 variant bits are not set.

      function Fork_UUID return String is
         use Ada.Calendar;
         Seed : constant String :=
           Source_UUID & "/"
           & Positive'Image (After_Turn) & "/"
           & Duration'Image (Seconds (Clock));
         Hash : constant String := GNAT.SHA256.Digest (Seed);
         --  Hash is 64 lowercase hex characters; use the first 32.
         H    : constant String := Hash (Hash'First .. Hash'First + 31);
      begin
         return H (H'First      .. H'First +  7)   --   8 hex chars
                & "-"
                & H (H'First +  8 .. H'First + 11)  --   4 hex chars
                & "-4"                               --   version nibble
                & H (H'First + 13 .. H'First + 15)  --   3 hex chars
                & "-"
                & H (H'First + 16 .. H'First + 19)  --   4 hex chars
                & "-"
                & H (H'First + 20 .. H'First + 31); --  12 hex chars
      end Fork_UUID;

      --  ── ISO-8601 timestamp helper ─────────────────────────────────────
      --
      --  Ada.Calendar.Formatting.Image returns "YYYY-MM-DD HH:MM:SS.SS"
      --  in one call — no arithmetic, no rounding, no padding helpers.
      --  We replace the space separator with 'T' to produce ISO-8601.

      function Now_Timestamp return String is
         use Ada.Calendar.Formatting;
         Raw : String := Image (Ada.Calendar.Clock,
                                Include_Time_Fraction => True);
      begin
         for I in Raw'Range loop
            if Raw (I) = ' ' then
               Raw (I) := 'T';
               exit;
            end if;
         end loop;
         return Raw;
      end Now_Timestamp;

      Source_Path  : constant String := Find_Session_File (Source_UUID);
      New_UUID     : constant String := Fork_UUID;
      Orig_Name    : Unbounded_String;

      package String_Vectors is new Ada.Containers.Vectors
        (Index_Type   => Natural,
         Element_Type => Unbounded_String);
      Source_Lines : String_Vectors.Vector;

   begin
      if Source_Path'Length = 0 then
         return "";
      end if;

      --  ── Pass 1: read all source lines into memory ─────────────────────

      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Source_Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            Source_Lines.Append
              (To_Unbounded_String (Ada.Text_IO.Get_Line (File)));
         end loop;
         Ada.Text_IO.Close (File);
      exception
         when Ex : others =>
            if Ada.Text_IO.Is_Open (File) then
               Ada.Text_IO.Close (File);
            end if;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Fork_Session: cannot read source: "
               & Ada.Exceptions.Exception_Message (Ex));
            return "";
      end;

      --  ── Pass 2: find cut point and collect original session name ──────
      --
      --  A turn completes when we have seen at least one user message and
      --  then at least one assistant message (the final text response).
      --  The next user message marks the start of a new turn.  We stop
      --  after After_Turn complete turns.

      declare
         Turns_Complete : Natural := 0;
         --  True once we have seen the assistant response in the current turn.
         Saw_Assistant  : Boolean := False;
         --  True while we are inside a turn (after a user message).
         In_Turn        : Boolean := False;
         --  Index (0-based into Source_Lines) of the last line to include.
         Cut_Index      : Integer := -1;
         Line_N         : Natural := 0;
      begin
         for I in Source_Lines.First_Index .. Source_Lines.Last_Index loop
            declare
               Line  : constant String := To_String (Source_Lines (I));
               Parse : constant Read_Result := Read (Line);
            begin
               Line_N := Line_N + 1;

               --  Skip blank lines and non-JSON lines silently.
               if Parse.Success then
                  declare
                     Obj  : constant JSON_Value := Parse.Value;
                     Kind : constant String     := Get_String (Obj, "type");
                  begin

                     --  Extract original session name for the fork header.
                     if Kind = "session_info" then
                        declare
                           N : constant String := Get_String (Obj, "name");
                        begin
                           if N'Length > 0 then
                              Orig_Name := To_Unbounded_String (N);
                           end if;
                        end;

                     elsif Kind = "message" then
                        declare
                           Msg  : constant JSON_Value :=
                             Get_Object (Obj, "message");
                           Role : constant String     :=
                             Get_String (Msg, "role");
                        begin
                           if Role = "user" then
                              --  Starting a new turn; if the previous turn
                              --  was complete we may already be at the cut.
                              if In_Turn and then Saw_Assistant then
                                 Turns_Complete := Turns_Complete + 1;
                                 if Turns_Complete = After_Turn then
                                    --  Cut point is just before this user msg.
                                    Cut_Index := I - 1;
                                    exit;
                                 end if;
                              end if;
                              In_Turn       := True;
                              Saw_Assistant := False;

                           elsif Role = "assistant" then
                              --  Mark that the current turn has a response.
                              --  Only count text-bearing assistant messages
                              --  (toolCall-only messages do not close a turn).
                              if In_Turn
                                and then Msg.Has_Field ("content")
                                and then Msg.Get ("content").Kind
                                         = JSON_Array_Type
                              then
                                 declare
                                    Content : constant JSON_Array :=
                                      Msg.Get ("content");
                                    Has_Text : Boolean := False;
                                 begin
                                    for J in 1 .. Length (Content) loop
                                       if Get_String
                                            (Get (Content, J), "type")
                                          = "text"
                                       then
                                          Has_Text := True;
                                          exit;
                                       end if;
                                    end loop;
                                    if Has_Text then
                                       Saw_Assistant := True;
                                    end if;
                                 end;
                              end if;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;

         --  End of file: if the last turn is complete and we haven't cut yet,
         --  use the entire file.
         if Cut_Index = -1 then
            if In_Turn and then Saw_Assistant then
               Turns_Complete := Turns_Complete + 1;
            end if;
            if Turns_Complete >= After_Turn then
               Cut_Index := Source_Lines.Last_Index;
            end if;
         end if;

         if Cut_Index < 0 then
            --  Fewer complete turns than requested.
            return "";
         end if;

         --  ── Write forked session file ──────────────────────────────────

         declare
            Target_Dir : constant String := Sessions_Dir (Target_Cwd);
            New_Path   : constant String :=
              Target_Dir & "/" & New_UUID & ".jsonl";
            Fork_Name  : constant String :=
              "Fork of "
              & (if Length (Orig_Name) > 0
                 then To_String (Orig_Name)
                 else Source_UUID (Source_UUID'First
                                   .. (if Source_UUID'Length >= 8
                                       then Source_UUID'First + 7
                                       else Source_UUID'Last))
                      & "...")
              & " @" & Positive'Image (After_Turn)
                         (2 .. Positive'Image (After_Turn)'Last);
            Out_File   : Ada.Text_IO.File_Type;
         begin
            Ada.Directories.Create_Path (Target_Dir);
            Ada.Text_IO.Create (Out_File, Ada.Text_IO.Out_File, New_Path);

            --  Header line: new UUID and current timestamp.
            Ada.Text_IO.Put_Line
              (Out_File,
               "{""type"":""session"",""id"":"""
               & New_UUID & """,""timestamp"":"""
               & Now_Timestamp & """}");

            --  Session-info line with fork name.
            Ada.Text_IO.Put_Line
              (Out_File,
               "{""type"":""session_info"",""name"":"""
               & Fork_Name & """}");

            --  Copy source lines, skipping the source header (line 0)
            --  and any source session_info line (already handled above).
            for I in Source_Lines.First_Index .. Cut_Index loop
               declare
                  Line  : constant String :=
                    To_String (Source_Lines (I));
                  Parse : constant Read_Result := Read (Line);
               begin
                  if Parse.Success then
                     declare
                        Kind : constant String :=
                          Get_String (Parse.Value, "type");
                     begin
                        if Kind /= "session"
                          and then Kind /= "session_info"
                        then
                           Ada.Text_IO.Put_Line (Out_File, Line);
                        end if;
                     end;
                  end if;
               end;
            end loop;

            Ada.Text_IO.Close (Out_File);
            return New_UUID;
         exception
            when Ex : others =>
               if Ada.Text_IO.Is_Open (Out_File) then
                  Ada.Text_IO.Close (Out_File);
               end if;
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "Fork_Session: cannot write target: "
                  & Ada.Exceptions.Exception_Message (Ex));
               return "";
         end;
      end;
   end Fork_Session;

end Session_Lister;
