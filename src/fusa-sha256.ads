--  Minimal, dependency-free SHA-256 (FIPS 180-4). Treats each Character of
--  the input String as one raw byte (0 .. 255) -- callers are responsible
--  for ensuring the String already holds the intended byte sequence (e.g.
--  UTF-8 encoded text stored byte-for-byte in Latin-1 range Characters).
--
--  fusa#101: this package is pure bit-twiddling over a runtime-bounded
--  local array with no I/O, no exceptions, and no heap allocation -- one
--  of ada-FuSa's own most safety-relevant units (every fingerprint,
--  attestation contentHash, and qualify hash in this tool ultimately
--  goes through Hex_Digest), and a reasonable first candidate for this
--  Ada/SPARK-branded tool to actually practice SPARK on its own source,
--  rather than only ever analyzing target projects for it (see #24).
pragma SPARK_Mode (On);

package Fusa.Sha256 is

   --  Returns the 64-character lowercase hex digest of Data.
   --  fusa:req REQ-019
   function Hex_Digest (Data : String) return String
     with Post => Hex_Digest'Result'Length = 64;

end Fusa.Sha256;
