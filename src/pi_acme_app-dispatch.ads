--  Pi_Acme_App.Dispatch — live pi event dispatch and window rendering.
--
--  Dispatch_Pi_Event maps incoming pi JSON events to acme window mutations.
--  Format_Status builds the one-line status string shown in line 1 of the
--  window body.  Append_Live_Turn_Footer appends the end-of-turn footer.
--  Open_Sub_Window creates a named child acme window.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Acme.Window;
with GNATCOLL.JSON;
with Nine_P.Client;
with Pi_RPC;

package Pi_Acme_App.Dispatch is

   --  Build the one-line status string placed in the first body line.
   function Format_Status
     (State : App_State;
      Extra : String := "ready") return String;

   --  Append the live end-of-turn footer to Win using the current values in
   --  State, and increment State.Turn_Count.
   procedure Append_Live_Turn_Footer
     (Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State;
      PID   : String);

   --  Create a new acme window named Parent/Sub, write Content, mark clean.
   procedure Open_Sub_Window
     (FS      : not null access Nine_P.Client.Fs;
      Parent  : String;
      Sub     : String;
      Content : String);

   --  Dispatch one pi JSON event to the appropriate window mutation.
   --  Section tracks the current streaming content kind and is updated
   --  in place.  PID is this process's PID as a decimal string.
   procedure Dispatch_Pi_Event
     (Event   :        GNATCOLL.JSON.JSON_Value;
      Win     : in out Acme.Window.Win;
      FS      : not null access Nine_P.Client.Fs;
      State   : in out App_State;
      Section : in out Section_Kind;
      Proc    : in out Pi_RPC.Process;
      PID     :        String);

end Pi_Acme_App.Dispatch;
