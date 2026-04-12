--  Session_Lister body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Characters.Handling;
with Ada.Containers.Generic_Array_Sort;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
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

end Session_Lister;
