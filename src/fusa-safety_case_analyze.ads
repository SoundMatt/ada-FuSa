--  fusa#83: safety-case used to be permanently vacuous ("nodes": [])
--  on every real project unless a human hand-authored the entire GSN
--  argument. Unlike fmea/tara (Fusa.Fmea_Analyze/Fusa.Tara_Analyze),
--  there is no way to derive a genuine safety ARGUMENT purely from
--  source -- whether an argument is sound is exactly the certification
--  engineer's judgement call this tool has never claimed to make (see
--  Fusa.Config's own doc comment on safety-case). What IS real and
--  derivable is which evidence artifacts (README's "Evidence Artifacts"
--  table -- fusa-report.json, qualify-report.json, comp-report.json,
--  etc.) actually exist on disk for this project right now: this
--  package builds one real goal/strategy/solution skeleton citing only
--  the artifacts genuinely present, never a fabricated claim about one
--  that doesn't exist (matching section 1.6.1's own solution-evidence
--  rule: "a claim of evidence that names a file the project doesn't
--  actually contain is worse than an honestly-missing solution").
--
--  If NO evidence artifact exists yet, Derive_Nodes returns an empty
--  list -- there being nothing real to cite is not, itself, faked.
--
--  safety-case's own command handler only calls this to fill in nodes
--  when .fusa-safety-case.json's own "nodes" array is empty, so a
--  project with a hand-authored real GSN argument keeps it completely
--  unchanged.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa.Config;

package Fusa.Safety_Case_Analyze is

   --  fusa:req REQ-123
   function Derive_Nodes
     (Project_Root : String; Root_Goal : out Unbounded_String)
      return Fusa.Config.Gsn_Node_List;

end Fusa.Safety_Case_Analyze;
