with Interfaces;

package Fusa.Crc32 is

   --  Standard IEEE 802.3 CRC-32 (polynomial 0xEDB88320, reflected),
   --  the checksum used by the ZIP format. Same byte convention as
   --  Fusa.Sha256.Hex_Digest.
   function Compute (Data : String) return Interfaces.Unsigned_32;

end Fusa.Crc32;
