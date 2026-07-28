--  §1.4.1 function-level requirement tagging (SHOULD, phased target): scans
--  a project's .ads files for public function/procedure declarations and
--  determines which carry a directly-preceding "-- fusa:req" tag, feeding
--  trace's --func-coverage gate.

with Ada.Containers.Indefinite_Vectors;

package Fusa.Func_Scan is

   type Func_Info is record
      Name    : Unbounded_String;
      File    : Unbounded_String;
      Line    : Positive;
      Has_Tag : Boolean := False;
   end record;

   package Func_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Func_Info);
   subtype Func_List is Func_Vectors.Vector;

   --  fusa:req REQ-024
   --  Scans every .ads file in Files (excluding tests/test paths -- see
   --  spec section 1.4.1: this targets a tool's own safety-relevant
   --  implementation, not test scaffolding) for top-level function/
   --  procedure declarations in the package's visible (public) part --
   --  i.e. before a bare "private" line, if any -- excluding generic
   --  formal parameters ("with function"/"with procedure"). A declaration
   --  counts as tagged (Has_Tag) if a "-- fusa:req" marker appears
   --  anywhere in the contiguous block of comment lines immediately
   --  preceding it (its doc comment). Each overload/declaration is
   --  counted separately.
   function Scan_Public_Functions
     (Project_Root : String; Files : String_List) return Func_List;

end Fusa.Func_Scan;
