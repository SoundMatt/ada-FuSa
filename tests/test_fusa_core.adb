with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Test_Framework; use Test_Framework;

procedure Test_Fusa_Core is
begin
   Check (Fusa.Normalize_Message ("line 42 has 3 errors") = "line # has # errors",
          "digit runs collapse to '#'");
   Check (Fusa.Normalize_Message ("a   b" & ASCII.HT & "c") = "a b c",
          "whitespace runs collapse to a single space");
   Check (Fusa.Normalize_Message ("  trim me  ") = "trim me",
          "leading/trailing whitespace is trimmed");

   Check (Fusa.Derive_Category ("LINT001") = Fusa.Lint, "LINT prefix -> lint category");
   Check (Fusa.Derive_Category ("ADA005") = Fusa.Safety, "ADA prefix -> safety category");
   Check (Fusa.Derive_Category ("SEC010") = Fusa.Security, "SEC prefix -> security category");
   Check (Fusa.Derive_Category ("COV001") = Fusa.Coverage, "COV prefix -> coverage category");
   Check (Fusa.Derive_Category ("REQ001") = Fusa.Requirement, "REQ prefix -> requirement category");
   Check (Fusa.Derive_Category ("ZZZ999") = Fusa.Other, "unrecognised prefix -> other category");

   Check (Fusa.Image (Fusa.Error) = "ERROR", "Severity Image is uppercase");
   Check (Fusa.Image (Fusa.Supply_Chain) = "supply-chain",
          "Supply_Chain category renders with a hyphen");

   declare
      F1 : constant Finding :=
        Make_Finding ("ADA001", Error, "bad thing", Make_Location ("src/x.adb", 10));
      F2 : constant Finding :=
        Make_Finding ("ADA001", Error, "bad thing", Make_Location ("src/x.adb", 99));
      F3 : constant Finding :=
        Make_Finding ("ADA002", Error, "bad thing", Make_Location ("src/x.adb", 10));
   begin
      Check (Length (F1.Fingerprint) = 71, --  "sha256:" (7) + 64 hex chars
             "fingerprint has the expected 'sha256:' + 64-hex-char length");
      Check (F1.Fingerprint = F2.Fingerprint,
             "fingerprint is independent of line number (not part of the canonical input)");
      Check (F1.Fingerprint /= F3.Fingerprint,
             "fingerprint differs when ruleId differs");
   end;
end Test_Fusa_Core;
