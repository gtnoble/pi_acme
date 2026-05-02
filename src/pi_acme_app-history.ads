--  Pi_Acme_App.History — session JSONL file replay into an acme window.
--
--  Render_Session_History reads a saved pi session file and replays
--  its full conversation history into Win.  See the body for the
--  two-pass rendering algorithm.
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Acme.Window;
with Nine_P.Client;

package Pi_Acme_App.History is

   --  Read the JSONL session file for UUID and replay the full conversation
   --  history into Win.  Searches all session directories.
   --  Restores State.Turn_Tokens from the last assistant usage block.
   --  Appends a turn footer when rendering completes.
   --  Writes an error message to Win if the session file cannot be located.
   procedure Render_Session_History
     (UUID  : String;
      Win   : in out Acme.Window.Win;
      FS    : not null access Nine_P.Client.Fs;
      State : in out App_State);

end Pi_Acme_App.History;
