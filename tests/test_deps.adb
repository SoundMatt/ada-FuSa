with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Deps;
with Fusa.Files;
with Test_Framework; use Test_Framework;

procedure Test_Deps is
   Root : constant String := "tmp_test_deps";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   Fusa.Files.Write_File
     (Root & "/src/pkg_a.ads",
      "package Pkg_A is" & ASCII.LF &
      "   procedure Do_It;" & ASCII.LF &
      "end Pkg_A;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/pkg_a.adb",
      "package body Pkg_A is" & ASCII.LF &
      "   procedure Do_It is begin null; end Do_It;" & ASCII.LF &
      "end Pkg_A;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/pkg_b.ads",
      "with Ada.Text_IO;  --  not a project unit, must be filtered out" & ASCII.LF &
      "with Pkg_A;" & ASCII.LF &
      "package Pkg_B is" & ASCII.LF &
      "   type T is tagged null record with Some_Aspect => True;  --  not a with-clause" &
      ASCII.LF &
      "   procedure Do_It;" & ASCII.LF &
      "end Pkg_B;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/pkg_c.ads",
      "private with Pkg_B;" & ASCII.LF &
      "package Pkg_C is" & ASCII.LF &
      "   procedure Do_It;" & ASCII.LF &
      "end Pkg_C;" & ASCII.LF);

   declare
      Files : String_List;
   begin
      Files.Append ("src/pkg_a.ads");
      Files.Append ("src/pkg_a.adb");
      Files.Append ("src/pkg_b.ads");
      Files.Append ("src/pkg_c.ads");

      declare
         Nodes : constant Fusa.Deps.Dep_Node_List := Fusa.Deps.Analyze (Root, Files);
      begin
         --  fusa:test REQ-102
         Check (Natural (Nodes.Length) = 3,
                "Pkg_A's .ads and .adb merge into a single node (3 nodes total, not 4)");

         declare
            A : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, "src/pkg_a.adb");
         begin
            Check (To_String (A.Name) = "Pkg_A", "Find_By_File resolves a .adb path to its unit");
            Check (Natural (A.Files.Length) = 2,
                   "the merged Pkg_A node lists both its .ads and .adb files");
            Check (Natural (A.Deps.Length) = 0, "Pkg_A has no project-internal dependencies");
         end;

         declare
            B : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, "src/pkg_b.ads");
         begin
            Check (Natural (B.Deps.Length) = 1 and then B.Deps.Element (1) = "Pkg_A",
                   "Pkg_B's dependency on Ada.Text_IO (not a project unit) is filtered out, "
                   & "leaving only Pkg_A; the aspect-specification 'with' inside the type "
                   & "declaration is not mistaken for a context-clause with");
         end;

         declare
            C : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, "src/pkg_c.ads");
         begin
            Check (Natural (C.Deps.Length) = 1 and then C.Deps.Element (1) = "Pkg_B",
                   "a 'private with' clause is recognised as a real dependency");
         end;

         declare
            Unresolved : constant Fusa.Deps.Dep_Node :=
              Fusa.Deps.Find_By_File (Nodes, "src/nope.ads");
         begin
            Check (Length (Unresolved.Name) = 0,
                   "Find_By_File returns an empty-name node for an unknown path");
         end;

         declare
            R : constant Fusa.Deps.Dep_Node_List := Fusa.Deps.Reverse_Reachable (Nodes, "Pkg_A");
            Names : String_List;
         begin
            for N of R loop
               Names.Append (To_String (N.Name));
            end loop;
            Check (Natural (R.Length) = 2, "Pkg_A is transitively depended on by both "
                   & "Pkg_B (direct) and Pkg_C (transitive, via Pkg_B) -- 2 impacted units");
            declare
               Has_B, Has_C : Boolean := False;
            begin
               for N of Names loop
                  if N = "Pkg_B" then Has_B := True; end if;
                  if N = "Pkg_C" then Has_C := True; end if;
               end loop;
               Check (Has_B, "Pkg_B (direct dependent) is in the reverse-reachable set");
               Check (Has_C, "Pkg_C (transitive dependent) is in the reverse-reachable set");
            end;
         end;

         declare
            None : constant Fusa.Deps.Dep_Node_List :=
              Fusa.Deps.Reverse_Reachable (Nodes, "Pkg_C");
         begin
            Check (Natural (None.Length) = 0,
                   "nothing depends on Pkg_C, so its reverse-reachable set is empty");
         end;
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Deps;
