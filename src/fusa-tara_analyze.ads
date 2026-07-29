--  fusa#83: tara used to be permanently vacuous on every real project
--  (a hand-authored .fusa-tara.json was the only way to get any content
--  at all), just like fmea (see Fusa.Fmea_Analyze). Unlike fmea, TARA's
--  natural analysis unit is the asset/component, not the individual
--  function, so this derives one real threat per real public
--  package/component Fusa.Func_Scan already finds, using the SAME
--  name-based heuristic classification Fusa.Fmea_Analyze uses (a
--  component whose functions look like they sign/verify/hash gets a
--  cryptographic-integrity threat; one that writes/saves/stores gets a
--  tampering/data-integrity threat; one that runs/executes/scans gets a
--  denial-of-service threat; otherwise a generic unauthorized-
--  modification threat) -- a real, source-traced starting point, not a
--  fabricated claim about a specific vulnerability.
--
--  tara's own command handler only calls this to fill in threats when
--  .fusa-tara.json's own "threats" array is empty, so a project with
--  hand-authored real TARA content keeps it completely unchanged.

with Fusa.Config;
with Fusa.Func_Scan;

package Fusa.Tara_Analyze is

   --  fusa:req REQ-122
   function Derive_Threats
     (Funcs : Fusa.Func_Scan.Func_List) return Fusa.Config.Threat_List;

end Fusa.Tara_Analyze;
