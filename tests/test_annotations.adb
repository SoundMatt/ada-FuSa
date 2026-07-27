with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Files;
with Fusa.Annotations; use Fusa.Annotations;
with Test_Framework; use Test_Framework;

procedure Test_Annotations is
   Root : constant String := "tmp_test_annotations";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   Fusa.Files.Write_File
     (Root & "/src/a.ads",
      "package A is" & ASCII.LF &
      "   -- fusa:req REQ-001" & ASCII.LF &
      "   procedure P;" & ASCII.LF &
      "   -- fusa:req REQ-002 free text description is fine" & ASCII.LF &
      "   procedure Q;" & ASCII.LF &
      "   -- fusa:sec-test REQ-001" & ASCII.LF &
      "   -- fusa:req" & ASCII.LF &                       --  malformed: no id
      "   -- fusa:req REQ-003 REQ-004" & ASCII.LF &        --  malformed: two ids
      "end A;" & ASCII.LF);

   declare
      Files    : String_List;
      Findings : Finding_List;
   begin
      Files.Append ("src/a.ads");
      declare
         Tags : constant Fusa.Annotations.Tag_List :=
           Fusa.Annotations.Scan (Root, Files, Findings);
         Req_001_Impl, Req_001_Sec, Req_002_Impl : Natural := 0;
      begin
         Check (Natural (Tags.Length) = 3, "three well-formed tags are recognised");
         for T of Tags loop
            if To_String (T.Requirement_Id) = "REQ-001" and then T.Kind = Fusa.Annotations.Impl then
               Req_001_Impl := Req_001_Impl + 1;
            elsif To_String (T.Requirement_Id) = "REQ-001" and then T.Kind = Fusa.Annotations.Sec_Test then
               Req_001_Sec := Req_001_Sec + 1;
            elsif To_String (T.Requirement_Id) = "REQ-002" and then T.Kind = Fusa.Annotations.Impl then
               Req_002_Impl := Req_002_Impl + 1;
            end if;
         end loop;
         Check (Req_001_Impl = 1, "REQ-001 impl tag captured");
         Check (Req_001_Sec = 1, "REQ-001 sec-test tag captured");
         Check (Req_002_Impl = 1,
                "trailing free-text description after the id does not break parsing");
         Check (Natural (Findings.Length) = 2,
                "missing-id and two-ids-on-one-line both produce a malformed-annotation finding");
         for F of Findings loop
            Check (F.Severity = Warning, "malformed annotation findings are WARNING");
         end loop;
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Annotations;
