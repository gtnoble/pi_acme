--  Acme.Window — operations on a single acme window via the 9P VFS.
--
--  Win is a LIMITED type holding only a window ID and an Addr_Mutex.
--  Every operation that touches the VFS takes an Fs parameter explicitly,
--  so each calling task can supply its own Nine_P.Client.Fs connection.
--  This is the correct multi-task design: the mutex serialises the
--  addr->data write pair; the Fs connections are task-local.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Nine_P.Client;

package Acme.Window is

   type Win is limited private;

   --  Create a new acme window by opening /new/ctl and reading the ID.
   function New_Win
     (FS : not null access Nine_P.Client.Fs) return Win;

   --  Write a ctl command (newline appended automatically).
   procedure Ctl
     (W   : in out Win;
      FS  : not null access Nine_P.Client.Fs;
      Cmd : String);

   --  Set the window name.
   procedure Set_Name
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Name : String);

   --  Append text to the tag line (writes directly to the tag file,
   --  not the ctl file — "tag" is not a valid ctl command).
   procedure Append_Tag
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String);

   --  Append text to the body (atomic addr=$ then data write).
   procedure Append
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String);

   --  Replace the first line of the body.
   procedure Replace_Line1
     (W    : in out Win;
      FS   : not null access Nine_P.Client.Fs;
      Text : String);

   --  Read the entire body text.
   function Read_Body
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs) return String;

   --  Read the currently selected text via the rdsel pseudo-file.
   function Selection_Text
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs) return String;

   --  Read the character range [Q0, Q1) via addr/xdata.
   function Read_Chars
     (W      : in out Win;
      FS     : not null access Nine_P.Client.Fs;
      Q0, Q1 : Natural) return String;

   --  Write an event back to acme (pass-through).
   procedure Send_Event
     (W      : in out Win;
      FS     : not null access Nine_P.Client.Fs;
      C1, C2 : Character;
      Q0, Q1 : Natural);

   --  Path of this window's event file (e.g. "/42/event").
   --  Pure — no Fs needed.
   function Event_Path (W : Win) return String;

   --  Scroll the window to the top.
   procedure Scroll_Top
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs);

   --  Delete the window.
   procedure Delete
     (W  : in out Win;
      FS : not null access Nine_P.Client.Fs);

   --  The numeric window ID.
   function Id (W : Win) return Window_Id;

private

   protected type Addr_Mutex is
      entry Acquire;
      procedure Release;
   private
      Locked : Boolean := False;
   end Addr_Mutex;

   type Win is tagged limited record
      Win_Id : Window_Id := 1;
      Mutex  : Addr_Mutex;
   end record;

end Acme.Window;
