--  Acme.Window body.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Exceptions;
with Ada.Text_IO;

package body Acme.Window is

   use Nine_P;
   use Nine_P.Client;

   --  ── Protected mutex body ─────────────────────────────────────────────

   protected body Addr_Mutex is
      entry Acquire when not Locked is
      begin
         Locked := True;
      end Acquire;

      procedure Release is
      begin
         Locked := False;
      end Release;
   end Addr_Mutex;

   --  ── Helpers ──────────────────────────────────────────────────────────

   function Bytes_To_String (Data : Byte_Array) return String is
      Result : String (1 .. Data'Length);
   begin
      for I in Data'Range loop
         Result (I - Data'First + 1) := Character'Val (Data (I));
      end loop;
      return Result;
   end Bytes_To_String;

   function First_Token (Text : String) return String is
      Start : Natural := Text'First;
   begin
      while Start <= Text'Last
        and then Text (Start) in ' ' | ASCII.LF | ASCII.CR | ASCII.HT
      loop
         Start := Start + 1;
      end loop;
      declare
         Stop : Natural := Start;
      begin
         while Stop <= Text'Last
           and then Text (Stop)
                      not in ' ' | ASCII.LF | ASCII.CR | ASCII.HT
         loop
            Stop := Stop + 1;
         end loop;
         return Text (Start .. Stop - 1);
      end;
   end First_Token;

   --  Open a window file, write Data, close (finalization clunks the fid).
   procedure Write_Win_File
     (FS      : not null access Nine_P.Client.Fs;
      Win_Id  : Window_Id;
      File    : String;
      Data    : String)
   is
      F     : aliased Nine_P.Client.File :=
        Open (FS, Win_File_Path (Win_Id, File), O_WRITE);
      Dummy : constant Natural := Write (F'Access, Data);
      pragma Unreferenced (Dummy);
   begin
      null;
   end Write_Win_File;

   --  Open a window file, read all content, close.
   function Read_Win_File
     (FS     : not null access Nine_P.Client.Fs;
      Win_Id : Window_Id;
      File   : String) return String
   is
      F    : aliased Nine_P.Client.File :=
        Open (FS, Win_File_Path (Win_Id, File), O_READ);
      Data : constant Byte_Array := Read (F'Access);
   begin
      return Bytes_To_String (Data);
   end Read_Win_File;

   --  Acquire mutex, write addr then data, release.
   procedure Atomic_Write
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Addr : String;
      Data : String)
   is
   begin
      W.Mutex.Acquire;
      begin
         Write_Win_File (FS, W.Win_Id, "addr", Addr);
         Write_Win_File (FS, W.Win_Id, "data", Data);
      exception
         when Ex : others =>
            W.Mutex.Release;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Atomic_Write failed: "
               & Ada.Exceptions.Exception_Information (Ex));
            raise;
      end;
      W.Mutex.Release;
   end Atomic_Write;

   --  ── New_Win ──────────────────────────────────────────────────────────

   function New_Win (FS : not null access Nine_P.Client.Fs) return Win is
   begin
      return Result : Win do
         declare
            F   : aliased Nine_P.Client.File :=
              Open (FS, "/new/ctl", O_READ);
            Ctl : constant String :=
              Bytes_To_String (Read (F'Access));
         begin
            Result.Win_Id := Window_Id'Value (First_Token (Ctl));
         end;
      end return;
   end New_Win;

   --  ── Public operations ────────────────────────────────────────────────

   procedure Ctl
     (W   : in out Win;
      FS  : not null access Nine_P.Client.Fs;
      Cmd : String)
   is
   begin
      Write_Win_File (FS, W.Win_Id, "ctl", Cmd & ASCII.LF);
   end Ctl;

   procedure Set_Name
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Name : String)
   is
   begin
      Ctl (W, FS, "name " & Name);
   end Set_Name;

   procedure Append_Tag
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String)
   is
   begin
      Write_Win_File (FS, W.Win_Id, "tag", Text);
   end Append_Tag;

   procedure Append
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String)
   is
   begin
      Atomic_Write (W, FS, "$", Text);
   end Append;

   procedure Replace_Match
     (W           : in out Win;
      FS          : not null access Nine_P.Client.Fs;
      Pattern     : String;
      Replacement : String)
   is
   begin
      W.Mutex.Acquire;
      begin
         Write_Win_File (FS, W.Win_Id, "addr", Pattern);
         Write_Win_File (FS, W.Win_Id, "data", Replacement);
      exception
         when others =>
            --  Pattern did not match or addr write failed; ignore silently.
            W.Mutex.Release;
            return;
      end;
      W.Mutex.Release;
   end Replace_Match;

   procedure Replace_Line1
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String)
   is
   begin
      Atomic_Write (W, FS, "1", Text & ASCII.LF);
   end Replace_Line1;

   function Read_Body
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs) return String
   is
   begin
      return Read_Win_File (FS, W.Win_Id, "body");
   end Read_Body;

   function Selection_Text
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs) return String
   is
   begin
      return Read_Win_File (FS, W.Win_Id, "rdsel");
   end Selection_Text;

   function Read_Chars
     (W      : in out Win;
      FS     : not null access Nine_P.Client.Fs;
      Q0, Q1 : Natural) return String
   is
      Q0_Image : constant String := Natural'Image (Q0);
      Q1_Image : constant String := Natural'Image (Q1);
      Addr     : constant String :=
        "#" & Q0_Image (Q0_Image'First + 1 .. Q0_Image'Last)
        & ",#" & Q1_Image (Q1_Image'First + 1 .. Q1_Image'Last);
   begin
      W.Mutex.Acquire;
      begin
         Write_Win_File (FS, W.Win_Id, "addr", Addr);
         declare
            Result : constant String :=
              Read_Win_File (FS, W.Win_Id, "xdata");
         begin
            W.Mutex.Release;
            return Result;
         end;
      exception
         when Ex : others =>
            W.Mutex.Release;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Read_Chars failed: "
               & Ada.Exceptions.Exception_Information (Ex));
            raise;
      end;
   end Read_Chars;

   procedure Send_Event
     (W      : in out Win;
      FS     : not null access Nine_P.Client.Fs;
      C1, C2 : Character;
      Q0, Q1 : Natural)
   is
      Q0_Image : constant String := Natural'Image (Q0);
      Q1_Image : constant String := Natural'Image (Q1);
      Msg      : constant String :=
        C1 & C2
        & Q0_Image (Q0_Image'First + 1 .. Q0_Image'Last)
        & " "
        & Q1_Image (Q1_Image'First + 1 .. Q1_Image'Last)
        & ASCII.LF;
   begin
      Write_Win_File (FS, W.Win_Id, "event", Msg);
   end Send_Event;

   function Event_Path (W : Win) return String is
   begin
      return Win_File_Path (W.Win_Id, "event");
   end Event_Path;

   procedure Scroll_Top
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs)
   is
   begin
      W.Mutex.Acquire;
      begin
         Write_Win_File (FS, W.Win_Id, "addr", "#0");
         Write_Win_File (FS, W.Win_Id, "ctl", "dot=addr" & ASCII.LF);
         Write_Win_File (FS, W.Win_Id, "ctl", "show" & ASCII.LF);
      exception
         when Ex : others =>
            W.Mutex.Release;
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "Scroll_Top failed: "
               & Ada.Exceptions.Exception_Information (Ex));
            raise;
      end;
      W.Mutex.Release;
   end Scroll_Top;

   procedure Delete
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs)
   is
   begin
      Ctl (W, FS, "delete");
   end Delete;

   function Id (W : Win) return Window_Id is
   begin
      return W.Win_Id;
   end Id;

end Acme.Window;
