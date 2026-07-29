--  fusa#24: SPARK proof-coverage via gnatprove -- ada-FuSa's flagship
--  differentiator among the x-FuSa family (Ada/SPARK is the only member
--  language with a mature formal-verification toolchain). Modelled on
--  the spec's own `coverage --proof` pattern (section 9.2/13, itself
--  modelled on the family's existing `--mcdc`/`--mcdc-file`/
--  `--mcdc-threshold` convention): an external tool (here, gnatprove)
--  produces structured proof data, this package ingests it, and
--  `coverage --proof` renders/gates on the x-FuSa-canonical
--  `proof-report.json` shape (section 13).
--
--  gnatprove itself writes one JSON file per analysed compilation unit
--  (its own ".spark" format, under <object-dir>/gnatprove/*.spark --
--  there is no single native "whole project" aggregate; see e.g.
--  <https://github.com/HeisenbugLtd/spat/blob/master/doc/spark_file_format.md>
--  for the reverse-engineered field-level schema this package's parser
--  follows, since AdaCore's own SPARK User's Guide documents the
--  existence of these files but not their exact JSON field names).
--  Parse_Proof_File therefore accepts EITHER a single such per-unit
--  object, OR a JSON array of them (the practical way to feed gnatprove
--  results for a whole project in one file, e.g. via
--  `jq -s '.' obj/gnatprove/*.spark > proof.json`).
--
--  Only the top-level "proof" array (verification conditions gnatprove
--  attempted to discharge by proof) is counted as a proof obligation --
--  the separate "flow" array (data/information-flow analysis) answers a
--  different question and is out of scope for this obligation count.  A
--  verification condition counts as proved when every one of its
--  check_tree entries has at least one prover attempt with
--  "result": "Valid" (a VC can be split into several proof sub-goals,
--  all of which must succeed); a VC with no recorded check_tree/proof
--  attempts at all is conservatively counted as unproved.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

package Fusa.Proof_Analyze is

   type Func_Proof_Stat is record
      Name               : Unbounded_String;
      File               : Unbounded_String;
      Total_Obligations  : Natural := 0;
      Proved_Obligations : Natural := 0;
   end record;

   --  fusa:req REQ-124
   function Proved (F : Func_Proof_Stat) return Boolean is
     (F.Total_Obligations > 0 and then F.Proved_Obligations = F.Total_Obligations);

   package Func_Proof_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Func_Proof_Stat);
   subtype Func_Proof_List is Func_Proof_Vectors.Vector;

   type Proof_Report is record
      Tool               : Unbounded_String := To_Unbounded_String ("gnatprove");
      Total_Obligations  : Natural := 0;
      Proved_Obligations : Natural := 0;
      Functions          : Func_Proof_List;
   end record;

   --  section 13 MUST: proofPct == 100 * provedObligations /
   --  totalObligations (rounded to one decimal); totalObligations = 0
   --  MUST report proofPct 100 (no obligations means nothing is
   --  unproved).
   --  fusa:req REQ-124
   function Proof_Pct (R : Proof_Report) return Long_Float;

   --  Same value as Proof_Pct, as whole tenths-of-a-percent (e.g. 963 for
   --  96.3) -- Fusa.Json.Writer.Decimal_Value/Decimal_Field's exact input
   --  shape, so the JSON rendering and the --proof-threshold gate always
   --  compare against the identical rounded value, never two
   --  independently-rounded floats that could disagree at the boundary.
   --  fusa:req REQ-124
   function Proof_Pct_Tenths (R : Proof_Report) return Integer;

   --  Reads and parses Path (raised exceptions propagate: Fusa.Files
   --  read errors, or Fusa.Json.Json_Error on malformed JSON -- the
   --  caller is expected to translate both into the usual runtime-error
   --  JSON envelope, matching every other input-file command in this
   --  codebase).
   --  fusa:req REQ-124
   function Parse_Proof_File (Path : String) return Proof_Report;

end Fusa.Proof_Analyze;
