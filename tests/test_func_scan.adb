with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Files;
with Fusa.Func_Scan;
with Test_Framework; use Test_Framework;

procedure Test_Func_Scan is
   Root : constant String := "tmp_test_func_scan";

   function Find (Funcs : Fusa.Func_Scan.Func_List; Name : String) return Natural is
   begin
      for I in 1 .. Natural (Funcs.Length) loop
         if To_String (Funcs.Element (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find;
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");
   Ada.Directories.Create_Path (Root & "/tests");

   Fusa.Files.Write_File
     (Root & "/src/a.ads",
      "package A is" & ASCII.LF &
      "   --  fusa:req REQ-001" & ASCII.LF &
      "   function Tagged_Func (X : Integer) return Integer;" & ASCII.LF &
      ASCII.LF &
      "   function Untagged_Func return Boolean;" & ASCII.LF &
      ASCII.LF &
      "   --  A multi-line doc comment with the tag on an earlier line,not" & ASCII.LF &
      "   --  fusa:req REQ-002" & ASCII.LF &
      "   --  the one directly above the declaration." & ASCII.LF &
      "   procedure Multi_Line_Doc_Comment;" & ASCII.LF &
      ASCII.LF &
      "   generic" & ASCII.LF &
      "      with function Formal_Cb return Boolean;" & ASCII.LF &
      "   procedure Generic_Proc;" & ASCII.LF &
      ASCII.LF &
      "private" & ASCII.LF &
      ASCII.LF &
      "   function Private_Func return Integer;" & ASCII.LF &
      "end A;" & ASCII.LF);

   Fusa.Files.Write_File
     (Root & "/tests/test_helper.ads",
      "package Test_Helper is" & ASCII.LF &
      "   function Assert_Helper return Boolean;" & ASCII.LF &
      "end Test_Helper;" & ASCII.LF);

   declare
      Files : String_List;
   begin
      Files.Append ("src/a.ads");
      Files.Append ("tests/test_helper.ads");
      declare
         --  fusa:test REQ-024
         Funcs : constant Fusa.Func_Scan.Func_List :=
           Fusa.Func_Scan.Scan_Public_Functions (Root, Files);
      begin
         Check (Find (Funcs, "Assert_Helper") = 0,
                "a .ads file under tests/ is excluded from function scanning");

         declare
            I : constant Natural := Find (Funcs, "Tagged_Func");
         begin
            Check (I > 0 and then Funcs.Element (I).Has_Tag,
                   "a function with a directly-preceding fusa:req tag is Has_Tag");
         end;

         declare
            I : constant Natural := Find (Funcs, "Untagged_Func");
         begin
            Check (I > 0 and then not Funcs.Element (I).Has_Tag,
                   "a function with no preceding comment is not Has_Tag");
         end;

         declare
            I : constant Natural := Find (Funcs, "Multi_Line_Doc_Comment");
         begin
            Check (I > 0 and then Funcs.Element (I).Has_Tag,
                   "a fusa:req tag anywhere in the contiguous comment block "
                   & "above a declaration counts, not only the line directly "
                   & "above it");
         end;

         Check (Find (Funcs, "Formal_Cb") = 0,
                "a generic formal subprogram (with function/procedure) is "
                & "not counted as a public declaration");

         Check (Find (Funcs, "Private_Func") = 0,
                "a declaration after a bare 'private' line is excluded");

         Check (Find (Funcs, "Generic_Proc") > 0,
                "a generic procedure's own declaration is still counted");
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Func_Scan;
