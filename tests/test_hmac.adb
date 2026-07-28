with Fusa.Hmac;
with Test_Framework; use Test_Framework;

procedure Test_Hmac is
begin
   --  fusa:test REQ-087
   --  RFC 4231 test case 1: Key = 0x0b * 20, Data = "Hi There".
   declare
      Key : constant String (1 .. 20) := (others => Character'Val (16#0b#));
   begin
      Check (Fusa.Hmac.Sha256_Hex (Key, "Hi There") =
               "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
             "HMAC-SHA256 matches RFC 4231 test case 1 (short key)");
   end;

   --  RFC 4231 test case 6: a 131-byte key exercises the "key longer than
   --  block size gets hashed down first" branch.
   declare
      Key : constant String (1 .. 131) := (others => Character'Val (16#aa#));
   begin
      Check (Fusa.Hmac.Sha256_Hex
               (Key, "Test Using Larger Than Block-Size Key - Hash Key First") =
               "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54",
             "HMAC-SHA256 matches RFC 4231 test case 6 (key longer than block size)");
   end;

   Check (Fusa.Hmac.Sha256_Hex ("key", "message") /=
            Fusa.Hmac.Sha256_Hex ("key", "different message"),
          "different messages under the same key produce different HMACs");
   Check (Fusa.Hmac.Sha256_Hex ("key1", "message") /=
            Fusa.Hmac.Sha256_Hex ("key2", "message"),
          "the same message under different keys produces different HMACs");
   Check (Fusa.Hmac.Sha256_Hex ("k", "m")'Length = 64,
          "the digest is exactly 64 hex characters");

   --  fusa:test REQ-087
   --  Constant_Time_Equal: functional correctness (the constant-time
   --  *property* itself -- always iterating the full length regardless
   --  of where a mismatch occurs -- isn't something a black-box Check
   --  can observe via timing, so this exercises only that it computes
   --  the right Boolean in every case).
   Check (Fusa.Hmac.Constant_Time_Equal ("abcdef", "abcdef"),
          "identical strings compare equal");
   Check (not Fusa.Hmac.Constant_Time_Equal ("abcdef", "abcdeg"),
          "a difference in the last character is still detected");
   Check (not Fusa.Hmac.Constant_Time_Equal ("abcdef", "xbcdef"),
          "a difference in the first character is still detected");
   Check (not Fusa.Hmac.Constant_Time_Equal ("abc", "abcd"),
          "different-length strings (shorter first) are never equal");
   Check (not Fusa.Hmac.Constant_Time_Equal ("abcd", "abc"),
          "different-length strings (longer first) are never equal");
   Check (Fusa.Hmac.Constant_Time_Equal ("", ""),
          "two empty strings compare equal");
   Check (not Fusa.Hmac.Constant_Time_Equal ("a", ""),
          "a non-empty string never equals an empty one");
end Test_Hmac;
