--  Pi_Acme_App body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;             use Interfaces;
with GNAT.SHA256;
with GNATCOLL.JSON;          use GNATCOLL.JSON;
with GNATCOLL.OS.FS;
with GNATCOLL.OS.Process;
with Nine_P;                 use Nine_P;
with Nine_P.Client;          use Nine_P.Client;
with Acme;
with Acme.Event_Parser;
with Acme.Raw_Events;
with Pi_RPC;
with Session_Lister;         use Session_Lister;

package body Pi_Acme_App is

   --  POSIX getpid() — used to build window-specific selector tokens.
   function Getpid return Integer;
   pragma Import (C, Getpid, "getpid");

   --  ── UTF-8 helpers ─────────────────────────────────────────────────────

   --  Repeat string Text exactly N times.
   function Str_Repeat (Text : String; N : Positive) return String is
      Result : String (1 .. Text'Length * N);
   begin
      for I in 0 .. N - 1 loop
         Result (I * Text'Length + 1 .. (I + 1) * Text'Length) := Text;
      end loop;
      return Result;
   end Str_Repeat;

   --  ── UTF-8 pseudographic constants ─────────────────────────────────────
   --  Each constant holds the UTF-8 byte sequence for one Unicode character.
   UC_BULLET : constant String :=  --  ●  U+25CF
     Character'Val (16#E2#) & Character'Val (16#97#) & Character'Val (16#8F#);
   UC_DBL_H  : constant String :=  --  ═  U+2550
     Character'Val (16#E2#) & Character'Val (16#95#) & Character'Val (16#90#);
   UC_BOX_V  : constant String :=  --  │  U+2502
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#82#);
   UC_BOX_TL : constant String :=  --  ┌  U+250C
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#8C#);
   UC_BOX_BL : constant String :=  --  └  U+2514
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#94#);
   UC_GEAR   : constant String :=  --  ⚙  U+2699
     Character'Val (16#E2#) & Character'Val (16#9A#) & Character'Val (16#99#);
   UC_CHECK  : constant String :=  --  ✓  U+2713
     Character'Val (16#E2#) & Character'Val (16#9C#) & Character'Val (16#93#);
   UC_CROSS  : constant String :=  --  ✗  U+2717
     Character'Val (16#E2#) & Character'Val (16#9C#) & Character'Val (16#97#);
   UC_TRI_R  : constant String :=  --  ▶  U+25B6
     Character'Val (16#E2#) & Character'Val (16#96#) & Character'Val (16#B6#);
   UC_WARN   : constant String :=  --  ⚠  U+26A0
     Character'Val (16#E2#) & Character'Val (16#9A#) & Character'Val (16#A0#);
   UC_ELLIP  : constant String :=  --  …  U+2026
     Character'Val (16#E2#) & Character'Val (16#80#) & Character'Val (16#A6#);
   UC_HORIZ  : constant String :=  --  ─  U+2500
     Character'Val (16#E2#) & Character'Val (16#94#) & Character'Val (16#80#);
   UC_RETRY  : constant String :=  --  ↻  U+21BB
     Character'Val (16#E2#) & Character'Val (16#86#) & Character'Val (16#BB#);
   UC_HOOK_L : constant String :=  --  ↩  U+21A9
     Character'Val (16#E2#) & Character'Val (16#86#) & Character'Val (16#A9#);

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
      function Text_Emitted       return Boolean is (P_Text_Emitted);
      function Has_Text_Delta     return Boolean is (P_Has_Text_Delta);
      function Pending_Stats      return Boolean is (P_Pending_Stats);
      function Context_Window     return Natural is (P_Ctx_Win);
      function Turn_Input_Tokens  return Natural is (P_Turn_In);
      function Turn_Output_Tokens return Natural is (P_Turn_Out);
      function Turn_Count         return Natural is (P_Turn_Count);
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

      procedure Set_Text_Emitted (Value : Boolean) is
      begin
         P_Text_Emitted := Value;
      end Set_Text_Emitted;

      procedure Set_Has_Text_Delta (Value : Boolean) is
      begin
         P_Has_Text_Delta := Value;
      end Set_Has_Text_Delta;

      procedure Set_Pending_Stats (Value : Boolean) is
      begin
         P_Pending_Stats := Value;
      end Set_Pending_Stats;

      procedure Set_Context_Window (N : Natural) is
      begin
         P_Ctx_Win := N;
      end Set_Context_Window;

      procedure Set_Turn_Tokens (Input, Output : Natural) is
      begin
         P_Turn_In  := Input;
         P_Turn_Out := Output;
      end Set_Turn_Tokens;

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

   --  ── Small utilities ───────────────────────────────────────────────────

   --  Natural'Image without the leading space.
   function Natural_Image (N : Natural) return String is
      Image : constant String := Natural'Image (N);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Natural_Image;

   --  Format a token count compactly: 800 -> "800", 1500 -> "1.5k".
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

   --  Return just the stem of an agent path.
   --  E.g. "~/.../foo.agent.md" -> "foo"
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

   --  Return the first 16 hex characters of the SHA-256 digest of Tool_Id.
   --  Matches the token produced by the Python reference implementation:
   --    hashlib.sha256(tool_id.encode()).hexdigest()[:16]
   function Hash_Tool_Id (Tool_Id : String) return String is
   begin
      return GNAT.SHA256.Digest (Tool_Id) (1 .. 16);
   end Hash_Tool_Id;

   --  Scan Context (body bytes starting at rune Ctx_Start) for a
   --  llm-chat+.../tool/... token that contains rune position Anchor.
   --  Returns the token string, or "" if not found.
   --
   --  The token pattern is:
   --    llm-chat+ [0-9a-f-]+ /tool/ [0-9a-f]+
   --
   --  Positions in Context are mapped to rune offsets by adding Ctx_Start;
   --  this is an approximation when the body contains multi-byte UTF-8
   --  sequences, but is exact for the ASCII-only tokens we scan for.
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

   --  ── Scan_Fork_Token ───────────────────────────────────────────────────
   --
   --  Scan Context (body bytes starting at rune Ctx_Start) for a
   --  fork+PID/UUID/N token that contains rune position Anchor.
   --  Returns the token string, or "" if not found.
   --
   --  The token pattern is:
   --    fork+ [0-9]+ / [0-9a-f-]+ / [0-9]+
   --
   --  The same ASCII-only rune-offset approximation as Scan_Tool_Token.
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

   --  ── JSON helpers ──────────────────────────────────────────────────────

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

   --  Return a human-readable string for a scalar JSON value.
   --  Strings are returned as-is (no quotes); integers, booleans and
   --  floats are serialised via GNATCOLL.JSON.Write; compound or null
   --  values produce "...".
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

   --  ── Plumb message parsing ─────────────────────────────────────────────
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

   --  ── Pi event dispatcher ───────────────────────────────────────────────

   type Section_Kind is
     (No_Section, Thinking_Section, Text_Section, Tool_Section);

   --  Separator between turns.  Carries a clickable fork token so that
   --  button-3 on the separator line opens a forked session.
   --  Format:  fork+PID/UUID/N\n════...════\n\n
   function Format_Separator
     (Turn_N  : Positive;
      UUID    : String;
      PID     : String) return String
   is
   begin
      return ASCII.LF & ASCII.LF
             & "fork+" & PID & "/" & UUID & "/"
             & Natural_Image (Turn_N) & ASCII.LF
             & Str_Repeat (UC_DBL_H, 60)
             & ASCII.LF & ASCII.LF;
   end Format_Separator;

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

   procedure Dispatch_Pi_Event
     (Event   :     JSON_Value;
      Win     : in out Acme.Window.Win;
      FS      : not null access Nine_P.Client.Fs;
      State   : in out App_State;
      Section : in out Section_Kind;
      Proc    : in out Pi_RPC.Process)
   is
      Kind : constant String := Get_String (Event, "type");
   begin

      --  ── agent_start ───────────────────────────────────────────────────
      if Kind = "agent_start" then
         State.Set_Streaming (True);
         State.Set_Text_Emitted (False);
         State.Set_Has_Text_Delta (False);
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
         elsif not State.Text_Emitted then
            Acme.Window.Append
              (Win, FS,
               ASCII.LF
               & UC_WARN & " No response -- context may be full. Try New."
               & ASCII.LF);
         end if;
         --  Only emit the stats summary and turn separator when the
         --  agent produced an actual text response.  Tool-only intermediate
         --  turns are silently skipped.
         if State.Has_Text_Delta then
            State.Set_Pending_Stats (True);
            Pi_RPC.Send (Proc, "{""type"":""get_session_stats""}");
         end if;
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
                        declare
                           Text    : constant String :=
                             JSON_Scalar_Image (Value);
                           Trimmed : constant String :=
                             (if Text'Length > 200
                              then Text (Text'First
                                         .. Text'First + 196)
                                   & UC_ELLIP
                              else Text);
                        begin
                           Acme.Window.Append
                             (Win, FS,
                              ASCII.LF & UC_BOX_V
                              & " " & Name & ": " & Trimmed);
                        end;
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

      --  ── message_end (token counts) ────────────────────────────────────
      elsif Kind = "message_end" then
         declare
            Msg   : constant JSON_Value := Get_Object (Event, "message");
            Usage : constant JSON_Value := Get_Object (Msg, "usage");
         begin
            if Get_String (Msg, "role") = "assistant"
              and then Usage.Kind = JSON_Object_Type
            then
               declare
                  Input_Count : constant Natural :=
                    Get_Integer (Usage, "input")
                    + Get_Integer (Usage, "cacheRead")
                    + Get_Integer (Usage, "cacheWrite");
                  Output_Count : constant Natural :=
                    Get_Integer (Usage, "output");
               begin
                  if Input_Count > 0 or else Output_Count > 0 then
                     State.Set_Turn_Tokens (Input_Count, Output_Count);
                  end if;
               end;
            end if;
         end;

      --  ── auto_retry_start ──────────────────────────────────────────────
      --  Emitted by pi before each retry attempt.  Show a compact notice
      --  so the user can see why the turn is being retried and how long
      --  the backoff delay is.
      elsif Kind = "auto_retry_start" then
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
                  State.Reset_Turn_Count;
                  Pi_RPC.Send (Proc, "{""type"":""get_state""}");

               elsif Command = "get_session_stats" then
                  if State.Pending_Stats then
                     State.Set_Pending_Stats (False);
                     --  Append turn summary line.
                     declare
                        Input_Tokens  : constant Natural :=
                          State.Turn_Input_Tokens;
                        Output_Tokens : constant Natural :=
                          State.Turn_Output_Tokens;
                        Ctx_Window    : constant Natural :=
                          State.Context_Window;
                        Parts : Unbounded_String;
                     begin
                        if Input_Tokens > 0
                          and then Ctx_Window > 0
                        then
                           Append
                             (Parts,
                              "ctx "
                              & Format_Kilo (Input_Tokens)
                              & "/" & Format_Kilo (Ctx_Window)
                              & " ("
                              & Natural_Image
                                  (Input_Tokens * 100 / Ctx_Window)
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
                        declare
                           Model_Text : constant String :=
                             State.Current_Model;
                        begin
                           if Model_Text'Length > 0 then
                              if Length (Parts) > 0 then
                                 Append (Parts, " | ");
                              end if;
                              Append (Parts, Model_Text);
                           end if;
                        end;
                        if Length (Parts) > 0 then
                           Acme.Window.Append
                             (Win, FS,
                              ASCII.LF & "["
                              & To_String (Parts) & "]" & ASCII.LF);
                        end if;
                     end;
                     State.Increment_Turn_Count;
                     Acme.Window.Append
                       (Win, FS,
                        Format_Separator
                          (State.Turn_Count,
                           State.Session_Id,
                           Natural_Image (Natural (Getpid))));
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
               end if;
            end;
         end if;
      end if;
   end Dispatch_Pi_Event;

   --  ── Nth_Field ─────────────────────────────────────────────────────────
   --
   --  Return the N-th (1-based) whitespace-separated token from Text,
   --  or "" if there are fewer than N tokens.

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

   --  ── List_Models ───────────────────────────────────────────────────────
   --
   --  Run  pi --list-models  directly (no shell), parse its table and
   --  return one  model+PID/PROVIDER/ID  token per line.

   function List_Models return String is
      use GNATCOLL.OS.FS;
      use GNATCOLL.OS.Process;
      Pid_Prefix   : constant String := Natural_Image (Natural (Getpid)) & "/";
      Stdout_R, Stdout_W : File_Descriptor;
      Null_In      : constant File_Descriptor :=
        Open (Null_File, Read_Mode);
      Args         : Argument_List;
      Handle       : Process_Handle;
      Buffer       : Unbounded_String;
      Result       : Unbounded_String;
      Chunk        : String (1 .. 4096);
      Bytes_Read   : Integer;
   begin
      Open_Pipe (Stdout_R, Stdout_W);
      Args.Append (Pi_RPC.Find_Pi);
      Args.Append ("--list-models");
      Handle := Start (Args   => Args,
                       Stdin  => Null_In,
                       Stdout => Stdout_W,
                       Stderr => Stdout_W);
      Close (Null_In);
      Close (Stdout_W);
      loop
         Bytes_Read := Read (Stdout_R, Chunk);
         exit when Bytes_Read <= 0;
         Append (Buffer, Chunk (1 .. Bytes_Read));
      end loop;
      Close (Stdout_R);
      declare
         Dummy : constant Integer := Wait (Handle);
         pragma Unreferenced (Dummy);
      begin
         null;
      end;

      --  Parse: skip header (first line), then emit "model+F1/F2\n".
      declare
         Raw        : constant String := To_String (Buffer);
         Line_Start : Natural         := Raw'First;
         Line_Count : Natural         := 0;
      begin
         for I in Raw'Range loop
            if Raw (I) = ASCII.LF then
               if Line_Count > 0 then
                  declare
                     Line : constant String := Raw (Line_Start .. I - 1);
                     F1   : constant String := Nth_Field (Line, 1);
                     F2   : constant String := Nth_Field (Line, 2);
                  begin
                     if F1'Length > 0 and then F2'Length > 0 then
                        Append
                          (Result,
                           "model+" & Pid_Prefix
                           & F1 & "/" & F2 & ASCII.LF);
                     end if;
                  end;
               end if;
               Line_Start := I + 1;
               Line_Count := Line_Count + 1;
            end if;
         end loop;
         --  Last line if no trailing newline.
         if Line_Start <= Raw'Last and then Line_Count > 0 then
            declare
               Line : constant String := Raw (Line_Start .. Raw'Last);
               F1   : constant String := Nth_Field (Line, 1);
               F2   : constant String := Nth_Field (Line, 2);
            begin
               if F1'Length > 0 and then F2'Length > 0 then
                  Append
                    (Result,
                     "model+" & Pid_Prefix
                     & F1 & "/" & F2 & ASCII.LF);
               end if;
            end;
         end if;
      end;
      return To_String (Result);
   exception
      when others => return "";
   end List_Models;

   --  ── Parse_Session_Token ───────────────────────────────────────────────
   --
   --  Extract the session UUID from a plumb session token.
   --  Pid_Prefix must be "llm-chat+PID/" (e.g. "llm-chat+12345/").
   --
   --  Accepts:
   --    "llm-chat+PID/UUID"       → UUID  (PID-tagged for this instance)
   --    "llm-chat+UUID"           → UUID  (bare token, backward-compat)
   --  Rejects (returns ""):
   --    "llm-chat+OTHER_PID/UUID" → ""   (tagged for another instance)
   --    anything else             → ""

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

   --  ── List_Sessions_Text ────────────────────────────────────────────────
   --
   --  Call Session_Lister directly and return one PID-tagged token per line:
   --    llm-chat+PID/UUID<TAB>name<TAB>date<TAB>snippet
   --
   --  The PID prefix ensures that button-3 in the +sessions window routes
   --  the plumb message only to this pi-acme instance.

   function List_Sessions_Text return String is
      Pid_Prefix : constant String :=
        "llm-chat+" & Natural_Image (Natural (Getpid)) & "/";
      Sessions   : constant Session_Vectors.Vector :=
        List_Sessions (Ada.Directories.Current_Directory);
      Result     : Unbounded_String;
   begin
      Append
        (Result,
         "# Button-3 any llm-chat+ token to load that session."
         & ASCII.LF & ASCII.LF);
      for Session of Sessions loop
         Append
           (Result,
            Pid_Prefix & To_String (Session.UUID)
            & ASCII.HT & To_String (Session.Name)
            & ASCII.HT & To_String (Session.Date)
            & ASCII.HT & To_String (Session.Snippet)
            & ASCII.LF);
      end loop;
      return To_String (Result);
   end List_Sessions_Text;

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
               Line  : constant String      := Ada.Text_IO.Get_Line (File);
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
               Line  : constant String      := Ada.Text_IO.Get_Line (File);
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
                              --  its fork separator before this user msg.
                              if In_Turn and then Saw_Asst_Text then
                                 Turns_Rendered := Turns_Rendered + 1;
                                 Append
                                   (Buf,
                                    Format_Separator
                                      (Turns_Rendered, UUID, PID_Str));
                              end if;
                              In_Turn       := True;
                              Saw_Asst_Text := False;
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

      --  Append separator for the final rendered turn (if any), then flush.
      if In_Turn and then Saw_Asst_Text then
         Turns_Rendered := Turns_Rendered + 1;
         Append
           (Buf,
            Format_Separator (Turns_Rendered, UUID, PID_Str));
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

   --  ── Run ───────────────────────────────────────────────────────────────

   procedure Run (Opts : Options) is

      Cwd       : constant String := Ada.Strings.Fixed.Trim
        (Ada.Command_Line.Command_Name, Ada.Strings.Both);  --  placeholder
      Tag_Extra : constant String :=
        " | Send Stop Steer New Compact Clear Models Sessions Thinking Stats";

      --  Process ID used to build window-specific selector tokens.
      My_PID : constant String := Natural_Image (Natural (Getpid));

      --  Shared objects — all tasks close over these:
      Win_FS : aliased Nine_P.Client.Fs  := Ns_Mount ("acme");
      Win    : Acme.Window.Win := Acme.Window.New_Win (Win_FS'Access);
      Proc   : Pi_RPC.Process  := Pi_RPC.Start
        (Session_Id    => To_String (Opts.Session_Id),
         Model         => To_String (Opts.Model),
         System_Prompt => To_String (Opts.Agent),
         No_Tools      => Opts.No_Tools);
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
         My_FS      : aliased Nine_P.Client.Fs := Ns_Mount ("acme");
         Section    : Section_Kind             := No_Section;
         First_Boot : Boolean                  := True;
      begin
         Restart_Loop : loop
            --  Bootstrap: always send get_state; send set_model only on
            --  the first start (on session reload the model comes from the
            --  session itself via the get_state / model_select response).
            Pi_RPC.Send (Proc, "{""type"":""get_state""}");
            if First_Boot then
               First_Boot := False;
               if To_String (Opts.Model) /= "" then
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
            end if;
            --  Main read loop: dispatch pi JSON events until EOF.
            Read_Loop : loop
               declare
                  Line : constant String := Pi_RPC.Read_Line (Proc);
               begin
                  exit Read_Loop when Line'Length = 0;
                  declare
                     Parse_Result : constant Read_Result := Read (Line);
                  begin
                     if Parse_Result.Success then
                        Dispatch_Pi_Event
                          (Parse_Result.Value,
                           Win, My_FS'Access, State, Section, Proc);
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
            --  EOF: check for a pending session reload.
            declare
               UUID          : Unbounded_String;
               Was_Requested : Boolean;
            begin
               State.Consume_Reload (UUID, Was_Requested);
               if Was_Requested then
                  declare
                     UUID_Str : constant String := To_String (UUID);
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
                     Pi_RPC.Restart (Proc, UUID_Str);
                  end;
                  Section := No_Section;
                  State.Signal_Restart_Done;
                  --  Continue Restart_Loop: bootstrap and read the new pi.
               else
                  --  Normal shutdown or unexpected EOF — unblock
                  --  Pi_Stderr_Task.
                  State.Signal_Restart_Aborted;
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
         Parser  : Acme.Raw_Events.Event_Parser;

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
            Context   : constant String  :=
              Acme.Window.Read_Chars
                (Win, My_FS'Access, Ctx_Start, Ctx_End);
            Token     : constant String  :=
              Scan_Tool_Token (Context, Ctx_Start, Anchor);
         begin
            if Token'Length = 0 then
               return False;
            end if;
            Run_Llm_Chat_Open (Token);
            return True;
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
            Context   : constant String  :=
              Acme.Window.Read_Chars
                (Win, My_FS'Access, Ctx_Start, Ctx_End);
            Token     : constant String  :=
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
         exception
            when others =>
               return False;
         end Try_Fork_URI;

      begin
         loop
            declare
               Data : constant Byte_Array :=
                 Read_Once (Ev_File'Access);
            begin
               exit when Data'Length = 0;
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
                                 if Sel'Length > 0
                                   and then not State.Is_Streaming
                                 then
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
                              --  streaming or a compaction is already running.
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
                              declare
                                 Parent  : constant String :=
                                   Ada.Directories.Current_Directory
                                   & "/+pi";
                                 Content : constant String :=
                                   List_Models;
                              begin
                                 Open_Sub_Window
                                   (My_FS'Access, Parent, "+models",
                                    (if Content'Length > 0
                                     then Content
                                     else "(no models found)" & ASCII.LF));
                              end;
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
                                 Parent        : constant String :=
                                   Ada.Directories.Current_Directory
                                   & "/+pi";
                                 Input_Tokens  : constant Natural :=
                                   State.Turn_Input_Tokens;
                                 Output_Tokens : constant Natural :=
                                   State.Turn_Output_Tokens;
                                 Ctx_Window    : constant Natural :=
                                   State.Context_Window;
                                 Stats_Buffer  : Unbounded_String;
                              begin
                                 Append
                                   (Stats_Buffer,
                                    "Session:  " & State.Session_Id
                                    & ASCII.LF);
                                 Append
                                   (Stats_Buffer,
                                    "Model:    " & State.Current_Model
                                    & ASCII.LF);
                                 Append
                                   (Stats_Buffer,
                                    "Thinking: "
                                    & State.Current_Thinking
                                    & ASCII.LF & ASCII.LF);
                                 Append
                                   (Stats_Buffer, "Last turn:" & ASCII.LF);
                                 if Input_Tokens > 0 then
                                    Append
                                      (Stats_Buffer,
                                       "  Input:   "
                                       & Natural_Image (Input_Tokens)
                                       & ASCII.LF);
                                 end if;
                                 if Output_Tokens > 0 then
                                    Append
                                      (Stats_Buffer,
                                       "  Output:  "
                                       & Natural_Image (Output_Tokens)
                                       & ASCII.LF);
                                 end if;
                                 if Input_Tokens > 0
                                   and then Ctx_Window > 0
                                 then
                                    Append
                                      (Stats_Buffer,
                                       "  Context: "
                                       & Natural_Image (Input_Tokens)
                                       & "/" & Natural_Image (Ctx_Window)
                                       & " ("
                                       & Natural_Image
                                           (Input_Tokens * 100
                                            / Ctx_Window)
                                       & "%)" & ASCII.LF);
                                 end if;
                                 Open_Sub_Window
                                   (My_FS'Access, Parent, "+stats",
                                    To_String (Stats_Buffer));
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
         end loop;
         State.Signal_Shutdown;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Acme_Event_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
            State.Signal_Shutdown;
      end Acme_Event_Task;

      --  ── Plumb_Model_Task ──────────────────────────────────────────────

      task body Plumb_Model_Task is
         Pl_FS  : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         My_FS  : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         Port   : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-model", O_READ);
      begin
         loop
            declare
               Raw  : constant Byte_Array :=
                 Nine_P.Client.Read_Once (Port'Access);
               Data : constant String := Extract_Plumb_Data (Raw);
            begin
               exit when Raw'Length = 0;
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
                                   Rest (Rest'First .. Second_Slash - 1);
                                 Model_Id : constant String :=
                                   Rest (Second_Slash + 1 .. Rest'Last);
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
                                    ASCII.LF & "[Model -> " & Rest & "]"
                                    & ASCII.LF);
                              end;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
         end loop;
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
         Pl_FS      : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         Pid_Prefix : constant String             :=
           "llm-chat+" & My_PID & "/";
         Port       : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-session", O_READ);
      begin
         loop
            declare
               Raw  : constant Byte_Array :=
                 Nine_P.Client.Read_Once (Port'Access);
               Data : constant String := Extract_Plumb_Data (Raw);
            begin
               exit when Raw'Length = 0;
               if Data'Length > 0 then
                  declare
                     UUID : constant String :=
                       Parse_Session_Token (Data, Pid_Prefix);
                  begin
                     if UUID'Length > 0 then
                        --  Signal reload and terminate pi; Pi_Stdout_Task
                        --  will call Pi_RPC.Restart once it gets EOF.
                        State.Request_Reload (UUID);
                        Pi_RPC.Terminate_Process (Proc);
                     end if;
                  end;
               end if;
            end;
         end loop;
      exception
         when Ex : others =>
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Plumb_Session_Task terminated: "
               & Ada.Exceptions.Exception_Information (Ex));
      end Plumb_Session_Task;

      --  ── Plumb_Thinking_Task ───────────────────────────────────────────

      task body Plumb_Thinking_Task is
         Pl_FS : aliased Nine_P.Client.Fs   := Ns_Mount ("plumb");
         My_FS : aliased Nine_P.Client.Fs   := Ns_Mount ("acme");
         Port  : aliased Nine_P.Client.File :=
           Open (Pl_FS'Access, "/pi-thinking", O_READ);
      begin
         loop
            declare
               Raw   : constant Byte_Array :=
                 Nine_P.Client.Read_Once (Port'Access);
               Level : constant String := Extract_Plumb_Data (Raw);
            begin
               exit when Raw'Length = 0;
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
         end loop;
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
         Ada.Directories.Current_Directory & "/+pi");
      Acme.Window.Append
        (Win, Win_FS'Access, UC_BULLET & " starting..." & ASCII.LF);
      Acme.Window.Ctl (Win, Win_FS'Access, "clean");

      --  ── Wait for window-closed shutdown ───────────────────────────────
      State.Wait_Shutdown;
   end Run;

end Pi_Acme_App;
