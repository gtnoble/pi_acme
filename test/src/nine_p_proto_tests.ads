with AUnit;
with AUnit.Test_Fixtures;

package Nine_P_Proto_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Primitive type round-trips
   procedure Test_Qid_Round_Trip          (T : in out Test);
   procedure Test_Stat_Round_Trip         (T : in out Test);

   --  Message round-trips
   procedure Test_Tversion_Round_Trip     (T : in out Test);
   procedure Test_Rversion_Round_Trip     (T : in out Test);
   procedure Test_Tattach_Round_Trip      (T : in out Test);
   procedure Test_Rattach_Round_Trip      (T : in out Test);
   procedure Test_Rerror_Round_Trip       (T : in out Test);
   procedure Test_Twalk_Round_Trip        (T : in out Test);
   procedure Test_Rwalk_Round_Trip        (T : in out Test);
   procedure Test_Topen_Round_Trip        (T : in out Test);
   procedure Test_Ropen_Round_Trip        (T : in out Test);
   procedure Test_Tread_Round_Trip        (T : in out Test);
   procedure Test_Rread_Round_Trip        (T : in out Test);
   procedure Test_Twrite_Round_Trip       (T : in out Test);
   procedure Test_Rwrite_Round_Trip       (T : in out Test);
   procedure Test_Tclunk_Round_Trip       (T : in out Test);
   procedure Test_Stat_Message_Round_Trip (T : in out Test);

   --  Wire format correctness
   procedure Test_Message_Size   (T : in out Test);
   procedure Test_Little_Endian  (T : in out Test);
   procedure Test_String_Encoding (T : in out Test);

end Nine_P_Proto_Tests;
