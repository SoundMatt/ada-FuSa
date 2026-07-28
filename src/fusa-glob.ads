--  Minimal gitignore-style glob matcher for the §1.2 `excludePatterns`
--  config field. Supports '*' (any run of non-'/' characters), '**' (any
--  run of characters including '/'), and '?' (any single non-'/'
--  character). This is a practical subset of gitignore syntax, not a full
--  implementation (no negation, no anchoring nuances for leading '/').

package Fusa.Glob is

   --  Matches Pattern against Text in full (implicit anchors at both ends).
   --  fusa:req REQ-048
   function Match (Pattern, Text : String) return Boolean;

   --  True if Rel_Path (a "/"-separated, project-relative path) should be
   --  excluded per Patterns: a pattern containing '/' is matched against
   --  the full path; a pattern without '/' is matched against every path
   --  segment (so it also excludes whole directories by name).
   --  fusa:req REQ-049
   function Is_Excluded (Patterns : String_List; Rel_Path : String) return Boolean;

end Fusa.Glob;
