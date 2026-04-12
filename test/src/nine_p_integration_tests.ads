with AUnit;
with AUnit.Test_Fixtures;

--  Integration tests against the live plan9port acme and plumb servers.
--  All tests skip gracefully when acme is not running.

package Nine_P_Integration_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Nine_P.Client against live acme
   procedure Test_Ns_Mount_Acme       (T : in out Test);
   procedure Test_Read_Acme_Index     (T : in out Test);
   procedure Test_Open_New_Ctl        (T : in out Test);
   procedure Test_Client_Matches_9p   (T : in out Test);

end Nine_P_Integration_Tests;
