--  Minimal, dependency-free SHA-256 (FIPS 180-4). Treats each Character of
--  the input String as one raw byte (0 .. 255) -- callers are responsible
--  for ensuring the String already holds the intended byte sequence (e.g.
--  UTF-8 encoded text stored byte-for-byte in Latin-1 range Characters).

package Fusa.Sha256 is

   --  Returns the 64-character lowercase hex digest of Data.
   function Hex_Digest (Data : String) return String;

end Fusa.Sha256;
