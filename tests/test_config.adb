with Ada.Directories;
with Ada.Text_IO;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Config;
with Fusa.Files;
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
      --  fusa:test REQ-005
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
      --  fusa:test REQ-006
      Check (Natural (Loaded.Length) = 1, "duplicate id is not added twice");
      Check (Natural (Findings.Length) = 1, "duplicate id produces exactly one finding");
      Check (Findings.Element (1).Severity = Error, "duplicate-id finding is an ERROR");
      Check (Findings.Element (1).Category = Requirement,
             "duplicate-id finding has category requirement");
   end;

   --  Regression: a missing/empty/non-string id used to be silently
   --  dropped with no diagnostic at all, unlike a duplicate id.
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/.fusa-reqs.json");
      Ada.Text_IO.Put_Line
        (F, "{""requirements"":[{""id"":""REQ-010""}," &
            "{""title"":""no id key at all""}," &
            "{""id"":""""}," &
            "{""id"":42}]}");
      Ada.Text_IO.Close (F);
   end;
   declare
      Findings : Finding_List;
      Loaded : constant Fusa.Config.Requirement_List :=
        Fusa.Config.Load_Requirements (Root, Findings);
   begin
      Check (Natural (Loaded.Length) = 1,
             "only the entry with a real id is kept in the result list");
      Check (Natural (Findings.Length) = 3,
             "a missing key, an empty string, and a non-string id each "
             & "produce their own ERROR finding");
      for Fnd of Findings loop
         Check (Fnd.Severity = Error, "missing-id findings are ERROR");
         Check (Fnd.Category = Requirement,
                "missing-id findings have category requirement");
      end loop;
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

   --  Regression: a 'project' field present but of the wrong JSON type
   --  used to raise a message saying "missing", which is misleading when
   --  the field was actually there with an unexpected shape.
   declare
      F : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Root & "/.fusa.json");
      Ada.Text_IO.Put_Line (F, "{""project"": 42, ""standard"": ""generic""}");
      Ada.Text_IO.Close (F);
   end;
   declare
      Raised : Boolean := False;
      Msg_Ok : Boolean := False;
   begin
      begin
         declare
            C : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root);
            pragma Unreferenced (C);
         begin
            null;
         end;
      exception
         when E : Fusa.Config.Invalid_Config_Error =>
            Raised := True;
            declare
               Msg : constant String := Ada.Exceptions.Exception_Message (E);
            begin
               Msg_Ok :=
                 Ada.Strings.Fixed.Index (Msg, "must be a string or an object") > 0
                 and then Ada.Strings.Fixed.Index (Msg, "missing") = 0;
            end;
      end;
      Check (Raised, "a wrong-type 'project' field raises Invalid_Config_Error");
      Check (Msg_Ok,
             "the error message distinguishes wrong-type from absent, "
             & "rather than misleadingly saying 'missing'");
   end;

   --  fusa:test REQ-082
   Check (not Fusa.Config.Hara_Exists (Root), "no .fusa-hara.json initially");
   Fusa.Config.Scaffold_Hara (Root);
   Check (Fusa.Config.Hara_Exists (Root), ".fusa-hara.json exists after Scaffold_Hara");
   declare
      Findings : Finding_List;
      Empty    : constant Fusa.Config.Hazard_List := Fusa.Config.Load_Hara (Root, Findings);
   begin
      Check (Natural (Empty.Length) = 0, "a freshly scaffolded hara template has no hazards");
      Check (Natural (Findings.Length) = 0, "no validation findings against an empty template");
   end;

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Hara_File,
      "{""hazards"":[" &
      "{""id"":""HAZ-001"",""hazard"":""h"",""severity"":""S3""," &
      """exposure"":""E4"",""controllability"":""C3"",""asil"":""ASIL-D""," &
      """safetyGoal"":""g""}," &
      "{""id"":""HAZ-002"",""hazard"":""incomplete""}," &
      "{""hazard"":""no id at all""}" &
      "]}");
   declare
      Findings : Finding_List;
      Hazards  : constant Fusa.Config.Hazard_List := Fusa.Config.Load_Hara (Root, Findings);
      Errors, Warnings : Natural := 0;
   begin
      Check (Natural (Hazards.Length) = 2,
             "only the two hazards with a non-empty id are returned "
             & "(the one with no id at all is excluded, not just flagged)");
      for F of Findings loop
         case F.Severity is
            when Error   => Errors := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => null;
         end case;
      end loop;
      Check (Errors = 1, "a hazard with no id produces exactly one ERROR finding");
      Check (Warnings = 1,
             "a hazard with an id but missing other required fields "
             & "produces exactly one WARNING finding");
   end;

   --  fusa:test REQ-083
   Check (not Fusa.Config.Tara_Exists (Root), "no .fusa-tara.json initially");
   Fusa.Config.Scaffold_Tara (Root);
   Check (Fusa.Config.Tara_Exists (Root), ".fusa-tara.json exists after Scaffold_Tara");

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Tara_File,
      "{""threats"":[" &
      "{""id"":""THR-001"",""asset"":""a"",""threat"":""t""," &
      """attackVector"":""av"",""impact"":""i"",""likelihood"":""l""," &
      """risk"":""r"",""treatment"":""tr"",""mitigations"":[""m1"",""m2""]}," &
      "{""threat"":""no id at all""}" &
      "]}");
   declare
      Findings : Finding_List;
      Threats  : constant Fusa.Config.Threat_List := Fusa.Config.Load_Tara (Root, Findings);
   begin
      Check (Natural (Threats.Length) = 1, "only the threat with a non-empty id is returned");
      Check (Natural (Threats.Element (1).Mitigations.Length) = 2,
             "the mitigations array round-trips with both entries");
      Check (Natural (Findings.Length) = 1
             and then Findings.Element (1).Severity = Error,
             "a threat with no id produces exactly one ERROR finding");
   end;

   --  fusa:test REQ-096
   Check (not Fusa.Config.Gap_Objectives_Exist (Root, "do178c"),
          "no .fusa-do178c-objectives.json initially");
   declare
      Starter : Fusa.Config.Gap_Objective_List;
      O       : Fusa.Config.Gap_Objective;
   begin
      O.Id     := To_Unbounded_String ("DO178-PLAN-1");
      O.Status := To_Unbounded_String ("gap");
      Starter.Append (O);
      Fusa.Config.Scaffold_Gap_Objectives (Root, "do178c", Starter);
   end;
   Check (Fusa.Config.Gap_Objectives_Exist (Root, "do178c"),
          ".fusa-do178c-objectives.json exists after Scaffold_Gap_Objectives");
   declare
      Findings   : Finding_List;
      Objectives : constant Fusa.Config.Gap_Objective_List :=
        Fusa.Config.Load_Gap_Objectives (Root, "do178c", Findings);
   begin
      Check (Natural (Objectives.Length) = 1, "the scaffolded starter objective round-trips");
      Check (To_String (Objectives.Element (1).Id) = "DO178-PLAN-1",
             "the starter objective's id round-trips");
      Check (Findings.Is_Empty, "no validation findings against a well-formed template");
   end;

   --  Scaffolding again once the file already exists is a no-op.
   Fusa.Config.Scaffold_Gap_Objectives (Root, "do178c", Fusa.Config.Gap_Objective_List'(
     Fusa.Config.Gap_Objective_Vectors.Empty_Vector));
   declare
      Findings   : Finding_List;
      Objectives : constant Fusa.Config.Gap_Objective_List :=
        Fusa.Config.Load_Gap_Objectives (Root, "do178c", Findings);
   begin
      Check (Natural (Objectives.Length) = 1,
             "re-scaffolding an existing objectives file does not overwrite it");
   end;

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Gap_Objectives_File ("iso26262"),
      "{""objectives"":[" &
      "{""id"":""ISO-1"",""title"":""t"",""clause"":""c"",""status"":""satisfied""," &
      """evidence"":[""e1""],""findings"":[""ADA001""]}," &
      "{""id"":""ISO-2"",""status"":""not-a-real-status""}," &
      "{""title"":""no id at all""}" &
      "]}");
   declare
      Findings   : Finding_List;
      Objectives : constant Fusa.Config.Gap_Objective_List :=
        Fusa.Config.Load_Gap_Objectives (Root, "iso26262", Findings);
      Errors, Warnings : Natural := 0;
   begin
      Check (Natural (Objectives.Length) = 2,
             "only the two objectives with a non-empty id are returned "
             & "(the one with no id at all is excluded, not just flagged)");
      Check (Natural (Objectives.Element (1).Evidence.Length) = 1
             and then Natural (Objectives.Element (1).Findings.Length) = 1,
             "evidence and findings arrays round-trip on a well-formed objective");
      for F of Findings loop
         case F.Severity is
            when Error   => Errors := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => null;
         end case;
      end loop;
      Check (Errors = 1, "an objective with no id produces exactly one ERROR finding");
      Check (Warnings = 1,
             "an objective with an id but an unrecognised status "
             & "produces exactly one WARNING finding, and is still returned");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Config;
