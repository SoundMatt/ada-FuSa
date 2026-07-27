--  §1.4 source annotation scanning: `-- fusa:req <ID>`, `-- fusa:test <ID>`,
--  and the optional `-- fusa:sec-test <ID>`. Ada's only comment form is
--  `--`, so (unlike languages with block comments) there is no separate
--  "scan inside block comments" case to handle.

with Ada.Containers.Indefinite_Vectors;

package Fusa.Annotations is

   type Tag_Kind is (Impl, Test, Sec_Test);

   type Tag is record
      Requirement_Id : Unbounded_String;
      File           : Unbounded_String;
      Line           : Positive;
      Kind           : Tag_Kind;
   end record;

   package Tag_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Tag);
   subtype Tag_List is Tag_Vectors.Vector;

   --  Scans Files for annotations. A line carrying a recognised marker
   --  with zero or more-than-one following token is malformed and MUST
   --  NOT be silently dropped: it is reported as a WARNING finding
   --  (category requirement) in Findings instead of producing a Tag.
   function Scan
     (Project_Root : String;
      Files        : String_List;
      Findings     : in out Finding_List) return Tag_List;

end Fusa.Annotations;
