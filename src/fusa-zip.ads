--  Minimal ZIP writer (STORED / no-compression entries only) used by
--  `audit-pack`. Produces a flat archive: no directory entries, no
--  subdirectories.

with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Fusa.Zip is

   type Zip_Entry is record
      Name : Unbounded_String; --  archive-relative name, no leading "/"
      Data : Unbounded_String; --  raw bytes (Fusa.Sha256's byte convention)
   end record;

   package Entry_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Zip_Entry);
   subtype Entry_List is Entry_Vectors.Vector;

   --  fusa:req REQ-020
   procedure Write_Zip (Path : String; Entries : Entry_List);

end Fusa.Zip;
