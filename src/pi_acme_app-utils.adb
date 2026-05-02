--  Pi_Acme_App.Utils body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Directories;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with GNAT.SHA256;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;
with Interfaces;             use Interfaces;
with Nine_P;                 use Nine_P;

package body Pi_Acme_App.Utils is

   --  POSIX getpid() — needed by Edit_Diff_Lines for temp-file names.
   function Getpid return Integer;
   pragma Import (C, Getpid, "getpid");

   --  ── String utilities ─────────────────────────────────────────────────

   function Str_Repeat (Text : String; N : Positive) return String is
      Result : String (1 .. Text'Length * N);
   begin
      for I in 0 .. N - 1 loop
         Result (I * Text'Length + 1 .. (I + 1) * Text'Length) := Text;
      end loop;
      return Result;
   end Str_Repeat;

   function Natural_Image (N : Natural) return String is
      Image : constant String := Natural'Image (N);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image;

   function Format_Kilo (N : Natural) return String is
   begin
      if N >= 1000 then
         declare
            Value       : constant Float   := Float (N) / 1000.0;
            Whole_Part  : constant Natural :=
              Natural (Float'Floor (Value));
            Frac_Part   : constant Natural :=
              Natural (Float'Floor
                         ((Value - Float (Whole_Part)) * 10.0));
         begin
            if Frac_Part = 0 then
               return Natural_Image (Whole_Part) & "k";
            else
               return Natural_Image (Whole_Part)
                      & "." & Natural_Image (Frac_Part) & "k";
            end if;
         end;
      end if;
      return Natural_Image (N);
   end Format_Kilo;

   function Format_Cost (Dmil : Natural) return String is

      function Pad4 (N : Natural) return String is
         Buf : String (1 .. 4) := "0000";
         V   : Natural         := N;
      begin
         Buf (4) := Character'Val (Character'Pos ('0') + V mod 10);
         V       := V / 10;
         Buf (3) := Character'Val (Character'Pos ('0') + V mod 10);
         V       := V / 10;
         Buf (2) := Character'Val (Character'Pos ('0') + V mod 10);
         V       := V / 10;
         Buf (1) := Character'Val (Character'Pos ('0') + V mod 10);
         return Buf;
      end Pad4;

   begin
      return "$"
             & Natural_Image (Dmil / 10_000)
             & "."
             & Pad4 (Dmil mod 10_000);
   end Format_Cost;

   function Agent_Stem (Path : String) return String is
      Slash : Natural := 0;
   begin
      for I in reverse Path'Range loop
         if Path (I) = '/' then
            Slash := I;
            exit;
         end if;
      end loop;
      declare
         Base   : constant String := Path (Slash + 1 .. Path'Last);
         Suffix : constant String := ".agent.md";
         Dot    : constant Natural :=
           (if Base'Length > Suffix'Length
              and then Base
                         (Base'Last - Suffix'Length + 1 .. Base'Last)
                       = Suffix
            then Base'Last - Suffix'Length
            else Base'Last);
      begin
         return Base (Base'First .. Dot);
      end;
   end Agent_Stem;

   function Nth_Field (Text : String; N : Positive) return String is
      Count   : Natural := 0;
      Start   : Natural := 0;
      In_Tok  : Boolean := False;
   begin
      for I in Text'Range loop
         if Text (I) in ' ' | ASCII.HT then
            if In_Tok then
               if Count = N then
                  return Text (Start .. I - 1);
               end if;
               In_Tok := False;
            end if;
         else
            if not In_Tok then
               In_Tok := True;
               Count  := Count + 1;
               Start  := I;
            end if;
         end if;
      end loop;
      if In_Tok and then Count = N then
         return Text (Start .. Text'Last);
      end if;
      return "";
   end Nth_Field;

   function Parse_Session_Token
     (Data       : String;
      Pid_Prefix : String) return String
   is
      Bare_Prefix : constant String := "llm-chat+";
   begin
      --  PID-tagged: "llm-chat+PID/UUID"
      if Data'Length > Pid_Prefix'Length
        and then
          Data (Data'First .. Data'First + Pid_Prefix'Length - 1)
          = Pid_Prefix
      then
         return Data (Data'First + Pid_Prefix'Length .. Data'Last);
      end if;
      --  Bare: "llm-chat+UUID" — accept only when UUID contains no '/'
      --  (a '/' would indicate it is PID-tagged for a different instance).
      if Data'Length > Bare_Prefix'Length
        and then
          Data (Data'First .. Data'First + Bare_Prefix'Length - 1)
          = Bare_Prefix
      then
         declare
            Rest : constant String :=
              Data (Data'First + Bare_Prefix'Length .. Data'Last);
         begin
            for C of Rest loop
               if C = '/' then
                  return "";
               end if;
            end loop;
            return Rest;
         end;
      end if;
      return "";
   end Parse_Session_Token;

   function Hash_Tool_Id (Tool_Id : String) return String is
   begin
      return GNAT.SHA256.Digest (Tool_Id) (1 .. 16);
   end Hash_Tool_Id;

   function Scan_Tool_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String
   is
      Prefix   : constant String  := "llm-chat+";
      Pref_Len : constant Natural := Prefix'Length;
   begin
      if Context'Length < Pref_Len then
         return "";
      end if;
      for I in Context'First .. Context'Last - Pref_Len + 1 loop
         if Context (I .. I + Pref_Len - 1) = Prefix then
            --  Advance past the UUID part: [0-9a-f-]+
            declare
               J : Natural := I + Pref_Len;
            begin
               while J <= Context'Last
                 and then
                   (Context (J) in '0' .. '9' | 'a' .. 'f' | '-')
               loop
                  J := J + 1;
               end loop;
               --  Require at least one char before "/tool/" and the
               --  separator itself.
               if J > I + Pref_Len
                 and then J + 5 <= Context'Last
                 and then Context (J .. J + 5) = "/tool/"
               then
                  --  Advance past the hex suffix: [0-9a-f]+
                  declare
                     H : Natural := J + 6;
                  begin
                     while H <= Context'Last
                       and then
                         (Context (H) in '0' .. '9' | 'a' .. 'f')
                     loop
                        H := H + 1;
                     end loop;
                     if H > J + 6 then
                        --  Token occupies Context(I .. H-1).
                        --  Convert to approximate body rune offsets.
                        declare
                           Tok_Q0 : constant Natural :=
                             Ctx_Start + (I - Context'First);
                           Tok_Q1 : constant Natural :=
                             Ctx_Start + (H - 1 - Context'First);
                        begin
                           if Tok_Q0 <= Anchor
                             and then Anchor <= Tok_Q1
                           then
                              return Context (I .. H - 1);
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return "";
   end Scan_Tool_Token;

   function Scan_Fork_Token
     (Context   : String;
      Ctx_Start : Natural;
      Anchor    : Natural) return String
   is
      Prefix   : constant String  := "fork+";
      Pref_Len : constant Natural := Prefix'Length;
   begin
      if Context'Length < Pref_Len then
         return "";
      end if;
      for I in Context'First .. Context'Last - Pref_Len + 1 loop
         if Context (I .. I + Pref_Len - 1) = Prefix then
            --  Advance past PID digits: [0-9]+
            declare
               J : Natural := I + Pref_Len;
            begin
               while J <= Context'Last
                 and then Context (J) in '0' .. '9'
               loop
                  J := J + 1;
               end loop;
               --  Require at least one digit, then '/'.
               if J > I + Pref_Len
                 and then J <= Context'Last
                 and then Context (J) = '/'
               then
                  --  Advance past UUID chars: [0-9a-f-]+
                  declare
                     K : Natural := J + 1;
                  begin
                     while K <= Context'Last
                       and then
                         (Context (K) in '0' .. '9' | 'a' .. 'f' | '-')
                     loop
                        K := K + 1;
                     end loop;
                     --  Require at least one UUID char, then '/'.
                     if K > J + 1
                       and then K <= Context'Last
                       and then Context (K) = '/'
                     then
                        --  Advance past turn digits: [0-9]+
                        declare
                           L : Natural := K + 1;
                        begin
                           while L <= Context'Last
                             and then Context (L) in '0' .. '9'
                           loop
                              L := L + 1;
                           end loop;
                           --  Require at least one digit.
                           if L > K + 1 then
                              --  Token is Context(I .. L-1).
                              declare
                                 Tok_Q0 : constant Natural :=
                                   Ctx_Start + (I - Context'First);
                                 Tok_Q1 : constant Natural :=
                                   Ctx_Start + (L - 1 - Context'First);
                              begin
                                 if Tok_Q0 <= Anchor
                                   and then Anchor <= Tok_Q1
                                 then
                                    return Context (I .. L - 1);
                                 end if;
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return "";
   end Scan_Fork_Token;

   --  ── Edit_Diff_Lines ───────────────────────────────────────────────────
   --
   --  Run `diff -u` on Old_Text vs New_Text, strip the ---/+++/@@ header
   --  lines produced by unified diff, and return the remaining body lines
   --  joined by ASCII.LF.  Truncates to Max_L body lines and appends a
   --  trailer ("… N more lines") when the diff exceeds the limit.
   --
   --  Returns "(no changes)" when Old_Text = New_Text or when the diff
   --  produces no body lines.  Returns "(diff error)" if the subprocess
   --  cannot be started.
   --
   --  Matches the behaviour of the Python reference's edit_diff_lines().

   function Edit_Diff_Lines
     (Old_Text : String;
      New_Text : String;
      Max_L    : Positive := 30) return String
   is
      use GNATCOLL.OS.FS;
      use GNATCOLL.OS.Process;

      Pid_S  : constant String :=
        Natural_Image (Natural (Getpid));
      Old_F  : constant String :=
        "/tmp/pi-acme-diff-" & Pid_S & "-old";
      New_F  : constant String :=
        "/tmp/pi-acme-diff-" & Pid_S & "-new";

      --  Write Text to a temporary file at Path using binary stream I/O.
      --  Ada.Streams.Stream_IO is used instead of Ada.Text_IO so that the
      --  raw UTF-8 bytes are written as-is.  Ada.Text_IO.Put with -gnatW8
      --  re-encodes each Latin-1 byte > 16#7F# as a UTF-8 sequence,
      --  double-encoding content that is already UTF-8.
      procedure Write_Temp (Path : String; Text : String) is
         use Ada.Streams.Stream_IO;
         File : File_Type;
      begin
         Create (File, Out_File, Path);
         String'Write (Stream (File), Text);
         Close (File);
      end Write_Temp;

      Buffer : Unbounded_String;

   begin
      if Old_Text = New_Text then
         return "(no changes)";
      end if;

      Write_Temp (Old_F, Old_Text);
      Write_Temp (New_F, New_Text);

      --  Spawn diff -u and capture stdout.
      declare
         Stdout_R, Stdout_W : File_Descriptor;
         Null_In  : constant File_Descriptor :=
           Open (Null_File, Read_Mode);
         Null_Out : constant File_Descriptor :=
           Open (Null_File, Write_Mode);
         Args     : Argument_List;
         Handle   : Process_Handle;
         Chunk    : String (1 .. 4096);
         N        : Integer;
      begin
         Open_Pipe (Stdout_R, Stdout_W);
         Args.Append ("diff");
         Args.Append ("-u");
         Args.Append (Old_F);
         Args.Append (New_F);
         Handle := Start (Args   => Args,
                          Stdin  => Null_In,
                          Stdout => Stdout_W,
                          Stderr => Null_Out);
         Close (Null_In);
         Close (Stdout_W);
         Close (Null_Out);
         loop
            N := Read (Stdout_R, Chunk);
            exit when N <= 0;
            Append (Buffer, Chunk (1 .. N));
         end loop;
         Close (Stdout_R);
         declare
            Dummy : constant Integer := Wait (Handle);
            pragma Unreferenced (Dummy);
         begin
            null;
         end;
      end;

      --  Delete temp files (ignore errors).
      begin
         Ada.Directories.Delete_File (Old_F);
      exception
         when others => null;
      end;
      begin
         Ada.Directories.Delete_File (New_F);
      exception
         when others => null;
      end;

      --  Parse diff output: skip ---/+++/@@ lines; collect body lines;
      --  truncate to Max_L with an ellipsis trailer.
      declare
         Raw        : constant String  := To_String (Buffer);
         Result     : Unbounded_String;
         Line_Start : Natural          := Raw'First;
         Line_Count : Natural          := 0;
         Skipped    : Natural          := 0;

         --  Append one body line (without its terminating newline) to
         --  Result, respecting the Max_L truncation limit.
         procedure Process_Line (L : String) is
            Skip : constant Boolean :=
              (L'Length >= 3
                 and then L (L'First .. L'First + 2) = "---")
              or else (L'Length >= 3
                 and then L (L'First .. L'First + 2) = "+++")
              or else (L'Length >= 2
                 and then L (L'First .. L'First + 1) = "@@")
              or else (L'Length >= 1
                 and then L (L'First) = '\');
         begin
            if Skip then
               return;
            end if;
            if Line_Count < Max_L then
               if Length (Result) > 0 then
                  Append (Result, ASCII.LF);
               end if;
               Append (Result, L);
               Line_Count := Line_Count + 1;
            else
               Skipped := Skipped + 1;
            end if;
         end Process_Line;

      begin
         for I in Raw'Range loop
            if Raw (I) = ASCII.LF then
               Process_Line (Raw (Line_Start .. I - 1));
               Line_Start := I + 1;
            end if;
         end loop;
         --  Last line when the diff output has no trailing newline.
         if Line_Start <= Raw'Last then
            Process_Line (Raw (Line_Start .. Raw'Last));
         end if;
         if Skipped > 0 then
            if Length (Result) > 0 then
               Append (Result, ASCII.LF);
            end if;
            Append
              (Result,
               UC_ELLIP & " " & Natural_Image (Skipped) & " more lines");
         end if;
         if Length (Result) = 0 then
            return "(no changes)";
         end if;
         return To_String (Result);
      end;
   exception
      when others => return "(diff error)";
   end Edit_Diff_Lines;

   --  ── Extract_Plumb_Data ────────────────────────────────────────────────
   --
   --  A plumb message is 7 newline-separated fields:
   --  src, dst, wdir, type, attr, ndata, data

   function Extract_Plumb_Data (Raw : Byte_Array) return String is
      Count   : Natural := 0;
      Start   : Natural := Raw'First;
      N_Data  : Natural := 0;
   begin
      for I in Raw'Range loop
         if Raw (I) = Uint8 (Character'Pos (ASCII.LF)) then
            Count := Count + 1;
            if Count = 6 then
               --  Field 5 (0-indexed) is ndata; parse it, then return
               --  the data field that immediately follows this newline.
               declare
                  N_Data_String : String (1 .. I - Start);
               begin
                  for J in N_Data_String'Range loop
                     N_Data_String (J) :=
                       Character'Val (Raw (Start + J - 1));
                  end loop;
                  begin
                     N_Data := Natural'Value (N_Data_String);
                  exception
                     when Constraint_Error => N_Data := 0;
                  end;
               end;
               --  Data field starts at I + 1 (the byte after this \n).
               --  Use N_Data to bound it; this strips any trailing \n
               --  that the plumber appends to the message.
               declare
                  Data_Start : constant Natural := I + 1;
                  Available  : constant Natural :=
                    (if Data_Start <= Raw'Last
                     then Raw'Last - Data_Start + 1
                     else 0);
                  Length     : constant Natural :=
                    (if N_Data > 0
                     then Natural'Min (N_Data, Available)
                     else Available);
                  Result     : String (1 .. Length);
               begin
                  for J in Result'Range loop
                     Result (J) := Character'Val (Raw (Data_Start + J - 1));
                  end loop;
                  return Result;
               end;
            end if;
            Start := I + 1;
         end if;
      end loop;
      return "";
   end Extract_Plumb_Data;

   --  ── Turn footer builders ─────────────────────────────────────────────

   function Format_Turn_Summary
     (Input_Tokens      : Natural;
      Output_Tokens     : Natural;
      Ctx_Window        : Natural;
      Model_Text        : String;
      Turn_Cost_Dmil    : Natural := 0;
      Session_Cost_Dmil : Natural := 0) return String
   is
      Parts : Unbounded_String;
   begin
      if Input_Tokens > 0 and then Ctx_Window > 0 then
         Append
           (Parts,
            "ctx "
            & Format_Kilo (Input_Tokens)
            & "/" & Format_Kilo (Ctx_Window)
            & " ("
            & Natural_Image (Input_Tokens * 100 / Ctx_Window)
            & "%)");
      end if;
      if Output_Tokens > 0 then
         if Length (Parts) > 0 then
            Append (Parts, " | ");
         end if;
         Append
           (Parts,
            "^" & Format_Kilo (Output_Tokens)
            & " out");
      end if;
      if Turn_Cost_Dmil > 0 then
         if Length (Parts) > 0 then
            Append (Parts, " | ");
         end if;
         Append (Parts, Format_Cost (Turn_Cost_Dmil) & " turn");
      end if;
      if Session_Cost_Dmil > 0 then
         if Length (Parts) > 0 then
            Append (Parts, " | ");
         end if;
         Append (Parts, Format_Cost (Session_Cost_Dmil) & " session");
      end if;
      if Model_Text'Length > 0 then
         if Length (Parts) > 0 then
            Append (Parts, " | ");
         end if;
         Append (Parts, Model_Text);
      end if;
      return
        (if Length (Parts) > 0
         then "[" & To_String (Parts) & "]"
         else "");
   end Format_Turn_Summary;

   function Format_Turn_Footer
     (Turn_N            : Positive;
      UUID              : String;
      PID               : String;
      Input_Tokens      : Natural := 0;
      Output_Tokens     : Natural := 0;
      Ctx_Window        : Natural := 0;
      Model_Text        : String  := "";
      Turn_Cost_Dmil    : Natural := 0;
      Session_Cost_Dmil : Natural := 0) return String
   is
      Summary : constant String :=
        Format_Turn_Summary
          (Input_Tokens      => Input_Tokens,
           Output_Tokens     => Output_Tokens,
           Ctx_Window        => Ctx_Window,
           Model_Text        => Model_Text,
           Turn_Cost_Dmil    => Turn_Cost_Dmil,
           Session_Cost_Dmil => Session_Cost_Dmil);
   begin
      return ASCII.LF & ASCII.LF
             & (if Summary'Length > 0 then Summary & " " else "")
             & "fork+" & PID & "/" & UUID & "/"
             & Natural_Image (Turn_N) & ASCII.LF
             & Str_Repeat (UC_DBL_H, 60)
             & ASCII.LF & ASCII.LF;
   end Format_Turn_Footer;

   --  ── JSON field helpers ────────────────────────────────────────────────

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

   function Get_Integer
     (Val   : JSON_Value;
      Field : UTF8_String) return Natural
   is
   begin
      if Val.Has_Field (Field)
        and then Val.Get (Field).Kind = JSON_Int_Type
      then
         return Natural (Long_Integer'(Val.Get (Field).Get));
      end if;
      return 0;
   end Get_Integer;

   function Get_Cost_Dmil
     (Val   : JSON_Value;
      Field : UTF8_String) return Natural
   is
   begin
      if not Val.Has_Field (Field) then
         return 0;
      end if;
      declare
         F : constant JSON_Value := Val.Get (Field);
      begin
         if F.Kind = JSON_Float_Type then
            declare
               Cost : constant Long_Float := Get_Long_Float (F);
            begin
               if Cost > 0.0 then
                  return Natural
                    (Long_Float'Floor (Cost * 10_000.0 + 0.5));
               end if;
            end;
         elsif F.Kind = JSON_Int_Type then
            declare
               Cost_I : constant Long_Integer := Long_Integer'(F.Get);
            begin
               if Cost_I > 0 then
                  return Natural (Cost_I) * 10_000;
               end if;
            end;
         end if;
      end;
      return 0;
   end Get_Cost_Dmil;

   function Get_Boolean
     (Val   : JSON_Value;
      Field : UTF8_String) return Boolean
   is
   begin
      if Val.Has_Field (Field)
        and then Val.Get (Field).Kind = JSON_Boolean_Type
      then
         return Val.Get (Field).Get;
      end if;
      return False;
   end Get_Boolean;

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

   function JSON_Scalar_Image (Val : JSON_Value) return String is
   begin
      if Val.Kind = JSON_String_Type then
         return Val.Get;
      elsif Val.Kind in
        JSON_Int_Type | JSON_Boolean_Type | JSON_Float_Type
      then
         return Val.Write;
      else
         return "...";
      end if;
   end JSON_Scalar_Image;

   function Format_Tool_Field
     (Name    : String;
      Value   : String;
      Max_Len : Positive := 200) return String
   is
      Trimmed : constant String :=
        (if Value'Length > Max_Len
         then Value (Value'First .. Value'First + Max_Len - 4) & UC_ELLIP
         else Value);
      Result  : Unbounded_String;
      Pos     : Natural := Trimmed'First;
      First   : Boolean := True;
   begin
      for I in Trimmed'Range loop
         if Trimmed (I) = ASCII.LF then
            if First then
               Append
                 (Result,
                  UC_BOX_V & " " & Name & ": "
                  & Trimmed (Pos .. I - 1));
               First := False;
            else
               Append
                 (Result,
                  "" & ASCII.LF & UC_BOX_V & " "
                  & Trimmed (Pos .. I - 1));
            end if;
            Pos := I + 1;
         end if;
      end loop;
      --  Remainder after the last newline (or the whole value when there
      --  are no newlines).
      if First then
         Append
           (Result,
            UC_BOX_V & " " & Name & ": "
            & Trimmed (Pos .. Trimmed'Last));
      else
         Append
           (Result,
            "" & ASCII.LF & UC_BOX_V & " "
            & Trimmed (Pos .. Trimmed'Last));
      end if;
      return To_String (Result);
   end Format_Tool_Field;

end Pi_Acme_App.Utils;
