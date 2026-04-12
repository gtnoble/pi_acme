--  Nine_P_Buffer_Stream — in-memory Ada.Streams backend for testing.
--
--  Backed by a Nine_P.Byte_Vectors.Vector: grows automatically, no fixed
--  capacity.  Write bytes in, read them back out in FIFO order.

with Ada.Streams;
with Nine_P;

package Nine_P_Buffer_Stream is

   use Ada.Streams;

   type Buffer_Stream is new Ada.Streams.Root_Stream_Type with private;

   overriding procedure Read
     (S    : in out Buffer_Stream;
      Item : out Stream_Element_Array;
      Last : out Stream_Element_Offset);

   overriding procedure Write
     (S    : in out Buffer_Stream;
      Item : Stream_Element_Array);

   --  Number of bytes currently available to read.
   function Available (S : Buffer_Stream) return Stream_Element_Offset;

private

   type Buffer_Stream is new Ada.Streams.Root_Stream_Type with record
      Data     : Nine_P.Byte_Vectors.Vector;
      Read_Pos : Natural := 0;
   end record;

end Nine_P_Buffer_Stream;
