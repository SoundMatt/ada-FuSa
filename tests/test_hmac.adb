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
end Test_Hmac;
