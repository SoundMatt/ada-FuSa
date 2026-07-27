with Ada.Directories; use Ada.Directories;
with Fusa.Files;
with Fusa.Glob;

package body Fusa.Source_Scan is

   function Is_Skipped_Dir (Name : String) return Boolean is
     (Name = ".git" or else Name = "obj" or else Name = "bin"
      or else Name = "alire" or else Name = ".alire");

   function Has_Suffix (Name, Suffix : String) return Boolean is
     (Name'Length >= Suffix'Length
      and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix);

   procedure Walk
     (Dir_Path     : String;
      Project_Root : String;
      Cfg          : Fusa.Config.Project_Config;
      Result       : in out String_List)
   is
      Search : Search_Type;
      Ent    : Directory_Entry_Type;
   begin
      Start_Search
        (Search, Dir_Path, "",
         (Ordinary_File => True, Directory => True, Special_File => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Ent);
         declare
            Name : constant String := Simple_Name (Ent);
         begin
            if Name /= "." and then Name /= ".." then
               declare
                  Full_Path : constant String := Fusa.Files.Join (Dir_Path, Name);
                  Rel       : constant String :=
                    Fusa.Files.Relative_To (Project_Root, Full_Path);
               begin
                  if Kind (Ent) = Directory then
                     if not Is_Skipped_Dir (Name)
                       and then not Fusa.Glob.Is_Excluded (Cfg.Exclude_Patterns, Rel)
                     then
                        Walk (Full_Path, Project_Root, Cfg, Result);
                     end if;
                  else
                     if (Has_Suffix (Name, ".ads") or else Has_Suffix (Name, ".adb"))
                       and then not Fusa.Glob.Is_Excluded (Cfg.Exclude_Patterns, Rel)
                     then
                        Result.Append (Rel);
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
      End_Search (Search);
   end Walk;

   function Find_Source_Files
     (Project_Root : String; Cfg : Fusa.Config.Project_Config) return String_List
   is
      Result : String_List;
   begin
      if Cfg.Source_Dirs.Is_Empty then
         Walk (Project_Root, Project_Root, Cfg, Result);
      else
         for D of Cfg.Source_Dirs loop
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, D);
            begin
               if Fusa.Files.Is_Directory (Full) then
                  Walk (Full, Project_Root, Cfg, Result);
               end if;
            end;
         end loop;
      end if;
      return Result;
   end Find_Source_Files;

end Fusa.Source_Scan;
