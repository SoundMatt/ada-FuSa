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

   --  fusa:test REQ-051
   Check (not Fusa.Config.Exists (Root), "no config initially");

   --  fusa:test REQ-050
   --  fusa:test REQ-052
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

   --  fusa:test REQ-053
   Check (not Fusa.Config.Requirements_Exist (Root), "no requirements file initially");

   --  Requirements + duplicate-id detection
   --  fusa:test REQ-054
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
   Check (Fusa.Config.Requirements_Exist (Root),
          "Requirements_Exist is true once Save_Requirements has written the file");

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
   Fusa.Config.Scaffold_Hara (Root, "iso26262");
   Check (Fusa.Config.Hara_Exists (Root), ".fusa-hara.json exists after Scaffold_Hara");
   declare
      Findings : Finding_List;
      Empty    : constant Fusa.Config.Hara_Document := Fusa.Config.Load_Hara (Root, Findings);
   begin
      Check (Natural (Empty.Hazards.Length) = 0,
             "a freshly scaffolded hara template has no hazards");
      Check (Natural (Empty.Operational_Situations.Length) = 0
             and then Natural (Empty.Safety_Goals.Length) = 0,
             "nor any operational situations or safety goals");
      Check (Natural (Findings.Length) = 0, "no validation findings against an empty template");
   end;

   --  fusa:test REQ-082
   --  ASIL determination (S3 x E4 x C3 -> ASIL-D per ISO 26262-3 Table 4)
   --  and referential integrity are exercised directly against
   --  Determine_Asil and a hand-built document in test_engine.adb; this
   --  is the CLI-adjacent Load_Hara test for id-required-ness and
   --  completeness warnings.
   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Hara_File,
      "{""hazards"":[" &
      "{""id"":""HAZ-001"",""description"":""h"",""situations"":[""OS-001""]," &
      """risk"":{""severity"":""S3"",""exposure"":""E4"",""controllability"":""C3""}," &
      """safetyGoals"":[""SG-001""]}," &
      "{""id"":""HAZ-002"",""description"":""incomplete""," &
      """risk"":{""severity"":""S1"",""exposure"":""E1"",""controllability"":""C1""}}," &
      "{""description"":""no id at all""}" &
      "]," &
      """operationalSituations"":[{""id"":""OS-001"",""description"":""os""}]," &
      """safetyGoals"":[{""id"":""SG-001"",""description"":""sg""," &
      """hazards"":[""HAZ-001""],""asil"":""ASIL-D"",""fssrRefs"":[""REQ-999""]}]}");
   declare
      Findings : Finding_List;
      Doc      : constant Fusa.Config.Hara_Document := Fusa.Config.Load_Hara (Root, Findings);
      Errors, Warnings : Natural := 0;
   begin
      Check (Natural (Doc.Hazards.Length) = 2,
             "only the two hazards with a non-empty id are returned "
             & "(the one with no id at all is excluded, not just flagged)");
      Check (To_String (Doc.Hazards.Element (1).Risk.Asil) = "ASIL-D",
             "risk.asil is derived from severity x exposure x controllability "
             & "(S3/E4/C3 -> ASIL-D per ISO 26262-3 Table 4), not accepted verbatim");
      for F of Findings loop
         case F.Severity is
            when Error   => Errors := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => null;
         end case;
      end loop;
      --  HAZ-001: fully valid, no findings. HAZ-002: valid risk but no
      --  situations/safetyGoals -> 1 completeness WARNING. no-id entry
      --  -> 1 ERROR. SG-001's fssrRefs REQ-999 doesn't resolve into
      --  .fusa-reqs.json -> 1 more WARNING (referential integrity).
      Check (Errors = 1, "a hazard with no id produces exactly one ERROR finding");
      Check (Warnings = 2,
             "a hazard missing situations/safetyGoals produces one WARNING, "
             & "and a fssrRefs id that doesn't resolve into .fusa-reqs.json "
             & "produces another");
   end;

   --  fusa:test REQ-083
   Check (not Fusa.Config.Tara_Exists (Root), "no .fusa-tara.json initially");
   Fusa.Config.Scaffold_Tara (Root);
   Check (Fusa.Config.Tara_Exists (Root), ".fusa-tara.json exists after Scaffold_Tara");

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Tara_File,
      "{""threats"":[" &
      "{""id"":""THR-001"",""asset"":""a"",""threat"":""t""," &
      """attackVector"":""av"",""attackFeasibility"":""high""," &
      """impact"":{""safety"":""major"",""financial"":""negligible""," &
      """operational"":""negligible"",""privacy"":""negligible""}," &
      """treatment"":""tr"",""mitigations"":[""m1"",""m2""]}," &
      "{""threat"":""no id or asset at all""}" &
      "]}");
   declare
      Findings : Finding_List;
      Doc      : constant Fusa.Config.Tara_Document := Fusa.Config.Load_Tara (Root, Findings);
   begin
      Check (Natural (Doc.Threats.Length) = 1,
             "only the threat with a non-empty id and asset is returned");
      Check (Natural (Doc.Threats.Element (1).Mitigations.Length) = 2,
             "the mitigations array round-trips with both entries");
      Check (To_String (Doc.Threats.Element (1).Risk) = "high",
             "risk is derived from attackFeasibility x the highest SFOP impact "
             & "level (high feasibility, major-or-lower impact -> high, per the "
             & "section 9.2 combination table), not accepted verbatim -- there "
             & "is no ""risk"" field in the input at all");
      Check (Natural (Findings.Length) = 1
             and then Findings.Element (1).Severity = Error,
             "a threat with no id or asset produces exactly one ERROR finding");
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

   --  fusa:test REQ-106
   Check (not Fusa.Config.Fmea_Exists (Root), "no .fusa-fmea.json initially");
   Fusa.Config.Scaffold_Fmea (Root);
   Check (Fusa.Config.Fmea_Exists (Root), ".fusa-fmea.json exists after Scaffold_Fmea");

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Fmea_File,
      "{""entries"":[" &
      "{""id"":""FMEA-001"",""item"":""i"",""file"":""src/x.adb""," &
      """failureMode"":""fm"",""effect"":""ef""," &
      """severity"":8,""occurrence"":3,""detection"":4," &
      """actionPriority"":""high""," &
      """mitigations"":[""add overflow check"",""add unit test""]," &
      """requirementIds"":[""REQ-1"",""REQ-2""]}," &
      "{""id"":""FMEA-002"",""item"":""i"",""file"":""src/y.adb""," &
      """failureMode"":""fm"",""effect"":""ef""," &
      """severity"":11,""occurrence"":2,""detection"":2}," &
      "{""id"":""FMEA-003"",""item"":""i"",""file"":""src/z.adb""," &
      """failureMode"":""fm"",""effect"":""ef""," &
      """severity"":5,""occurrence"":5,""detection"":5,""rpn"":999}," &
      "{""title"":""no id at all""}" &
      "]}");
   declare
      Findings : Finding_List;
      Doc      : constant Fusa.Config.Fmea_Document := Fusa.Config.Load_Fmea (Root, Findings);
      Entries  : Fusa.Config.Fmea_Entry_List renames Doc.Entries;
      Errors, Warnings : Natural := 0;
   begin
      Check (Natural (Entries.Length) = 3,
             "only the three entries with a non-empty id are returned");
      Check (Entries.Element (1).Rpn = 96,
             "RPN is computed as severity*occurrence*detection when not given (8*3*4=96)");
      Check (Natural (Entries.Element (1).Mitigations.Length) = 2,
             "the mitigations array round-trips with both entries");
      Check (To_String (Entries.Element (1).Action_Priority) = "high",
             "actionPriority round-trips");
      Check (Natural (Entries.Element (1).Requirement_Ids.Length) = 2,
             "requirementIds round-trips with both entries");
      Check (Entries.Element (2).Severity = 0,
             "a severity outside 1..10 is treated as invalid (0), not clamped or accepted");
      Check (Entries.Element (2).Rpn = 0,
             "RPN is not computed when any of the three ratings is invalid");
      Check (Entries.Element (3).Rpn = 999,
             "an explicit rpn is preserved verbatim even when it disagrees with "
             & "severity*occurrence*detection (5*5*5=125)");
      Check (To_String (Doc.Rating_Scale) = "aiag-vda-2019",
             "ratingScale is set once any entry emits occurrence/detection "
             & "(section 9.2 MUST)");
      for F of Findings loop
         case F.Severity is
            when Error   => Errors := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => null;
         end case;
      end loop;
      Check (Errors = 1, "an entry with no id produces exactly one ERROR finding");
      Check (Warnings = 2,
             "the out-of-range rating and the rpn mismatch each produce their own "
             & "WARNING finding (2 total) -- none of the three surviving entries "
             & "is missing item/file/failureMode/effect, so FMEA004 never fires here");
   end;

   --  Regression: "file" is now a MUST field (was entirely absent from
   --  the old schema) -- an entry missing it (or item/failureMode/
   --  effect) must be flagged, not silently accepted.
   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Fmea_File,
      "{""entries"":[{""id"":""FMEA-INCOMPLETE""}]}");
   declare
      Findings : Finding_List;
      Doc      : constant Fusa.Config.Fmea_Document := Fusa.Config.Load_Fmea (Root, Findings);
      Fmea004_Hits : Natural := 0;
   begin
      Check (Natural (Doc.Entries.Length) = 1,
             "the entry is still returned (id alone is MUST; the rest is only WARNING)");
      for F of Findings loop
         if To_String (F.Rule_Id) = "FMEA004" then
            Fmea004_Hits := Fmea004_Hits + 1;
         end if;
      end loop;
      Check (Fmea004_Hits = 1,
             "FMEA004 fires once for an entry missing item/file/failureMode/effect");
   end;

   --  fusa:test REQ-107
   Check (not Fusa.Config.Safety_Case_Exists (Root), "no .fusa-safety-case.json initially");
   Fusa.Config.Scaffold_Safety_Case (Root);
   Check (Fusa.Config.Safety_Case_Exists (Root),
          ".fusa-safety-case.json exists after Scaffold_Safety_Case");
   declare
      Findings  : Finding_List;
      Root_Goal : Unbounded_String;
      Empty     : constant Fusa.Config.Gsn_Node_List :=
        Fusa.Config.Load_Safety_Case (Root, Findings, Root_Goal);
   begin
      Check (Natural (Empty.Length) = 0, "a freshly scaffolded safety case has no nodes");
      Check (Natural (Findings.Length) = 0, "no validation findings against an empty template");
   end;

   Fusa.Files.Write_File
     (Root & "/" & Fusa.Config.Safety_Case_File,
      "{""rootGoal"":""G1"",""nodes"":[" &
      "{""id"":""G1"",""type"":""goal"",""text"":""top"",""supportedBy"":[""S1""]}," &
      "{""id"":""S1"",""type"":""bogus-type"",""text"":""strat"",""supportedBy"":[""NOPE""]}," &
      "{""text"":""no id at all""}" &
      "]}");
   declare
      Findings  : Finding_List;
      Root_Goal : Unbounded_String;
      Nodes     : constant Fusa.Config.Gsn_Node_List :=
        Fusa.Config.Load_Safety_Case (Root, Findings, Root_Goal);
      Errors, Warnings : Natural := 0;
   begin
      Check (Natural (Nodes.Length) = 2,
             "only the two nodes with a non-empty id are returned");
      Check (To_String (Root_Goal) = "G1", "rootGoal round-trips verbatim");
      for F of Findings loop
         case F.Severity is
            when Error   => Errors := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => null;
         end case;
      end loop;
      Check (Errors = 2,
             "the missing-id entry and S1's dangling supportedBy reference to ""NOPE"" "
             & "each produce their own ERROR finding (2 total)");
      Check (Warnings = 1,
             "S1's unrecognised type ""bogus-type"" produces exactly one WARNING finding, "
             & "and S1 is still returned rather than excluded");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Config;
