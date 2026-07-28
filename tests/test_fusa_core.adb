with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Test_Framework; use Test_Framework;

procedure Test_Fusa_Core is
begin
   --  fusa:test REQ-047
   Check (Fusa.Normalize_Message ("line 42 has 3 errors") = "line # has # errors",
          "digit runs collapse to '#'");
   Check (Fusa.Normalize_Message ("a   b" & ASCII.HT & "c") = "a b c",
          "whitespace runs collapse to a single space");
   Check (Fusa.Normalize_Message ("  trim me  ") = "trim me",
          "leading/trailing whitespace is trimmed");

   --  fusa:test REQ-046
   Check (Fusa.Derive_Category ("LINT001") = Fusa.Lint, "LINT prefix -> lint category");
   Check (Fusa.Derive_Category ("ADA005") = Fusa.Safety, "ADA prefix -> safety category");
   Check (Fusa.Derive_Category ("FUSA001") = Fusa.Safety, "FUSA prefix -> safety category");
   Check (Fusa.Derive_Category ("SEC010") = Fusa.Security, "SEC prefix -> security category");
   Check (Fusa.Derive_Category ("CWE-089") = Fusa.Security, "CWE prefix -> security category");
   Check (Fusa.Derive_Category ("COV001") = Fusa.Coverage, "COV prefix -> coverage category");
   Check (Fusa.Derive_Category ("REQ001") = Fusa.Requirement, "REQ prefix -> requirement category");
   Check (Fusa.Derive_Category ("STYLE001") = Fusa.Style, "STYLE prefix -> style category");
   Check (Fusa.Derive_Category ("CONC001") = Fusa.Concurrency, "CONC prefix -> concurrency category");
   Check (Fusa.Derive_Category ("RACE001") = Fusa.Concurrency, "RACE prefix -> concurrency category");
   Check (Fusa.Derive_Category ("SBOM001") = Fusa.Supply_Chain, "SBOM prefix -> supply-chain category");
   Check (Fusa.Derive_Category ("SLSA001") = Fusa.Supply_Chain, "SLSA prefix -> supply-chain category");
   Check (Fusa.Derive_Category ("VULN001") = Fusa.Supply_Chain, "VULN prefix -> supply-chain category");
   Check (Fusa.Derive_Category ("CFG001") = Fusa.Config_Category, "CFG prefix -> config category");
   Check (Fusa.Derive_Category ("ZZZ999") = Fusa.Other, "unrecognised prefix -> other category");
   Check (Fusa.Derive_Category ("lint001") = Fusa.Lint,
          "prefix matching is case-insensitive (lowercase input)");
   Check (Fusa.Derive_Category ("ada001") = Fusa.Safety,
          "prefix matching is case-insensitive (mixed real-world rule id)");
   Check (Fusa.Derive_Category ("") = Fusa.Other, "empty rule id -> other category");

   --  Image() for every enum literal (not just the ones exercised above).
   --  fusa:test REQ-002
   --  fusa:test REQ-043
   Check (Fusa.Image (Fusa.Info) = "INFO", "Severity Image: INFO");
   Check (Fusa.Image (Fusa.Warning) = "WARNING", "Severity Image: WARNING");
   Check (Fusa.Image (Fusa.Error) = "ERROR", "Severity Image: ERROR");

   Check (Fusa.Image (Fusa.Lint) = "lint", "Category Image: lint");
   Check (Fusa.Image (Fusa.Style) = "style", "Category Image: style");
   Check (Fusa.Image (Fusa.Safety) = "safety", "Category Image: safety");
   Check (Fusa.Image (Fusa.Security) = "security", "Category Image: security");
   Check (Fusa.Image (Fusa.Coverage) = "coverage", "Category Image: coverage");
   Check (Fusa.Image (Fusa.Requirement) = "requirement", "Category Image: requirement");
   Check (Fusa.Image (Fusa.Concurrency) = "concurrency", "Category Image: concurrency");
   Check (Fusa.Image (Fusa.Supply_Chain) = "supply-chain",
          "Category Image: Supply_Chain renders with a hyphen");
   Check (Fusa.Image (Fusa.Config_Category) = "config", "Category Image: config");
   Check (Fusa.Image (Fusa.Other) = "other", "Category Image: other");

   Check (Fusa.Image (Fusa.Open) = "open", "Disposition Image: open");
   Check (Fusa.Image (Fusa.Accepted) = "accepted", "Disposition Image: accepted");
   Check (Fusa.Image (Fusa.Deferred) = "deferred", "Disposition Image: deferred");
   Check (Fusa.Image (Fusa.Rejected) = "rejected", "Disposition Image: rejected");

   Check (Fusa.Normalize_Message ("12345") = "#",
          "an all-digit message collapses to a single '#'");
   Check (Fusa.Normalize_Message ("1 2") = "# #",
          "digits separated by whitespace stay as two separate '#' tokens");
   Check (Fusa.Normalize_Message ("") = "", "empty message normalises to empty");

   declare
      F1 : constant Finding :=
        Make_Finding ("ADA001", Error, "bad thing", Make_Location ("src/x.adb", 10));
      F2 : constant Finding :=
        Make_Finding ("ADA001", Error, "bad thing", Make_Location ("src/x.adb", 99));
      F3 : constant Finding :=
        Make_Finding ("ADA002", Error, "bad thing", Make_Location ("src/x.adb", 10));
   begin
      --  fusa:test REQ-004
      --  fusa:test REQ-044
      --  fusa:test REQ-045
      Check (Length (F1.Fingerprint) = 71, --  "sha256:" (7) + 64 hex chars
             "fingerprint has the expected 'sha256:' + 64-hex-char length");
      Check (F1.Fingerprint = F2.Fingerprint,
             "fingerprint is independent of line number (not part of the canonical input)");
      Check (F1.Fingerprint /= F3.Fingerprint,
             "fingerprint differs when ruleId differs");
   end;
end Test_Fusa_Core;
