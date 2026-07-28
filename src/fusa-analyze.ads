--  `analyze` command (spec section 9.3 MAY): a deeper, own-pass static
--  analysis beyond `check`'s baseline ADA/SEC/FUSA rules, emitting
--  ANAL-prefixed findings. Deliberately NOT registered with Fusa.Engine --
--  `check`'s finding set and gate behaviour are unaffected by this
--  package; `analyze` is its own opt-in command with its own report kind,
--  mirroring how `comp`/`coupling` sit alongside (not inside) `check`.
--  Pure text-based static analysis, no full Ada parser, same methodology
--  as Fusa.Comp/Fusa.Deps -- see Fusa.Analyze.Analyze for each rule's
--  exact (deliberately conservative) definition and documented
--  limitations.

package Fusa.Analyze is

   --  fusa:req REQ-110
   function Analyze
     (Project_Root : String; Files : String_List) return Finding_List;

end Fusa.Analyze;
