--  `lint` command (spec section 9.3 MAY): general-correctness/formatting
--  hygiene, distinct from `check`'s ADA/SEC/FUSA rules and from
--  `analyze`'s deeper static analysis. Deliberately NOT registered with
--  Fusa.Engine, same reasoning as Fusa.Analyze -- its own opt-in command,
--  `check`'s finding set is unaffected.
--
--  Named Rules_Lint, not Lint, to avoid colliding with the
--  Fusa.Category_Kind enum literal Fusa.Lint (Category => Fusa.Lint is
--  used throughout the findings this package builds).

package Fusa.Rules_Lint is

   --  fusa:req REQ-111
   function Scan
     (Project_Root : String; Files : String_List) return Finding_List;

end Fusa.Rules_Lint;
