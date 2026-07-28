--  Starter Ada coding-standard rule pack (ADA001-ADA008, drawn from the
--  Ada Quality and Style Guide rather than a ported MISRA-style list, per
--  SoundMatt/FuSaOps#78) plus a small CWE-mapped security rule pack
--  (SEC001-SEC004, sharing the same substring-scan infrastructure). Rules
--  register themselves with Fusa.Engine when this package is elaborated --
--  see fusa-rules_style.adb.
--  fusa:req REQ-017
--  fusa:req REQ-078

package Fusa.Rules_Style is
   pragma Elaborate_Body;
end Fusa.Rules_Style;
