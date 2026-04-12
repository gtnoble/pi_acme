with AUnit.Run;
with AUnit.Reporter.Text;
with Test_Suites;

procedure Pi_Acme_Test is
   procedure Runner is new AUnit.Run.Test_Runner (Test_Suites.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   Runner (Reporter);
end Pi_Acme_Test;
