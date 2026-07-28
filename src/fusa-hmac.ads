--  Minimal, dependency-free HMAC-SHA256 (RFC 2104), built on top of
--  Fusa.Sha256's existing SHA-256 digest -- for evidence-file integrity
--  signing (`sign sign`/`sign verify`), not as a general-purpose crypto
--  library.

package Fusa.Hmac is

   --  Returns the 64-character lowercase hex HMAC-SHA256 of Message under
   --  Key. Both Key and Message are treated as raw bytes (one byte per
   --  Character), the same convention Fusa.Sha256.Hex_Digest already uses.
   --  fusa:req REQ-087
   function Sha256_Hex (Key, Message : String) return String;

end Fusa.Hmac;
