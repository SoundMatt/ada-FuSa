with Interfaces; use Interfaces;

package body Fusa.Crc32 is

   function Compute (Data : String) return Unsigned_32 is
      Crc : Unsigned_32 := 16#FFFF_FFFF#;
   begin
      for I in Data'Range loop
         Crc := Crc xor Unsigned_32 (Character'Pos (Data (I)));
         for J in 1 .. 8 loop
            if (Crc and 1) /= 0 then
               Crc := Shift_Right (Crc, 1) xor 16#EDB8_8320#;
            else
               Crc := Shift_Right (Crc, 1);
            end if;
         end loop;
      end loop;
      return not Crc;
   end Compute;

end Fusa.Crc32;
