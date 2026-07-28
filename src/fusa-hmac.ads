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

   --  Constant-time string comparison: always examines every character of
   --  the longer of A/B (accumulating a running mismatch flag via XOR/OR
   --  rather than exiting on the first difference), so comparison time
   --  does not leak how many leading characters of an attacker-supplied
   --  value match the true one -- the standard mitigation for a timing
   --  side channel on MAC/signature verification (CWE-208). MUST be used
   --  instead of "=" wherever a caller-supplied value is compared against
   --  a real signature/HMAC digest.
   --  fusa:req REQ-087
   function Constant_Time_Equal (A, B : String) return Boolean;

end Fusa.Hmac;
