with AUnit;
with AUnit.Test_Fixtures;

--  Integration tests for the pi_acme --one-shot (subagent) mode.
--
--  Each test spawns bin/pi_acme with --one-shot and verifies the JSON
--  result line written to stdout.  Tests are silently skipped when acme
--  is not running; they require a live acme 9P server and a configured
--  pi installation with the github-copilot/gpt-5-mini model.

package Subagent_Integration_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Happy-path: one-shot prints a JSON line whose "output" field
   --  contains the expected word "PONG" and whose "session_id" is a
   --  well-formed 36-character UUID.
   procedure Test_One_Shot_Returns_Json
     (T : in out Test);

   --  --one-shot implies --no-session: each invocation opens a fresh pi
   --  session, so two consecutive runs must return distinct session IDs.
   procedure Test_One_Shot_Fresh_Session_Each_Run
     (T : in out Test);

end Subagent_Integration_Tests;
