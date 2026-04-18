--  Session_Lister — list pi agent sessions for a working directory.
--
--  Reads JSONL files from ~/.pi/agent/sessions/<encoded-cwd>/
--  and extracts session metadata (UUID, name, date, first-message snippet).
--
--  Project: pi_acme
--  For revision history, see the project version-control log.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Session_Lister is

   SNIPPET_MAX : constant := 60;   --  max runes in the snippet

   type Session_Info is record
      UUID    : Ada.Strings.Unbounded.Unbounded_String;
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Date    : Ada.Strings.Unbounded.Unbounded_String;
      Snippet : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Session_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Natural,
      Element_Type => Session_Info);

   --  Encode a working-directory path as a session-directory slug.
   --  "/home/user/proj"  ->  "--home-user-proj--"
   function Encode_Cwd (Cwd : String) return String;

   --  Full path to the session directory for the given Cwd.
   --  Uses $HOME/.pi/agent/sessions/<Encode_Cwd(Cwd)>.
   function Sessions_Dir (Cwd : String) return String;

   --  Format an ISO-8601 timestamp into "YYYY-MM-DD HH:MM".
   --  Falls back to the raw string if it is too short.
   function Format_Timestamp (Ts : String) return String;

   --  Parse one JSONL session file.
   --  Returns a Session_Info with UUID = "" if parsing fails.
   function Parse_Session_File (Path : String) return Session_Info;

   --  Return all valid sessions for Cwd, newest first.
   function List_Sessions
     (Cwd : String) return Session_Vectors.Vector;

   --  Search every subdirectory of ~/.pi/agent/sessions/ for a JSONL file
   --  whose filename contains UUID.  Returns the full filesystem path, or ""
   --  if no matching file is found.  Unlike Sessions_Dir / List_Sessions,
   --  this is not restricted to the current working directory, so it can
   --  locate sessions created in other directories.
   function Find_Session_File (UUID : String) return String;

   --  Create a new session JSONL file containing the conversation history
   --  from Source_UUID up to and including After_Turn complete turns.
   --
   --  A "complete turn" is one user message plus all subsequent assistant
   --  and tool-result messages up to (but not including) the next user
   --  message.  After_Turn = 1 forks after the first round-trip.
   --
   --  The new file is written to Sessions_Dir(Target_Cwd) and is named
   --  <new-uuid>.jsonl.  Its header line carries the new UUID and the
   --  current timestamp; a session_info line names it
   --  "Fork of <original-name> @<After_Turn>".
   --
   --  Returns the new UUID on success, "" on any error (source not found,
   --  After_Turn exceeds the number of complete turns in the source, I/O
   --  failure, etc.).
   function Fork_Session
     (Source_UUID : String;
      After_Turn  : Positive;
      Target_Cwd  : String) return String;

end Session_Lister;
