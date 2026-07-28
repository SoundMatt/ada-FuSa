--  Package/unit dependency graph for `boundary`/`impact` (#26). Pure
--  text-based static analysis -- no full Ada parser -- built on top of
--  Fusa.Files.Split_Lines the same way Fusa.Comp is.
--
--  A unit's name is taken from its "package NAME is" / "package body NAME
--  is" line; its dependencies are the "with"/"private with" clauses that
--  appear in the file's context clause, i.e. before that package line --
--  this deliberately excludes Ada 2012+ aspect-specification "with"
--  (e.g. "... with Convention => C;"), which can only appear *after* the
--  unit it belongs to has already started.
--
--  Only intra-project dependencies are kept: a "with" naming a unit that
--  isn't itself one of the files passed to Analyze (e.g. Ada.Text_IO) is
--  dropped, since the boundary graph is meant to show project structure,
--  not the standard library.

with Ada.Containers.Indefinite_Vectors;

package Fusa.Deps is

   type Dep_Node is record
      Name  : Unbounded_String;
      Files : String_List;
      Deps  : String_List;
   end record;

   package Dep_Node_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Dep_Node);
   subtype Dep_Node_List is Dep_Node_Vectors.Vector;

   --  fusa:req REQ-102
   function Analyze (Project_Root : String; Files : String_List) return Dep_Node_List;

   --  Returns the node whose Files list contains Rel_Path (a project-root-
   --  relative path, as found in the Files passed to Analyze), or a node
   --  with an empty Name if none matches.
   --  fusa:req REQ-102
   function Find_By_File (Nodes : Dep_Node_List; Rel_Path : String) return Dep_Node;

   --  All nodes whose Deps (directly or transitively) reach Target_Name,
   --  i.e. every unit that would be affected if Target_Name changed.
   --  Target_Name itself is never included in the result.
   --  fusa:req REQ-102
   function Reverse_Reachable (Nodes : Dep_Node_List; Target_Name : String) return Dep_Node_List;

end Fusa.Deps;
