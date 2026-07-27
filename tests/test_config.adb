with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Config;
with Test_Framework; use Test_Framework;

procedure Test_Config is
   Root : constant String := "tmp_test_config";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root);

   Check (not Fusa.Config.Exists (Root), "no config initially");

   declare
      Cfg : Fusa.Config.Project_Config := Fusa.Config.Default_Config ("myproj");
   begin
      Cfg.Standard := To_Unbounded_String ("do178c");
      Cfg.Dal := To_Unbounded_String ("DAL-A");
      Cfg.Source_Dirs.Append ("src");
      Cfg.Exclude_Patterns.Append ("*.gen.adb");
      Fusa.Config.Save (Root, Cfg);
   end;

   Check (Fusa.Config.Exists (Root), "config exists after Save");

   declare
      Loaded : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root);
   begin
      Check (To_String (Loaded.Name) = "myproj", "name round-trips");
      Check (To_String (Loaded.Standard) = "do178c", "standard round-trips");
      Check (To_String (Loaded.Dal) = "DAL-A", "dal round-trips");
      Check (Length (Loaded.Asil) = 0, "asil stays blank (only dal was set)");
      Check (Natural (Loaded.Source_Dirs.Length) = 1
             and then Loaded.Source_Dirs.Element (1) = "src",
             "sourceDirs round-trips");
      Check (Natural (Loaded.Exclude_Patterns.Length) = 1,
             "excludePatterns round-trips");
   end;

   --  Requirements + duplicate-id detection
   declare
      Reqs : Fusa.Config.Requirement_List;
      R1, R2 : Fusa.Config.Requirement;
   begin
      R1.Id := To_Unbounded_String ("REQ-001");
      R1.Title := To_Unbounded_String ("first");
      R2.Id := To_Unbounded_String ("REQ-002");
      Reqs.Append (R1);
      Reqs.Append (R2);
      Fusa.Config.Save_Requirements (Root, Reqs);
   end;

   declare
      Findings : Finding_List;
      Loaded : constant Fusa.Config.Requirement_List :=
        Fusa.Config.Load_Requirements (Root, Findings);
   begin
      Check (Natural (Loaded.Length) = 2, "two distinct requirements round-trip");
      Check (Findings.Is_Empty, "no duplicate findings when ids are unique");
   end;

   --  Now inject a duplicate id directly via the raw file and confirm detection.
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/.fusa-reqs.json");
      Ada.Text_IO.Put_Line
        (F, "{""requirements"":[{""id"":""REQ-001""},{""id"":""REQ-001""}]}");
      Ada.Text_IO.Close (F);
   end;
   declare
      Findings : Finding_List;
      Loaded : constant Fusa.Config.Requirement_List :=
        Fusa.Config.Load_Requirements (Root, Findings);
   begin
      Check (Natural (Loaded.Length) = 1, "duplicate id is not added twice");
      Check (Natural (Findings.Length) = 1, "duplicate id produces exactly one finding");
      Check (Findings.Element (1).Severity = Error, "duplicate-id finding is an ERROR");
      Check (Findings.Element (1).Category = Requirement,
             "duplicate-id finding has category requirement");
   end;

   --  Invalid config
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/.fusa.json");
      Ada.Text_IO.Put_Line (F, "{not valid json");
      Ada.Text_IO.Close (F);
   end;
   declare
      Raised : Boolean := False;
   begin
      begin
         declare
            C : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root);
            pragma Unreferenced (C);
         begin
            null;
         end;
      exception
         when Fusa.Config.Invalid_Config_Error =>
            Raised := True;
      end;
      Check (Raised, "malformed .fusa.json raises Invalid_Config_Error");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Config;
