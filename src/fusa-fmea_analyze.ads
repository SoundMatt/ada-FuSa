--  fusa#83: fmea used to be permanently vacuous on every real project
--  (a hand-authored .fusa-fmea.json was the only way to get any content
--  at all) despite spec section 9.2 describing it as an analysis command
--  "over the project's public functions/components", structurally
--  identical in spirit to comp (which does derive its own results from
--  real source in this codebase). This package derives one real,
--  source-traced FMEA entry per public function/procedure Fusa.Func_Scan
--  already finds (the same function list --func-coverage's denominator
--  and fmea's own componentsInProject already use), with a failure
--  mode/effect/cause/severity heuristically derived from the function's
--  actual name (per section 1.6.1 rule B: content must vary with the
--  item's real signature, not a single fixed template repeated
--  verbatim) -- modelled on go-FuSa's own fmea.deriveAnalysis.
--
--  Fmea's own command handler (Cmd_Fmea) only calls this to fill in
--  entries when .fusa-fmea.json's own "entries" array is empty, so any
--  project that HAS hand-authored real FMEA content keeps it completely
--  unchanged -- this is a fallback for the previously-always-vacuous
--  case, not a silent override of genuine human analysis.

with Fusa.Config;
with Fusa.Func_Scan;

package Fusa.Fmea_Analyze is

   --  fusa:req REQ-121
   function Derive_Entries
     (Funcs : Fusa.Func_Scan.Func_List) return Fusa.Config.Fmea_Entry_List;

end Fusa.Fmea_Analyze;
