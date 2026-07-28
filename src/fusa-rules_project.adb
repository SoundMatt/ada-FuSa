with Ada.Directories;
with Fusa.Files;
with Fusa.Engine; use Fusa.Engine;

package body Fusa.Rules_Project is

   --  Returns a single WARNING finding if none of Candidates exist directly
   --  under Project_Root, else an empty list. Loc references the first
   --  candidate name (nothing to point a line number at -- this is a
   --  project-level, not source-level, concern).
   function Check_Present
     (Project_Root : String;
      Rule_Id      : String;
      Candidates   : String_List;
      Message      : String;
      Remediation  : String) return Finding_List
   is
      Result : Finding_List;
   begin
      for C of Candidates loop
         if Fusa.Files.Exists (Fusa.Files.Join (Project_Root, C)) then
            return Result;
         end if;
      end loop;
      Result.Append
        (Make_Finding
           (Rule_Id     => Rule_Id,
            Severity    => Warning,
            Message     => Message,
            Loc         => Make_Location (Candidates.Element (1)),
            Category    => Derive_Category (Rule_Id),
            Remediation => Remediation));
      return Result;
   end Check_Present;

   function Any_Gpr_File_Exists (Project_Root : String) return Boolean is
      Search : Ada.Directories.Search_Type;
      Ent    : Ada.Directories.Directory_Entry_Type;
      Found  : Boolean := False;
   begin
      Ada.Directories.Start_Search
        (Search, Project_Root, "*.gpr", (Ada.Directories.Ordinary_File => True,
                                          others => False));
      Found := Ada.Directories.More_Entries (Search);
      Ada.Directories.End_Search (Search);
      return Found;
   exception
      when Ada.Directories.Name_Error =>
         return False;
   end Any_Gpr_File_Exists;

   ----------------------------------------------------------------------
   --  FUSA001 -- no .gpr project file
   ----------------------------------------------------------------------

   type Fusa001_Rule is new Rule_Interface with null record;

   overriding function Id (R : Fusa001_Rule) return String is ("FUSA001");
   overriding function Description (R : Fusa001_Rule) return String is
     ("no .gpr project file found at the project root");
   overriding function Run
     (R : Fusa001_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      pragma Unreferenced (Files);
      Result : Finding_List;
   begin
      if not Any_Gpr_File_Exists (Project_Root) then
         Result.Append
           (Make_Finding
              (Rule_Id     => "FUSA001",
               Severity    => Warning,
               Message     => "no .gpr project file found at the project root",
               Loc         => Make_Location ("*.gpr"),
               Category    => Derive_Category ("FUSA001"),
               Remediation => "add a GNAT project file (e.g. <name>.gpr) so the " &
                 "project can be built with gprbuild"));
      end if;
      return Result;
   end Run;

   ----------------------------------------------------------------------
   --  FUSA002 -- no LICENSE file
   ----------------------------------------------------------------------

   type Fusa002_Rule is new Rule_Interface with null record;

   overriding function Id (R : Fusa002_Rule) return String is ("FUSA002");
   overriding function Description (R : Fusa002_Rule) return String is
     ("no LICENSE file found at the project root");
   overriding function Run
     (R : Fusa002_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      pragma Unreferenced (Files);
      Candidates : String_List;
   begin
      Candidates.Append ("LICENSE");
      Candidates.Append ("LICENSE.md");
      Candidates.Append ("LICENSE.txt");
      return Check_Present
        (Project_Root, "FUSA002", Candidates,
         "no LICENSE file found at the project root",
         "add a LICENSE (or LICENSE.md/LICENSE.txt) file stating the project's licence terms");
   end Run;

   ----------------------------------------------------------------------
   --  FUSA003 -- no README file
   ----------------------------------------------------------------------

   type Fusa003_Rule is new Rule_Interface with null record;

   overriding function Id (R : Fusa003_Rule) return String is ("FUSA003");
   overriding function Description (R : Fusa003_Rule) return String is
     ("no README file found at the project root");
   overriding function Run
     (R : Fusa003_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      pragma Unreferenced (Files);
      Candidates : String_List;
   begin
      Candidates.Append ("README.md");
      Candidates.Append ("README");
      Candidates.Append ("README.txt");
      Candidates.Append ("README.rst");
      return Check_Present
        (Project_Root, "FUSA003", Candidates,
         "no README file found at the project root",
         "add a README.md documenting the project's purpose, build, and usage");
   end Run;

   ----------------------------------------------------------------------
   --  FUSA004 -- no CI configuration found
   ----------------------------------------------------------------------

   type Fusa004_Rule is new Rule_Interface with null record;

   overriding function Id (R : Fusa004_Rule) return String is ("FUSA004");
   overriding function Description (R : Fusa004_Rule) return String is
     ("no .github/workflows CI configuration found at the project root");
   overriding function Run
     (R : Fusa004_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      pragma Unreferenced (Files);
      Result : Finding_List;
   begin
      if not Fusa.Files.Is_Directory
        (Fusa.Files.Join (Project_Root, ".github/workflows"))
      then
         Result.Append
           (Make_Finding
              (Rule_Id     => "FUSA004",
               Severity    => Warning,
               Message     => "no .github/workflows CI configuration found at " &
                 "the project root",
               Loc         => Make_Location (".github/workflows"),
               Category    => Derive_Category ("FUSA004"),
               Remediation => "add a GitHub Actions workflow (or another CI " &
                 "system this check does not yet recognise) so changes are " &
                 "built and tested automatically"));
      end if;
      return Result;
   end Run;

   ----------------------------------------------------------------------
   --  Registration
   ----------------------------------------------------------------------

   P001 : aliased Fusa001_Rule;
   P002 : aliased Fusa002_Rule;
   P003 : aliased Fusa003_Rule;
   P004 : aliased Fusa004_Rule;

begin
   Register (P001'Access);
   Register (P002'Access);
   Register (P003'Access);
   Register (P004'Access);
end Fusa.Rules_Project;
