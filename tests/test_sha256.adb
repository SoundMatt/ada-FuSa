with Fusa.Sha256;
with Test_Framework; use Test_Framework;

procedure Test_Sha256 is
begin
   --  fusa:test REQ-019
   Check (Fusa.Sha256.Hex_Digest ("") =
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "sha256('') matches known vector");
   Check (Fusa.Sha256.Hex_Digest ("abc") =
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          "sha256('abc') matches known vector");
   Check (Fusa.Sha256.Hex_Digest ("abc")'Length = 64,
          "digest is exactly 64 hex characters");
   Check (Fusa.Sha256.Hex_Digest ("abc") /= Fusa.Sha256.Hex_Digest ("abd"),
          "different inputs produce different digests");
end Test_Sha256;
