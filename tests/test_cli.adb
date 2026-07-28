with Ada.Directories;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Cli;
with Fusa.Files;
with Fusa.Config;
with Fusa.Source_Scan;
with Test_Framework; use Test_Framework;

procedure Test_Cli is
   Root : constant String := "tmp_test_cli";

   function Args (A1 : String := ""; A2 : String := ""; A3 : String := "";
                   A4 : String := ""; A5 : String := ""; A6 : String := "";
                   A7 : String := ""; A8 : String := "")
                   return String_List
   is
      L : String_List;
   begin
      if A1'Length > 0 then L.Append (A1); end if;
      if A2'Length > 0 then L.Append (A2); end if;
      if A3'Length > 0 then L.Append (A3); end if;
      if A4'Length > 0 then L.Append (A4); end if;
      if A5'Length > 0 then L.Append (A5); end if;
      if A6'Length > 0 then L.Append (A6); end if;
      if A7'Length > 0 then L.Append (A7); end if;
      if A8'Length > 0 then L.Append (A8); end if;
      return L;
   end Args;

   --  Redirects standard output to a temp file for the duration of Run,
   --  so tests can assert on what a command did (or, for --output tests,
   --  deliberately did NOT) print to stdout.
   function Run_Capturing_Stdout
     (A : String_List; Exit_Code : out Integer) return String
   is
      Capture_Path : constant String := "tmp_test_cli_stdout_capture.txt";
      Capture_File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Capture_File, Ada.Text_IO.Out_File, Capture_Path);
      Ada.Text_IO.Set_Output (Capture_File);
      Exit_Code := Fusa.Cli.Run (A);
      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.Close (Capture_File);
      declare
         Content : constant String := Fusa.Files.Read_File (Capture_Path);
      begin
         Ada.Directories.Delete_File (Capture_Path);
         return Content;
      end;
   end Run_Capturing_Stdout;
begin
   --  fusa:test REQ-001
   Check (Fusa.Cli.Run (Args ("bogus")) = Exit_Usage, "unknown command exits 2 (usage)");

   declare
      Empty : String_List;
   begin
      Check (Fusa.Cli.Run (Empty) = Exit_Usage, "no command exits 2 (usage)");
   end;

   --  fusa:test REQ-007
   Check (Fusa.Cli.Run (Args ("version")) = Exit_Ok, "version exits 0");
   --  fusa:test REQ-008
   Check (Fusa.Cli.Run (Args ("capabilities")) = Exit_Ok, "capabilities exits 0");

   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   --  Satisfies the FUSA001-004 project-structure rules so later
   --  "check --strict exits 0" assertions in this file aren't perturbed by
   --  new WARNING findings unrelated to what each assertion is testing.
   Ada.Directories.Create_Path (Root & "/.github/workflows");
   Fusa.Files.Write_File (Root & "/LICENSE", "MPL-2.0");
   Fusa.Files.Write_File (Root & "/README.md", "# Test fixture");
   Fusa.Files.Write_File (Root & "/t.gpr", "project T is end T;");
   Fusa.Files.Write_File (Root & "/.github/workflows/ci.yml", "name: CI");

   Check (Fusa.Cli.Run (Args ("check", "--dir", Root)) = Exit_Runtime,
          "check without .fusa.json exits 3 (runtime error)");
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "check with an unsupported --format exits 2 (usage)");

   --  fusa:test REQ-009
   Check (Fusa.Cli.Run (Args ("init", "--dir", Root, "--name", "t")) = Exit_Ok,
          "init exits 0 and creates config files");
   Check (Fusa.Files.Exists (Root & "/.fusa.json"), "init created .fusa.json");
   Check (Fusa.Files.Exists (Root & "/.fusa-reqs.json"), "init created .fusa-reqs.json");

   --  fusa:test REQ-010
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root)) = Exit_Ok,
          "check on a clean project exits 0");

   --  fusa:test REQ-021
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout
          (Args ("check", "--dir", Root, "--format", "json"), Exit_Code);
      Idx : constant Natural :=
        Ada.Strings.Fixed.Index (Out_Text, """projectRoot"": """);
   begin
      Check (Idx > 0
             and then Out_Text (Idx + 16) = '/',
             "projectRoot in check --format json output is an absolute path");
   end;

   Fusa.Files.Write_File
     (Root & "/src/bad.adb",
      "procedure Bad is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "exception" & ASCII.LF & "   when others =>" & ASCII.LF &
      "      null;" & ASCII.LF & "end Bad;" & ASCII.LF);

   Check (Fusa.Cli.Run (Args ("check", "--dir", Root)) = Exit_Ok,
          "check exits 0 for a WARNING-only finding without --strict");
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--strict")) = Exit_Gate_Fail,
          "check --strict exits 1 (gate fail) once a WARNING is present");

   --  fusa:test REQ-073
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--format", "html")) = Exit_Ok,
          "check --format html exits 0");

   --  fusa:test REQ-072
   --  End-to-end: check reads .fusa-dispositions.json (ruleId+file+line
   --  fallback match, since no fingerprint is computed by hand here) and
   --  an "accepted" waiver suppresses the --strict gate; "rejected" does not.
   Fusa.Files.Write_File
     (Root & "/.fusa-dispositions.json",
      "{""dispositions"":[{""ruleId"":""ADA002"",""file"":""src/bad.adb""," &
      """line"":5,""status"":""accepted""}]}");
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--strict")) = Exit_Ok,
          "check --strict exits 0 once the only WARNING is 'accepted' "
          & "via .fusa-dispositions.json");
   Fusa.Files.Write_File
     (Root & "/.fusa-dispositions.json",
      "{""dispositions"":[{""ruleId"":""ADA002"",""file"":""src/bad.adb""," &
      """line"":5,""status"":""rejected""}]}");
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--strict")) = Exit_Gate_Fail,
          "check --strict still exits 1 when the disposition is 'rejected' "
          & "(a denied waiver, not a dismissal)");
   Ada.Directories.Delete_File (Root & "/.fusa-dispositions.json");

   --  fusa:test REQ-015
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root)) = Exit_Ok,
          "report always exits 0, even with findings present");
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root, "--strict")) = Exit_Usage,
          "report rejects --strict with a usage error");
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root, "--format", "html")) = Exit_Ok,
          "report --format html exits 0");
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root, "--format", "md")) = Exit_Ok,
          "report --format md exits 0");

   --  fusa:test REQ-012
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root)) = Exit_Ok,
          "qualify passes its own known-answer tests");
   Check (Fusa.Files.Exists (Root & "/qualify-report.json"),
          "qualify writes qualify-report.json by default");
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root, "--format", "json")) = Exit_Ok,
          "qualify --format json also exits 0");
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "qualify rejects an unsupported --format with a usage error");

   --  fusa:test REQ-077
   --  section 6 MAY: hash is present, "sha256:"-prefixed, and -- since it's
   --  computed with generatedAt blanked before hashing -- byte-identical
   --  across two independent runs.
   declare
      Exit_Code1, Exit_Code2 : Integer;
      Out1 : constant String :=
        Run_Capturing_Stdout
          (Args ("qualify", "--dir", Root, "--format", "json"), Exit_Code1);
      Out2 : constant String :=
        Run_Capturing_Stdout
          (Args ("qualify", "--dir", Root, "--format", "json"), Exit_Code2);
      Idx1 : constant Natural := Ada.Strings.Fixed.Index (Out1, """hash"": ""sha256:");
      Idx2 : constant Natural := Ada.Strings.Fixed.Index (Out2, """hash"": ""sha256:");
   begin
      Check (Idx1 > 0, "qualify --format json includes a sha256:-prefixed hash field");
      Check (Idx1 > 0 and then Idx2 > 0
             and then Out1 (Idx1 .. Idx1 + 79) = Out2 (Idx2 .. Idx2 + 79),
             "qualify's hash is byte-identical across two independent runs "
             & "(reproducible per spec section 6, since generatedAt is "
             & "blanked before hashing)");
   end;

   --  fusa:test REQ-013
   Check (Fusa.Cli.Run (Args ("release", "--dir", Root)) = Exit_Ok, "release exits 0");
   Check (Fusa.Files.Exists (Root & "/sbom.json"), "release writes sbom.json");
   Check (Fusa.Cli.Run (Args ("release", "--dir", Root, "--full")) = Exit_Ok,
          "release --full exits 0");
   Check (Fusa.Files.Exists (Root & "/provenance.json"),
          "release --full writes provenance.json");
   Check (Fusa.Files.Exists (Root & "/artifact-manifest.json"),
          "release --full writes artifact-manifest.json");
   Check (Fusa.Files.Exists (Root & "/audit-pack.zip"),
          "release --full also produces audit-pack.zip as its final step");

   --  fusa:test REQ-076
   Check (not Fusa.Files.Exists (Root & "/t-0.1.0.spdx.json"),
          "release without --spdx-version does not write an SPDX document");
   Check (Fusa.Cli.Run (Args ("release", "--dir", Root, "--spdx-version", "2.3")) = Exit_Ok,
          "release --spdx-version 2.3 exits 0");
   Check (Fusa.Files.Exists (Root & "/t-0.1.0.spdx.json"),
          "release --spdx-version 2.3 writes <name>-<version>.spdx.json");
   Check (Fusa.Cli.Run
            (Args ("release", "--dir", Root, "--spdx-version", "9.9")) = Exit_Usage,
          "release rejects an unsupported --spdx-version value with a usage error");
   Check (Fusa.Cli.Run
            (Args ("release", "--dir", Root, "--spdx-version", "3.0.1")) = Exit_Usage,
          "release --spdx-version 3.0.1 is rejected as not yet implemented "
          & "(rather than silently emitting a mislabeled 2.x-shaped document)");

   --  fusa:test REQ-014
   Check (Fusa.Cli.Run (Args ("audit-pack", "--dir", Root)) = Exit_Ok, "audit-pack exits 0");
   Check (Fusa.Files.Exists (Root & "/audit-pack.zip"), "audit-pack writes audit-pack.zip");
   Check (Fusa.Cli.Run
            (Args ("audit-pack", "--dir", Root, "--output", Root & "/custom.zip")) = Exit_Ok,
          "audit-pack honours an explicit --output path");
   Check (Fusa.Files.Exists (Root & "/custom.zip"), "audit-pack wrote to the custom path");

   --  trace: no requirements yet -> zero totals, still exits 0
   --  fusa:test REQ-011
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root)) = Exit_Ok,
          "trace with no requirements file exits 0");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--format", "json")) = Exit_Ok,
          "trace --format json exits 0");
   --  fusa:test REQ-011
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--format", "html")) = Exit_Ok,
          "trace --format html exits 0");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--format", "md")) = Exit_Ok,
          "trace --format md exits 0");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "trace rejects an unsupported --format with a usage error");

   --  Add requirements and annotate the source so coverage is non-trivial.
   declare
      Reqs : Fusa.Config.Requirement_List;
      R1, R2 : Fusa.Config.Requirement;
   begin
      R1.Id := To_Unbounded_String ("REQ-001");
      R2.Id := To_Unbounded_String ("REQ-002");
      Reqs.Append (R1);
      Reqs.Append (R2);
      Fusa.Config.Save_Requirements (Root, Reqs);
   end;
   Fusa.Files.Write_File
     (Root & "/src/traced.adb",
      "procedure Traced is" & ASCII.LF &
      "   -- fusa:req REQ-001" & ASCII.LF &
      "   -- fusa:test REQ-001" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Traced;" & ASCII.LF);

   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--req-coverage", "50")) = Exit_Ok,
          "trace --req-coverage 50 passes at 50% traced (REQ-001 of 2)");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--req-coverage", "100")) = Exit_Gate_Fail,
          "trace --req-coverage 100 gate-fails while REQ-002 is untraced");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--strict")) = Exit_Gate_Fail,
          "trace --strict implies 100% thresholds and gate-fails here too");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--gaps", "--format", "json")) = Exit_Ok,
          "trace --gaps --format json exits 0");
   Check (Fusa.Cli.Run
            (Args ("trace", "--dir", Root, "--sec-tested", "10")) = Exit_Gate_Fail,
          "trace --sec-tested 10 gate-fails since no sec-test tags exist");

   --  fusa:test REQ-024
   --  spec section 1.4.1: --func-coverage gates on the percentage of public
   --  .ads function/procedure declarations carrying a directly-preceding
   --  fusa:req tag -- distinct from (and NOT implied by --strict, unlike)
   --  the requirement-level --req-coverage/--sec-tested axes.
   Fusa.Files.Write_File
     (Root & "/src/api.ads",
      "package Api is" & ASCII.LF &
      "   -- fusa:req REQ-001" & ASCII.LF &
      "   procedure Tagged_One;" & ASCII.LF &
      "   procedure Untagged_One;" & ASCII.LF &
      "end Api;" & ASCII.LF);

   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--func-coverage", "50")) = Exit_Ok,
          "trace --func-coverage 50 passes at 50% tagged (1 of 2 functions)");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--func-coverage", "100")) = Exit_Gate_Fail,
          "trace --func-coverage 100 gate-fails while Untagged_One has no tag");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--func-coverage", "abc")) = Exit_Usage,
          "trace --func-coverage abc exits 2 (usage), not a crash");

   declare
      Func_Strict_Root : constant String := "tmp_test_cli_func_strict";
   begin
      if Fusa.Files.Exists (Func_Strict_Root) then
         Ada.Directories.Delete_Tree (Func_Strict_Root);
      end if;
      Ada.Directories.Create_Path (Func_Strict_Root & "/src");
      Check (Fusa.Cli.Run
               (Args ("init", "--dir", Func_Strict_Root, "--name", "t")) = Exit_Ok,
             "func-strict fixture: init exits 0");
      declare
         Reqs : Fusa.Config.Requirement_List;
         R1   : Fusa.Config.Requirement;
      begin
         R1.Id := To_Unbounded_String ("REQ-001");
         Reqs.Append (R1);
         Fusa.Config.Save_Requirements (Func_Strict_Root, Reqs);
      end;
      Fusa.Files.Write_File
        (Func_Strict_Root & "/src/fully_traced.adb",
         "procedure Fully_Traced is" & ASCII.LF &
         "   -- fusa:req REQ-001" & ASCII.LF &
         "   -- fusa:sec-test REQ-001" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Fully_Traced;" & ASCII.LF);
      Fusa.Files.Write_File
        (Func_Strict_Root & "/src/api.ads",
         "package Api is" & ASCII.LF &
         "   procedure Untagged_One;" & ASCII.LF &
         "end Api;" & ASCII.LF);

      Check (Fusa.Cli.Run (Args ("trace", "--dir", Func_Strict_Root, "--strict")) = Exit_Ok,
             "trace --strict passes at 100% req/sec-tested coverage even "
             & "though func-coverage is 0% -- --strict does not imply "
             & "--func-coverage 100");
      Check (Fusa.Cli.Run
               (Args ("trace", "--dir", Func_Strict_Root, "--strict",
                      "--func-coverage", "100")) = Exit_Gate_Fail,
             "an explicit --func-coverage 100 alongside --strict does gate-fail");

      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("trace", "--dir", Func_Strict_Root, "--format", "json"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, """totalFunctions"": 1") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, """taggedFunctions"": 0") > 0,
                "trace --format json coverage object reports totalFunctions/"
                & "taggedFunctions");
      end;

      Ada.Directories.Delete_Tree (Func_Strict_Root);
   end;

   --  Regression: a non-numeric threshold used to crash with an unhandled
   --  CONSTRAINT_ERROR and exit 1 (colliding with Exit_Gate_Fail) instead
   --  of a clean Exit_Usage.
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--req-coverage", "abc")) = Exit_Usage,
          "trace --req-coverage abc exits 2 (usage), not a crash");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--sec-tested", "-5")) = Exit_Usage,
          "trace --sec-tested -5 exits 2 (usage), not a crash "
          & "(Natural'Value rejects negative numbers too)");

   --  Regression: boolean flags silently ignored the --flag=value form
   --  that Flag_Value-based flags already supported.
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--strict=true")) = Exit_Gate_Fail,
          "check --strict=true gates on a WARNING finding, same as bare --strict");

   --  Regression: qualify's text-format output printed the summary to
   --  stdout even when --output was given, unlike every other command.
   declare
      Exit_Code : Integer;
      Captured  : constant String :=
        Run_Capturing_Stdout
          (Args ("qualify", "--dir", Root, "--output", Root & "/q2.json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "qualify --output still exits 0");
      --  Ada.Text_IO.Create/Close on an unwritten file may itself leave a
      --  trailing line terminator, so check for absence of the actual
      --  summary content rather than requiring exactly zero bytes.
      Check (Ada.Strings.Fixed.Index (Captured, "known-answer") = 0
             and then Ada.Strings.Fixed.Index (Captured, "total,") = 0,
             "qualify (text format) prints nothing to stdout when --output is given");
      Check (Fusa.Files.Exists (Root & "/q2.json"),
             "qualify still wrote the JSON report to the given --output path");
   end;

   --  Regression: the empty equals-value form --output= was treated as if
   --  --output had never been given at all (fell through to Default).
   declare
      Exit_Code : Integer;
      Captured  : constant String :=
        Run_Capturing_Stdout (Args ("check", "--dir", Root, "--output="), Exit_Code);
   begin
      Check (Captured'Length > 0,
             "check --output= (empty value) still prints to stdout, "
             & "matching --output entirely absent");
   end;

   --  Regression: Emit_Runtime_Error's text-format branch never honoured
   --  --output, unlike its --format json branch.
   declare
      No_Cfg_Dir : constant String := Root & "/nocfg";
   begin
      Ada.Directories.Create_Path (No_Cfg_Dir);
      Check (Fusa.Cli.Run
               (Args ("check", "--dir", No_Cfg_Dir, "--output",
                      Root & "/err.txt")) = Exit_Runtime,
             "check --output on a no-config directory still exits 3");
      Check (Fusa.Files.Exists (Root & "/err.txt"),
             "the text-format runtime error was written to --output, not just stderr");
   end;

   --  Regression: an interrupted qualify run's leftover
   --  .fusa-qualify-tmp/ directory used to be scanned as real project
   --  source, producing a phantom finding at a fake location.
   declare
      Leftover_Dir : constant String := Root & "/.fusa-qualify-tmp";
   begin
      Ada.Directories.Create_Path (Leftover_Dir);
      Fusa.Files.Write_File
        (Leftover_Dir & "/fixture.adb",
         "procedure P is" & ASCII.LF &
         "   pragma Suppress (All_Checks);" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      declare
         Cfg   : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root);
         Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Root, Cfg);
         Found_Leftover : Boolean := False;
      begin
         for F of Files loop
            if F = ".fusa-qualify-tmp/fixture.adb" then
               Found_Leftover := True;
            end if;
         end loop;
         Check (not Found_Leftover,
                "a leftover .fusa-qualify-tmp/ directory is excluded from source scans");
      end;
      Ada.Directories.Delete_Tree (Leftover_Dir);
   end;

   Ada.Directories.Delete_Tree (Root);

   --  init variations: positional name, --force overwrite, missing name.
   declare
      Root2 : constant String := "tmp_test_cli_init";
   begin
      if Ada.Directories.Exists (Root2) then
         Ada.Directories.Delete_Tree (Root2);
      end if;
      Ada.Directories.Create_Path (Root2);

      Check (Fusa.Cli.Run (Args ("init", "--dir", Root2, "positional-name")) = Exit_Ok,
             "init accepts a positional project name");
      Check (Fusa.Cli.Run (Args ("init", "--dir", Root2, "--name", "ignored")) = Exit_Ok,
             "a second init without --force still exits 0 (name is still required, "
             & "but the existing config file is left alone)");

      declare
         Unchanged : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root2);
      begin
         Check (To_String (Unchanged.Name) = "positional-name",
                "without --force the original config was not overwritten");
      end;

      Check (Fusa.Cli.Run
               (Args ("init", "--dir", Root2, "--force", "--name", "renamed",
                      "--standard", "do178c")) = Exit_Ok,
             "init --force overwrites an existing config");

      declare
         Cfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root2);
      begin
         Check (To_String (Cfg.Name) = "renamed", "--force actually overwrote the name");
      end;

      Ada.Directories.Delete_Tree (Root2);
   end;

   declare
      Root3 : constant String := "tmp_test_cli_noname";
   begin
      if Ada.Directories.Exists (Root3) then
         Ada.Directories.Delete_Tree (Root3);
      end if;
      Ada.Directories.Create_Path (Root3);
      Check (Fusa.Cli.Run (Args ("init", "--dir", Root3)) = Exit_Usage,
             "init with no name available and no TTY exits 2 (usage)");
      Ada.Directories.Delete_Tree (Root3);
   end;

   --  fusa:test REQ-075
   declare
      Root4 : constant String := "tmp_test_cli_migrate";
   begin
      if Ada.Directories.Exists (Root4) then
         Ada.Directories.Delete_Tree (Root4);
      end if;
      Ada.Directories.Create_Path (Root4);
      Fusa.Files.Write_File
        (Root4 & "/.adafusa.json",
         "{""configVersion"":""1.0"",""project"":{""name"":""legacyproj""}," &
         """standard"":""generic""}");
      Fusa.Files.Write_File
        (Root4 & "/.adafusa-reqs.json",
         "{""requirements"":[{""id"":""REQ-X"",""title"":""t"",""text"":""x""," &
         """level"":""SW""}]}");

      Check (Fusa.Cli.Run (Args ("init", "--dir", Root4, "--migrate")) = Exit_Ok,
             "init --migrate exits 0");
      Check (Fusa.Files.Exists (Root4 & "/.fusa.json")
             and then not Fusa.Files.Exists (Root4 & "/.adafusa.json"),
             "init --migrate renames .adafusa.json to the canonical name");
      Check (Fusa.Files.Exists (Root4 & "/.fusa-reqs.json")
             and then not Fusa.Files.Exists (Root4 & "/.adafusa-reqs.json"),
             "init --migrate renames .adafusa-reqs.json to the canonical name");

      declare
         Cfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Root4);
      begin
         Check (To_String (Cfg.Name) = "legacyproj",
                "init --migrate preserves the legacy config's content, not just its name");
      end;

      Check (Fusa.Cli.Run (Args ("init", "--dir", Root4, "--migrate")) = Exit_Ok,
             "init --migrate is a harmless no-op (still exits 0) once nothing legacy remains");

      Ada.Directories.Delete_Tree (Root4);
   end;
end Test_Cli;
