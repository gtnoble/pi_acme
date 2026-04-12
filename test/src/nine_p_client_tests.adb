with AUnit.Assertions;
with Ada.Environment_Variables;
with Ada.Streams;                use Ada.Streams;
with Ada.Strings.Unbounded;      use Ada.Strings.Unbounded;
with Interfaces;                 use Interfaces;
with Nine_P;                     use Nine_P;
with Nine_P.Client;
with Nine_P.Proto;               use Nine_P.Proto;
with Nine_P_Buffer_Stream;       use Nine_P_Buffer_Stream;

package body Nine_P_Client_Tests is

   use AUnit.Assertions;

   --  Save, set, and restore a single environment variable around a block.
   procedure With_Env (Name : String; Val : String;
                       Action : not null access procedure)
   is
      use Ada.Environment_Variables;
      Had_Old : constant Boolean := Exists (Name);
      Old     : constant String  := (if Had_Old then Value (Name) else "");
   begin
      Set (Name, Val);
      begin
         Action.all;
      exception
         when others =>
            if Had_Old then
               Set (Name, Old);
            else
               Clear (Name);
            end if;
            raise;
      end;
      if Had_Old then
         Set (Name, Old);
      else
         Clear (Name);
      end if;
   end With_Env;

   --  ── Namespace ────────────────────────────────────────────────────────

   procedure Test_Namespace_Uses_Env (T : in out Test) is
      pragma Unreferenced (T);
      use Ada.Environment_Variables;
      procedure Check is
      begin
         Assert (Nine_P.Client.Namespace = "/tmp/test.ns",
                 "Should return $NAMESPACE verbatim");
      end Check;
   begin
      With_Env ("NAMESPACE", "/tmp/test.ns", Check'Access);
   end Test_Namespace_Uses_Env;

   procedure Test_Namespace_Fallback (T : in out Test) is
      pragma Unreferenced (T);
      use Ada.Environment_Variables;
      NS_Saved  : constant Boolean := Exists ("NAMESPACE");
      NS_Old    : constant String  :=
        (if NS_Saved
         then Value ("NAMESPACE")
         else "");
      Verified  : Boolean := False;

      procedure Set_User is
         procedure Set_Display is
            procedure Check is
            begin
               Assert (Nine_P.Client.Namespace = "/tmp/ns.tuser.:99",
                       "Fallback should be /tmp/ns.<USER>.<DISPLAY>");
               Verified := True;
            end Check;
         begin
            With_Env ("DISPLAY", ":99", Check'Access);
         end Set_Display;
      begin
         With_Env ("USER", "tuser", Set_Display'Access);
      end Set_User;
   begin
      --  Clear NAMESPACE so the fallback path is taken
      Clear ("NAMESPACE");
      begin
         Set_User;
      exception
         when others =>
            if NS_Saved then
               Set ("NAMESPACE", NS_Old);
            end if;
            raise;
      end;
      if NS_Saved then
         Set ("NAMESPACE", NS_Old);
      end if;
      Assert (Verified, "Test body did not execute");
   end Test_Namespace_Fallback;

   --  ── Read_Message / Write_Message ─────────────────────────────────────

   procedure Test_Read_Write_Message (T : in out Test) is
      pragma Unreferenced (T);
      BS     : aliased Buffer_Stream;
      Orig   : constant Message :=
        (Kind  => Kind_Rerror,
         Tag   => 42,
         Ename => To_Unbounded_String ("something went wrong"));
      Packed : constant Byte_Array := Pack (Orig);
   begin
      Nine_P.Client.Write_Message (BS'Access, Packed);
      declare
         Got : constant Byte_Array :=
           Nine_P.Client.Read_Message (BS'Access);
      begin
         Assert (Got'Length = Packed'Length,
                 "Round-trip length should match");
         for I in 0 .. Packed'Length - 1 loop
            Assert (Got (I) = Packed (I),
                    "Byte mismatch at index" & I'Image);
         end loop;
         Assert (Available (BS) = 0, "Buffer should be fully consumed");
      end;
   end Test_Read_Write_Message;

   procedure Test_Read_Message_Framing (T : in out Test) is
      pragma Unreferenced (T);
      BS   : aliased Buffer_Stream;
      Msg1 : constant Message := (Kind => Kind_Rflush, Tag => 10);
      Msg2 : constant Message := (Kind => Kind_Rclunk, Tag => 20);
   begin
      Nine_P.Client.Write_Message (BS'Access, Pack (Msg1));
      Nine_P.Client.Write_Message (BS'Access, Pack (Msg2));
      Assert (Available (BS) = 14,
              "Two 7-byte messages should occupy 14 bytes");
      declare
         Got1 : constant Message :=
           Unpack (Nine_P.Client.Read_Message (BS'Access));
         Got2 : constant Message :=
           Unpack (Nine_P.Client.Read_Message (BS'Access));
      begin
         Assert (Got1.Kind = Kind_Rflush, "First message should be Rflush");
         Assert (Got1.Tag  = 10,          "First message tag should be 10");
         Assert (Got2.Kind = Kind_Rclunk, "Second message should be Rclunk");
         Assert (Got2.Tag  = 20,          "Second message tag should be 20");
         Assert (Available (BS) = 0,
                 "Buffer should be empty after two reads");
      end;
   end Test_Read_Message_Framing;

end Nine_P_Client_Tests;
