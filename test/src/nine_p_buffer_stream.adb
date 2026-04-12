with Nine_P; use Nine_P;

package body Nine_P_Buffer_Stream is

   use Ada.Streams;

   overriding procedure Read
     (S    : in out Buffer_Stream;
      Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset)
   is
      Avail   : constant Natural :=
        Natural (S.Data.Length) - S.Read_Pos;
      To_Read : Natural := Item'Length;
   begin
      if Avail = 0 then
         Last := Item'First - 1;   --  EOF
         return;
      end if;
      if To_Read > Avail then
         To_Read := Avail;
      end if;
      for I in 0 .. To_Read - 1 loop
         Item (Item'First + Stream_Element_Offset (I)) :=
           Stream_Element (S.Data.Element (S.Read_Pos + I));
      end loop;
      S.Read_Pos := S.Read_Pos + To_Read;
      Last := Item'First + Stream_Element_Offset (To_Read) - 1;
   end Read;

   overriding procedure Write
     (S    : in out Buffer_Stream;
      Item : Stream_Element_Array)
   is
   begin
      for E of Item loop
         S.Data.Append (Uint8 (E));
      end loop;
   end Write;

   function Available (S : Buffer_Stream) return Stream_Element_Offset is
   begin
      return Stream_Element_Offset
        (Natural (S.Data.Length) - S.Read_Pos);
   end Available;

end Nine_P_Buffer_Stream;
