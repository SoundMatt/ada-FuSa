--  Project-structure rule pack (FUSA001-FUSA004): checks that certain
--  expected files/directories exist at the project root, mirroring
--  java-FuSa's "FUSA" category (config/build-file/LICENSE/README/CI
--  present). Unlike Fusa.Rules_Style's rules, these do not scan file
--  content -- each is a single existence check against Project_Root.
--  Rules register themselves with Fusa.Engine when this package is
--  elaborated -- see fusa-rules_project.adb.
--  fusa:req REQ-079

package Fusa.Rules_Project is
   pragma Elaborate_Body;
end Fusa.Rules_Project;
