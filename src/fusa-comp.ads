--  §9.2 `comp`: McCabe cyclomatic complexity V(G) per function (DO-178C
--  §6.3.4). Pure text-based static analysis -- no full Ada parser -- so
--  the counting rule is documented precisely (see Fusa.Comp.Analyze) and
--  deliberately conservative about what it claims to detect.

with Ada.Containers.Indefinite_Vectors;

package Fusa.Comp is

   type Comp_Result is record
      File               : Unbounded_String;
      Line               : Positive;
      Name               : Unbounded_String;
      Complexity         : Positive;
      Exceeds_Threshold  : Boolean;
   end record;

   package Comp_Result_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Comp_Result);
   subtype Comp_Result_List is Comp_Result_Vectors.Vector;

   --  Analyzes every .adb file in Files for subprogram bodies and computes
   --  each one's McCabe cyclomatic complexity. See Fusa.Comp body for the
   --  exact counting rule and its documented limitations (most notably: a
   --  nested subprogram's decision points are attributed to its innermost
   --  enclosing subprogram rather than reported as a separate result).
   --  fusa:req REQ-080
   function Analyze
     (Project_Root : String;
      Files        : String_List;
      Threshold    : Positive) return Comp_Result_List;

end Fusa.Comp;
