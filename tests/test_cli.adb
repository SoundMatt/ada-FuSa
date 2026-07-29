with Ada.Directories;
with GNAT.OS_Lib;
with Ada.Text_IO;
with Ada.Strings.Fixed;
with Interfaces.C;
with Interfaces.C.Strings;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Cli;
with Fusa.Files;
with Fusa.Config;
with Fusa.Source_Scan;
with Fusa.Attestation;
with Fusa.Json;
use type Fusa.Json.Value_Access;
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
   --  fusa:test REQ-037
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
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("capabilities"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index
               (Out_Text, """kind"": ""capabilities""") > 0,
             "capabilities JSON output has kind = ""capabilities""");
      Check (Ada.Strings.Fixed.Index (Out_Text, """specVersion"": """) > 0,
             "capabilities JSON output includes specVersion");
      Check (Ada.Strings.Fixed.Index (Out_Text, """commands"":") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """check""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """trace""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """qualify""") > 0,
             "capabilities JSON output lists commands including check/"
             & "trace/qualify");
      Check (Ada.Strings.Fixed.Index (Out_Text, """formats"":") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """sarif""") > 0,
             "capabilities JSON output lists per-command formats "
             & "including sarif");
   end;

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
   --  Regression: standard is just as required as name (section 9.1
   --  MUST) -- non-interactively omitting it must exit 2, not silently
   --  default to "generic".
   Check (Fusa.Cli.Run (Args ("init", "--dir", Root, "--name", "t")) = Exit_Usage,
          "init requires --standard, not just --name, when not run "
          & "interactively");
   Check (not Fusa.Files.Exists (Root & "/.fusa.json"),
          "init does not write a placeholder .fusa.json when --standard "
          & "is missing non-interactively");
   Check (Fusa.Cli.Run
            (Args ("init", "--dir", Root, "--name", "t", "--standard", "generic")) = Exit_Ok,
          "init exits 0 and creates config files once both --name and "
          & "--standard are given");
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
      --  Regression: an earlier version of this assertion only checked
      --  the value's *shape* (leading '/'), which would still pass for
      --  an absolute path to the wrong directory entirely. Assert the
      --  value actually resolves to Root, and that the SHOULD "standard"
      --  field carries the real configured value, not just any string.
      Check (Ada.Strings.Fixed.Index (Out_Text, "/" & Root & """") > 0,
             "projectRoot in check --format json output resolves to the "
             & "actual project directory, not merely some absolute path");
      Check (Ada.Strings.Fixed.Index
               (Out_Text, """standard"": ""generic""") > 0,
             "standard in check --format json output carries the "
             & "project's actual configured standard (""generic""), not "
             & "just any non-blank string");
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

   --  Regression: a file-scoped disposition (a "file" given, "line"
   --  omitted) used to match EVERY finding for that rule project-wide,
   --  not just findings in the named file, because Matches's
   --  "E.Line = 0 or else (...)" short-circuited to True without ever
   --  consulting E.File.
   --  fusa:test REQ-072
   declare
      Disp_Root : constant String := "tmp_test_cli_disposition_scope";
   begin
      if Ada.Directories.Exists (Disp_Root) then
         Ada.Directories.Delete_Tree (Disp_Root);
      end if;
      Ada.Directories.Create_Path (Disp_Root & "/src");
      Fusa.Files.Write_File
        (Disp_Root & "/.fusa.json", "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Disp_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Disp_Root & "/src/a.adb",
         "procedure A is" & ASCII.LF & "   -- TODO fix this" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end A;" & ASCII.LF);
      Fusa.Files.Write_File
        (Disp_Root & "/src/b.adb",
         "procedure B is" & ASCII.LF & "   -- TODO fix this too" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end B;" & ASCII.LF);
      Fusa.Files.Write_File
        (Disp_Root & "/.fusa-dispositions.json",
         "{""dispositions"":[{""ruleId"":""ADA007"",""file"":""src/a.adb""," &
         """status"":""accepted""}]}");
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("check", "--dir", Disp_Root, "--format", "json"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Json, """file"": ""src/a.adb""") > 0
                and then Ada.Strings.Fixed.Index (Out_Json, """disposition"": ""accepted""") > 0,
                "a file-scoped disposition (no line) accepts the ADA007 finding "
                & "in src/a.adb, the file it actually names");
         Check (Ada.Strings.Fixed.Index (Out_Json, """file"": ""src/b.adb""") > 0,
                "src/b.adb's ADA007 finding is still present in the output");
      end;
      Check (Fusa.Cli.Run (Args ("check", "--dir", Disp_Root, "--strict")) = Exit_Gate_Fail,
             "check --strict still gate-fails on src/b.adb's ADA007 WARNING -- a "
             & "file-scoped disposition naming only src/a.adb must NOT also waive "
             & "the same rule in every other file project-wide");
      Ada.Directories.Delete_Tree (Disp_Root);
   end;

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
   --  Regression: qualify --format json used to omit the section 3.2
   --  report-extension fields entirely -- projectRoot is MUST.
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("qualify", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """projectRoot"": """) > 0,
             "qualify --format json now includes the MUST projectRoot field");
      Check (Ada.Strings.Fixed.Index (Out_Text, "/" & Root & """") > 0,
             "qualify --format json's projectRoot resolves to the actual "
             & "project directory");
      Check (Ada.Strings.Fixed.Index
               (Out_Text, """standard"": ""generic""") > 0,
             "qualify --format json's standard carries the project's "
             & "actual configured value (""generic"")");
   end;
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "qualify rejects an unsupported --format with a usage error");

   --  Regression: the FUSA00x known-answer case used to run FUSA001-004
   --  against the real --dir being qualified, PASSing only when none of
   --  them fired -- i.e. only when that project already happened to have
   --  a LICENSE, README, *.gpr, and .github/workflows (exactly why Root
   --  above was seeded with all four at fixture setup, purely to make
   --  the self-test pass). A project missing any of those markers --
   --  which is completely normal, e.g. right after `adafusa init` --
   --  would report qualify as FAILED even though nothing about the tool
   --  itself is broken. It must now use an internal scratch directory
   --  that deliberately has none of the four markers, so qualify passes
   --  (and correctly demonstrates FUSA001-004 firing) regardless of
   --  whatever project it's actually run against.
   declare
      Marker_Free_Root : constant String := "tmp_test_cli_qualify_no_markers";
   begin
      if Ada.Directories.Exists (Marker_Free_Root) then
         Ada.Directories.Delete_Tree (Marker_Free_Root);
      end if;
      Ada.Directories.Create_Path (Marker_Free_Root & "/src");
      Fusa.Files.Write_File
        (Marker_Free_Root & "/.fusa.json",
         "{""project"":{""name"":""t"",""version"":""0.1.0""},""standard"":""generic""}");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("qualify", "--dir", Marker_Free_Root, "--format", "json"), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok,
                "qualify still exits 0 against a project with no LICENSE, README, "
                & "*.gpr, or .github/workflows of its own -- the FUSA00x "
                & "known-answer case no longer depends on the qualified "
                & "project's own state");
         Check (Ada.Strings.Fixed.Index (Out_Text, """name"": ""rule-FUSA001-known-answer""") > 0
                and then Ada.Strings.Fixed.Index
                  (Out_Text, """name"": ""rule-FUSA004-known-answer""") > 0,
                "FUSA001 and FUSA004 are now reported as individual, named "
                & "known-answer cases (not one combined ""FUSA00x"" bucket), "
                & "giving real positive-detection coverage per rule");
      end;
      Ada.Directories.Delete_Tree (Marker_Free_Root);
   end;

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

   --  Regression: release --full used to print "not yet implemented" and
   --  skip fmea/boundary entirely, even though both are fully shipped
   --  commands. boundary needs no input sidecar, so it writes real
   --  content on the very first --full run; fmea's own scaffold-on-
   --  first-run behaviour (no .fusa-fmea.json yet) means this first run
   --  only creates the *input* sidecar, not a fmea.json report -- that's
   --  fmea's existing, unrelated first-run contract, not a --full bug.
   --  fusa:test REQ-013
   Check (Fusa.Files.Exists (Root & "/boundary.dot"),
          "release --full now writes boundary.dot (boundary is wired in, not skipped)");
   Check (Fusa.Files.Exists (Root & "/.fusa-fmea.json"),
          "release --full's first run scaffolds .fusa-fmea.json via fmea's "
          & "own template-on-first-run behaviour (fmea is wired in, not skipped)");
   --  Delete the sidecar scaffold immediately: it's a side effect of this
   --  release --full run, not deliberately-seeded fixture state, and a
   --  later test (REQ-106's fmea block) asserts .fusa-fmea.json is absent
   --  before fmea's own first run against this same shared Root.
   Ada.Directories.Delete_File (Root & "/.fusa-fmea.json");

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

   --  Regression: audit-pack used to bundle a fixed 7-file allowlist that
   --  missed most of the tool's own evidence artifacts. boundary.dot
   --  exists in Root by this point (release --full wrote it above) but
   --  was never one of the original 7 -- its filename (stored uncompressed
   --  in the zip's local file headers by this hand-rolled writer) must
   --  now appear in the archive's raw bytes.
   Check (Ada.Strings.Fixed.Index
            (Fusa.Files.Read_File (Root & "/audit-pack.zip"), "boundary.dot") > 0,
          "audit-pack's expanded allowlist bundles boundary.dot, which was "
          & "never one of the original 7 hardcoded filenames");

   --  fusa:test REQ-076 / REQ-014: project.name/version are free-text
   --  JSON string fields with no path-safety validation of their own --
   --  a crafted "../.." name must not let release --spdx-version write,
   --  or audit-pack read, outside the project/output directory.
   declare
      Trav_Root : constant String := "tmp_test_cli_path_traversal";
      Outside_File : constant String := "tmp_test_cli_traversal_outside.txt";
   begin
      if Ada.Directories.Exists (Trav_Root) then
         Ada.Directories.Delete_Tree (Trav_Root);
      end if;
      Ada.Directories.Create_Path (Trav_Root);
      Fusa.Files.Write_File
        (Outside_File, "should never be read or overwritten");
      Fusa.Files.Write_File
        (Trav_Root & "/.fusa.json",
         "{""project"":{""name"":""../../../../tmp/pwned""," &
           """version"":""1.0""},""standard"":""generic""}");
      Check (Fusa.Cli.Run
               (Args ("release", "--dir", Trav_Root, "--spdx-version", "2.3"))
               = Exit_Runtime,
             "release --spdx-version refuses to write the SPDX document "
             & "when project.name/version would resolve outside --output-dir "
             & "(exit 3, not a silent escape)");
      Check (not Fusa.Files.Exists ("/tmp/pwned-1.0.spdx.json"),
             "no file was actually written outside the project directory");

      --  Same escape attempt, but via a name/version pair crafted to
      --  resolve exactly onto a real file one level above Trav_Root, to
      --  prove audit-pack's read side is guarded too (not just release's
      --  write side).
      Fusa.Files.Write_File
        (Trav_Root & "/.fusa.json",
         "{""project"":{""name"":"".."",""version"":""" &
           Outside_File & """},""standard"":""generic""}");
      Check (Fusa.Cli.Run
               (Args ("audit-pack", "--dir", Trav_Root, "--output",
                      Trav_Root & "/pack.zip")) = Exit_Ok,
             "audit-pack still exits 0 (missing/escaping files are silently "
             & "skipped, same as any other absent evidence artifact)");
      Check (Ada.Strings.Fixed.Index
               (Fusa.Files.Read_File (Trav_Root & "/pack.zip"),
                "should never be read") = 0,
             "audit-pack did not bundle a file outside the project "
             & "directory even though the traversal path resolves to a "
             & "real, readable file");
      Ada.Directories.Delete_Tree (Trav_Root);
      Ada.Directories.Delete_File (Outside_File);
   end;

   --  Regression (fusa#96): Fusa.Files.Is_Within compared Path against
   --  the literal, un-normalised Root string, so the DEFAULT --dir value
   --  "." (used whenever no --dir flag is given at all -- by far the
   --  most common real invocation) never matched anything Join produced,
   --  because Join normalises the leading "." away. sourceDirs scanning,
   --  audit-pack bundling, and release --spdx-version's output-path
   --  safety check all silently treated every real, in-tree path as
   --  "outside" the project root -- a false-clean result (zero findings,
   --  exit 0). Every other test in this file passes an explicit --dir
   --  (Root, an already-relative-but-not-"." directory name), which
   --  never exercised this. This block genuinely changes the process's
   --  current directory and omits --dir entirely, which is exactly the
   --  invocation style that was silently broken.
   --  fusa:test REQ-117
   declare
      Rel_Root  : constant String := "tmp_test_cli_relative_dir";
      Saved_Cwd : constant String := Ada.Directories.Current_Directory;
   begin
      if Ada.Directories.Exists (Rel_Root) then
         Ada.Directories.Delete_Tree (Rel_Root);
      end if;
      Ada.Directories.Create_Path (Rel_Root & "/src");
      Fusa.Files.Write_File
        (Rel_Root & "/.fusa.json",
         "{""configVersion"":""1.0"",""project"":{""name"":""relrepro""," &
           """version"":""0.1.0""},""standard"":""generic""," &
           """sourceDirs"":[""src""]}");
      Fusa.Files.Write_File (Rel_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Rel_Root & "/src/bad.adb",
         "procedure Bad is" & ASCII.LF &
         "   pragma Suppress (All_Checks);" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Bad;" & ASCII.LF);

      Ada.Directories.Set_Directory (Rel_Root);
      declare
         Exit_Code : Integer;
         Out1      : constant String :=
           Run_Capturing_Stdout (Args ("check", "--format", "json"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out1, "ADA001") > 0,
                "check with the DEFAULT (no --dir) relative root actually "
                & "scans sourceDirs and finds the ADA001 finding, instead "
                & "of silently reporting zero findings via a false-clean "
                & "exit 0");
      end;

      Check (Fusa.Cli.Run (Args ("release", "--spdx-version", "2.3")) = Exit_Ok,
             "release --spdx-version with the default relative root exits 0 "
             & "instead of erroring out over a spurious path-escape check");
      Check (Fusa.Files.Exists ("relrepro-0.1.0.spdx.json"),
             "release --spdx-version with the default relative root "
             & "actually writes the SPDX document");

      Check (Fusa.Cli.Run (Args ("audit-pack")) = Exit_Ok,
             "audit-pack with the default relative root exits 0");
      Check (Ada.Strings.Fixed.Index
               (Fusa.Files.Read_File ("audit-pack.zip"), ".fusa.json") > 0,
             "audit-pack with the default relative root actually bundles "
             & "the project's real evidence files, not just an empty "
             & "manifest.json");

      Ada.Directories.Set_Directory (Saved_Cwd);
      Ada.Directories.Delete_Tree (Rel_Root);
   end;

   --  fusa:test REQ-081
   Check (Fusa.Cli.Run (Args ("comp", "--dir", Root)) = Exit_Ok,
          "comp with the default threshold (10) exits 0 for this fixture's "
          & "low-complexity functions");
   Check (Fusa.Cli.Run (Args ("comp", "--dir", Root, "--threshold", "0")) = Exit_Usage,
          "comp rejects a --threshold of 0 as a usage error");
   Check (Fusa.Cli.Run (Args ("comp", "--dir", Root, "--dal", "DAL-Z")) = Exit_Usage,
          "comp rejects an unrecognised --dal value as a usage error");

   --  V(G) = 1 + 4 (if + 3 elsifs) = 5, which exceeds DAL-A's threshold of
   --  4 but not the default DAL-B threshold of 10.
   Fusa.Files.Write_File
     (Root & "/src/complex5.adb",
      "procedure Complex5 (A, B, C, D : Boolean) is" & ASCII.LF &
      "begin" & ASCII.LF &
      "   if A then null;" & ASCII.LF &
      "   elsif B then null;" & ASCII.LF &
      "   elsif C then null;" & ASCII.LF &
      "   elsif D then null;" & ASCII.LF &
      "   end if;" & ASCII.LF &
      "end Complex5;" & ASCII.LF);
   Check (Fusa.Cli.Run (Args ("comp", "--dir", Root)) = Exit_Ok,
          "comp with the default threshold (10) still exits 0 once "
          & "complex5.adb (V(G)=5) is added");
   Check (Fusa.Cli.Run (Args ("comp", "--dir", Root, "--dal", "DAL-A")) = Exit_Gate_Fail,
          "comp --dal DAL-A (threshold 4) gate-fails once complex5.adb's "
          & "V(G)=5 exceeds that low threshold");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout
          (Args ("comp", "--dir", Root, "--dal", "DAL-A", "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """threshold"": 4") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """dal"": ""DAL-A""") > 0,
             "comp --format json reports the DAL-derived threshold and the dal field");
   end;

   --  fusa:test REQ-084
   Check (not Fusa.Files.Exists (Root & "/.fusa-hara.json"), "no .fusa-hara.json initially");
   --  Regression (section 1.2.5 MUST): a hara run against a missing
   --  input file with no --init must exit non-zero, not silently
   --  report zero hazards as if the analysis were complete -- under
   --  --format json this must ALSO still be a real JSON document (an
   --  "error" object), not a stray plain-text line.
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("hara", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Runtime,
             "hara --format json on a missing .fusa-hara.json with no --init "
             & "exits 3 (runtime error), not 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, """kind"": ""hara-report""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """error"":") > 0,
             "the missing-input error is still a real JSON document with an "
             & """error"" object, not a stray plain-text line");
      Check (not Fusa.Files.Exists (Root & "/.fusa-hara.json"),
             "no file was scaffolded as a side effect of the error path");
   end;
   Check (Fusa.Cli.Run (Args ("hara", "--dir", Root, "--init")) = Exit_Ok,
          "hara --init scaffolds a template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-hara.json"), "hara --init created .fusa-hara.json");
   Check (Fusa.Cli.Run (Args ("hara", "--dir", Root)) = Exit_Ok,
          "hara against the (still-empty) scaffolded template exits 0 "
          & "(no --init needed once the file exists)");
   --  Regression: kind used to be the bare command name "hara"; §1.2.5/
   --  §9.2 require the report-document form "hara-report".
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("hara", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """kind"": ""hara-report""") > 0,
             "hara --format json reports kind ""hara-report"", not the bare "
             & "command name ""hara""");
      Check (Ada.Strings.Fixed.Index (Out_Text, """completeness"":") > 0,
             "hara --format json includes the section 1.2.5 completeness block");
   end;
   Fusa.Files.Write_File
     (Root & "/.fusa-hara.json", "{""hazards"":[{""description"":""no id""}]}");
   Check (Fusa.Cli.Run (Args ("hara", "--dir", Root)) = Exit_Gate_Fail,
          "hara gate-fails once a hazard with no id is present (ERROR finding)");

   --  fusa:test REQ-119 / REQ-120: section 1.6.1/1.6.2 detection and
   --  attestation, exercised end-to-end through the hara command (the
   --  underlying Rule A/B/attestation logic itself is unit-tested in
   --  test_stub_detect.adb; this locks in that hara actually wires it in).
   declare
      Stub_Root : constant String := "tmp_test_cli_stub_hara";
      Many      : Unbounded_String := Null_Unbounded_String;

      function Hazards_Json (Descriptions : String) return String is
        ("{""hazards"":[" & Descriptions & "],""safetyGoals"":[]}");

      function One_Hazard (Id, Desc : String) return String is
        ("{""id"":""" & Id & """,""description"":""" & Desc &
           """,""situations"":[],""risk"":{""severity"":""S1""," &
           """exposure"":""E1"",""controllability"":""C1""}," &
           """safetyGoals"":[]}");

      function Hazards_With_Attestation
        (Descriptions, Hash : String) return String is
        ("{""hazards"":[" & Descriptions & "],""safetyGoals"":[]," &
           """attestation"":{""status"":""reviewed""," &
           """implementationAuthor"":""auto""," &
           """independentReviewer"":""Jane Doe <jane@example.com>""," &
           """reviewedAt"":""2026-07-28T00:00:00Z""," &
           """contentHash"":""" & Hash & """}}");
   begin
      if Ada.Directories.Exists (Stub_Root) then
         Ada.Directories.Delete_Tree (Stub_Root);
      end if;
      Ada.Directories.Create_Path (Stub_Root);
      Fusa.Files.Write_File
        (Stub_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""iso26262""}");
      Fusa.Files.Write_File
        (Stub_Root & "/.fusa-hara.json",
         Hazards_Json (One_Hazard ("H1", "[describe hazard]")));
      Check (Fusa.Cli.Run (Args ("hara", "--dir", Stub_Root)) = Exit_Gate_Fail,
             "hara gate-fails on a Rule A (FUSA-STUB001) placeholder hazard "
             & "description, even though it's a WARNING-free document "
             & "otherwise -- disposition-suppressible only, always-on");

      --  Regression: unlike Rule B, a fresh/independent/hash-matching
      --  attestation must NOT suppress Rule A -- section 1.6.1 only
      --  wires Attestation_Suppresses into Check_Blanket_Fallback, never
      --  into Check_Placeholder. A placeholder value is still a
      --  placeholder no matter who reviewed it.
      declare
         Root_Val : constant Fusa.Json.Value_Access :=
           Fusa.Json.Parse
             (Fusa.Files.Read_File (Stub_Root & "/.fusa-hara.json"));
         Hash : constant String :=
           Fusa.Attestation.Canonical_Content_Hash (Root_Val);
      begin
         Fusa.Files.Write_File
           (Stub_Root & "/.fusa-hara.json",
            Hazards_With_Attestation
              (One_Hazard ("H1", "[describe hazard]"), Hash));
      end;
      Check (Fusa.Cli.Run
               (Args ("hara", "--dir", Stub_Root, "--require-attestation")) =
               Exit_Gate_Fail,
             "a fresh, independently-reviewed, hash-matching attestation "
             & "does NOT suppress Rule A (FUSA-STUB001) -- placeholder "
             & "descriptions gate-fail regardless of attestation, unlike "
             & "Rule B");
      Fusa.Files.Write_File
        (Stub_Root & "/.fusa-hara.json",
         Hazards_Json (One_Hazard ("H1", "[describe hazard]")));

      for I in 1 .. 11 loop
         if I > 1 then
            Append (Many, ",");
         end if;
         Append (Many, One_Hazard
                   ("H" & Ada.Strings.Fixed.Trim
                            (Integer'Image (I), Ada.Strings.Left),
                    "generic hazard"));
      end loop;
      Fusa.Files.Write_File
        (Stub_Root & "/.fusa-hara.json", Hazards_Json (To_String (Many)));
      Check (Fusa.Cli.Run (Args ("hara", "--dir", Stub_Root)) = Exit_Ok,
             "hara does not gate-fail on a Rule B (FUSA-STUB002) blanket "
             & "fallback WARNING by default -- it's advisory");
      Check (Fusa.Cli.Run
               (Args ("hara", "--dir", Stub_Root, "--require-attestation")) =
               Exit_Gate_Fail,
             "hara --require-attestation escalates the unsuppressed Rule B "
             & "WARNING to exit 1");
      Check (Fusa.Cli.Run (Args ("hara", "--dir", Stub_Root, "--strict")) =
               Exit_Gate_Fail,
             "hara --strict implies --require-attestation");

      --  A fresh, independently-reviewed attestation whose contentHash
      --  matches the current document suppresses Rule B entirely (not
      --  merely dispositions it) -- exit goes back to 0 even under
      --  --require-attestation.
      declare
         Root_Val : constant Fusa.Json.Value_Access :=
           Fusa.Json.Parse
             (Fusa.Files.Read_File (Stub_Root & "/.fusa-hara.json"));
         Hash : constant String :=
           Fusa.Attestation.Canonical_Content_Hash (Root_Val);
      begin
         Fusa.Files.Write_File
           (Stub_Root & "/.fusa-hara.json",
            Hazards_With_Attestation (To_String (Many), Hash));
      end;
      Check (Fusa.Cli.Run
               (Args ("hara", "--dir", Stub_Root, "--require-attestation")) =
               Exit_Ok,
             "a fresh, independently-reviewed attestation whose contentHash "
             & "matches the current document suppresses Rule B, even under "
             & "--require-attestation");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("hara", "--dir", Stub_Root, "--format", "json"),
              Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, """attestation"":") > 0
                and then Ada.Strings.Fixed.Index
                           (Out_Text, """status"": ""reviewed""") > 0,
                "hara's JSON output passes the input file's attestation "
                & "through verbatim");
      end;

      --  Mutating the document without updating contentHash makes the
      --  carried-forward attestation stale -- it falls back to
      --  "heuristic" and Rule B's WARNING reappears.
      Append (Many, "," & One_Hazard ("H99", "generic hazard"));
      Fusa.Files.Write_File
        (Stub_Root & "/.fusa-hara.json",
         Hazards_With_Attestation
           (To_String (Many),
            "sha256:0000000000000000000000000000000000000000000000" &
              "0000000000000000"));
      Check (Fusa.Cli.Run
               (Args ("hara", "--dir", Stub_Root, "--require-attestation")) =
               Exit_Gate_Fail,
             "a stale attestation (contentHash no longer matching) no "
             & "longer suppresses Rule B");
      Ada.Directories.Delete_Tree (Stub_Root);
   end;

   --  fusa:test REQ-085
   Check (not Fusa.Files.Exists (Root & "/.fusa-tara.json"), "no .fusa-tara.json initially");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("tara", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Runtime,
             "tara --format json on a missing .fusa-tara.json with no --init "
             & "exits 3 (runtime error), not 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, """error"":") > 0,
             "the missing-input error is still a real JSON document");
   end;
   Check (Fusa.Cli.Run (Args ("tara", "--dir", Root, "--init")) = Exit_Ok,
          "tara --init scaffolds a template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-tara.json"), "tara --init created .fusa-tara.json");
   --  Regression: kind used to be the bare command name "tara"; §1.2.5/
   --  §9.2 require the report-document form "tara-report".
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("tara", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """kind"": ""tara-report""") > 0,
             "tara --format json reports kind ""tara-report"", not the bare "
             & "command name ""tara""");
      Check (Ada.Strings.Fixed.Index (Out_Text, """summary"": {") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """assetsAnalyzed""") > 0,
             "tara --format json includes the section 9.2 canonical summary "
             & "block (assetsAnalyzed/assetsInProject/coveragePct)");
   end;

   --  fusa:test REQ-085: section 9.2 MUST (spec v1.15.0) -- coveragePct
   --  must never exceed 100, even when an understated assetsInProject
   --  override would otherwise produce an impossible value like 200%.
   Fusa.Files.Write_File
     (Root & "/.fusa-tara.json",
      "{""assetsInProject"":1,""threats"":[" &
        "{""id"":""T1"",""asset"":""a1"",""threat"":""t1""," &
        """attackVector"":""network"",""attackFeasibility"":""medium""," &
        """impact"":{""safety"":""moderate"",""financial"":""moderate""," &
        """operational"":""moderate"",""privacy"":""moderate""}}," &
        "{""id"":""T2"",""asset"":""a2"",""threat"":""t2""," &
        """attackVector"":""network"",""attackFeasibility"":""medium""," &
        """impact"":{""safety"":""moderate"",""financial"":""moderate""," &
        """operational"":""moderate"",""privacy"":""moderate""}}]}");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout
          (Args ("tara", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """coveragePct"": 100") > 0,
             "tara clamps coveragePct to 100 rather than reporting 200% "
             & "when assetsInProject understates the real denominator");
   end;

   Fusa.Files.Write_File
     (Root & "/.fusa-tara.json", "{""threats"":[{""threat"":""no id or asset""}]}");
   Check (Fusa.Cli.Run (Args ("tara", "--dir", Root)) = Exit_Gate_Fail,
          "tara gate-fails once a threat with no id/asset is present (ERROR finding)");

   --  fusa:test REQ-119: same Rule A wiring as hara (test_stub_detect.adb
   --  unit-tests the underlying logic; test above end-to-end verifies
   --  hara's Rule B/attestation wiring in full) -- this locks in that
   --  tara wires Rule A in too, over its "threat" field.
   Fusa.Files.Write_File
     (Root & "/.fusa-tara.json",
      "{""threats"":[{""id"":""T1"",""asset"":""a"",""threat"":" &
        """[fill in]"",""attackVector"":""network""," &
        """attackFeasibility"":""medium"",""impact"":{""safety"":" &
        """moderate"",""financial"":""moderate"",""operational"":" &
        """moderate"",""privacy"":""moderate""}}]}");
   Check (Fusa.Cli.Run (Args ("tara", "--dir", Root)) = Exit_Gate_Fail,
          "tara gate-fails on a Rule A (FUSA-STUB001) placeholder threat "
          & "description");

   --  fusa:test REQ-097
   Check (not Fusa.Files.Exists (Root & "/.fusa-do178c-objectives.json"),
          "no .fusa-do178c-objectives.json initially");
   Check (Fusa.Cli.Run (Args ("do178", "--dir", Root)) = Exit_Ok,
          "do178 with no objectives file scaffolds a non-empty starter template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-do178c-objectives.json"),
          "do178 created .fusa-do178c-objectives.json");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("do178", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok,
             "do178 against the scaffolded starter template (all status ""gap"") exits 0 -- "
             & "gap status alone must never gate");
      --  Regression: kind used to be "<standard>-gap-report" (e.g.
      --  "do178c-gap-report"); §3.1's closed kind enum requires the
      --  literal string "gap-report" for every standard.
      Check (Ada.Strings.Fixed.Index (Out_Text, """kind"": ""gap-report""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """standard"": ""do178c""") > 0,
             "do178 --format json reports the spec-mandated literal ""gap-report"" "
             & "kind (not ""do178c-gap-report"") and the do178c standard field");
   end;
   Fusa.Files.Write_File
     (Root & "/.fusa-do178c-objectives.json", "{""objectives"":[{""title"":""no id""}]}");
   Check (Fusa.Cli.Run (Args ("do178", "--dir", Root)) = Exit_Gate_Fail,
          "do178 gate-fails once an objective with no id is present (ERROR finding)");

   --  Regression: "summary" is the §9.3 canonical objectives tally
   --  (total/satisfied/partial/gaps); a generic errors/warnings/infos
   --  tally of the GAP001/GAP002 config-validation findings used to
   --  ALSO claim that same key (via Write_Summary's old hardcoded
   --  "summary"), silently overwriting the objectives tally in the
   --  written JSON. It must now appear under "findingsSummary" instead.
   --  Regression: an objective with an unrecognised status used to be
   --  counted in "total" but in none of satisfied/partial/gaps,
   --  breaking the spec's satisfied+partial+gaps=total invariant.
   Fusa.Files.Write_File
     (Root & "/.fusa-do178c-objectives.json",
      "{""objectives"":[" &
      "{""id"":""a"",""status"":""satisfied""}," &
      "{""id"":""b"",""status"":""bogus""}," &
      "{""title"":""no id""}" &
      "]}");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("do178", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Gate_Fail,
             "the id-less objective's ERROR finding still gate-fails "
             & "regardless of the summary-key/status-normalisation fixes");
      Check (Ada.Strings.Fixed.Index (Out_Text, """summary"": {") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """total"": 2,") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """satisfied"": 1,") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """partial"": 0,") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """gaps"": 1") > 0,
             "the objectives ""summary"" counts the id-less objective out of "
             & """total"" (it was never added to Objectives) and folds the "
             & "unrecognised-status objective into ""gaps"", so "
             & "satisfied+partial+gaps=total holds");
      Check (Ada.Strings.Fixed.Index (Out_Text, """findingsSummary""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """objectiveSummary""") = 0,
             "the config-validation findings tally is written under "
             & """findingsSummary"", not the old, now-removed ""objectiveSummary""");
      Check (Ada.Strings.Fixed.Index (Out_Text, """status"": ""gap""") > 0,
             "an objective with an unrecognised status is normalised to "
             & """gap"" fail-safe (§9.3), not left as the invalid raw string, "
             & "in the written objectives array too");
   end;

   Check (not Fusa.Files.Exists (Root & "/.fusa-iso26262-objectives.json"),
          "no .fusa-iso26262-objectives.json initially");
   Check (Fusa.Cli.Run (Args ("iso26262", "--dir", Root)) = Exit_Ok,
          "iso26262 with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Cli.Run (Args ("iso21434", "--dir", Root)) = Exit_Ok,
          "iso21434 with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Cli.Run (Args ("iec61508", "--dir", Root)) = Exit_Ok,
          "iec61508 with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Cli.Run (Args ("iec62443", "--dir", Root)) = Exit_Ok,
          "iec62443 with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-iec62443-4-1-objectives.json"),
          "iec62443 uses the canonical standard id iec62443-4-1 for its objectives filename");
   Check (Fusa.Cli.Run (Args ("unece", "--dir", Root)) = Exit_Ok,
          "unece with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-unece-r155-objectives.json"),
          "unece uses the canonical standard id unece-r155 for its objectives filename");
   Check (Fusa.Cli.Run (Args ("slsa", "--dir", Root)) = Exit_Ok,
          "slsa with no objectives file scaffolds an empty template and exits 0");
   Check (Fusa.Cli.Run (Args ("iso26262", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "iso26262 --format bogus exits Exit_Usage");

   --  fusa:test REQ-086
   Check (Fusa.Cli.Run (Args ("vuln", "--dir", Root)) = Exit_Ok,
          "vuln exits 0 when no alire.toml is present (nothing to scan)");
   declare
      Exit_Code1 : Integer;
      Out_No_Alr : constant String :=
        Run_Capturing_Stdout (Args ("vuln", "--dir", Root, "--format", "json"), Exit_Code1);
   begin
      Check (Ada.Strings.Fixed.Index (Out_No_Alr, """findings"": []") > 0,
             "vuln reports an empty findings array with no alire.toml present");
   end;
   Fusa.Files.Write_File (Root & "/alire.toml", "name = ""t""");
   Check (Fusa.Cli.Run (Args ("vuln", "--dir", Root)) = Exit_Ok,
          "vuln still exits 0 with alire.toml present (an INFO finding does not gate)");
   declare
      Exit_Code2 : Integer;
      Out_Alr    : constant String :=
        Run_Capturing_Stdout (Args ("vuln", "--dir", Root, "--format", "json"), Exit_Code2);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Alr, """ruleId"": ""VULN001""") > 0,
             "vuln surfaces an informational VULN001 finding once alire.toml exists");
   end;

   --  fusa:test REQ-099
   declare
      Verify_Root : constant String := "tmp_test_cli_verify";
   begin
      if Ada.Directories.Exists (Verify_Root) then
         Ada.Directories.Delete_Tree (Verify_Root);
      end if;
      Ada.Directories.Create_Path (Verify_Root);
      Check (not Fusa.Files.Exists (Verify_Root & "/.fusa-verify.json"),
             "no .fusa-verify.json initially");
      Check (Fusa.Cli.Run (Args ("verify", "--dir", Verify_Root)) = Exit_Ok,
             "verify with no .fusa-verify.json scaffolds a template and exits 0");
      Check (Fusa.Files.Exists (Verify_Root & "/.fusa-verify.json"),
             "verify created .fusa-verify.json");

      Fusa.Files.Write_File
        (Verify_Root & "/.fusa-verify.json",
         "{""suites"":[{""name"":""unit-tests"",""tests"":[" &
         "{""name"":""t1"",""result"":""PASS""}," &
         "{""name"":""t2"",""result"":""PASS""}," &
         "{""name"":""t3"",""result"":""FAIL""}]}]}");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout (Args ("verify", "--dir", Verify_Root), Exit_Code);
      begin
         Check (Exit_Code = Exit_Gate_Fail,
                "verify gate-fails once any test in the suite has result FAIL");
         Check (Ada.Strings.Fixed.Index (Out_Text, "2 passed, 1 failed") > 0,
                "verify's text output reports the computed passed/failed counts "
                & "(2 PASS + 1 FAIL among the three tests)");
      end;
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("verify", "--dir", Verify_Root, "--format", "json"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Json, """passed"": 2") > 0
                and then Ada.Strings.Fixed.Index (Out_Json, """failed"": 1") > 0,
                "verify --format json reports the canonical top-level passed/failed fields");
         Check (Ada.Strings.Fixed.Index (Out_Json, """suites"":") > 0
                and then Ada.Strings.Fixed.Index (Out_Json, """tests"":") > 0,
                "verify --format json nests suites[].tests[] per the spec canonical shape");
      end;

      Fusa.Files.Write_File
        (Verify_Root & "/.fusa-verify.json", "{""suites"":[{""tests"":[]}]}");
      Check (Fusa.Cli.Run (Args ("verify", "--dir", Verify_Root)) = Exit_Gate_Fail,
             "verify gate-fails once a suite with no name is present (ERROR finding)");
      Ada.Directories.Delete_Tree (Verify_Root);
   end;

   --  fusa:test REQ-101
   declare
      Badge_Root : constant String := "tmp_test_cli_badge";
   begin
      if Ada.Directories.Exists (Badge_Root) then
         Ada.Directories.Delete_Tree (Badge_Root);
      end if;
      Ada.Directories.Create_Path (Badge_Root & "/src");
      Ada.Directories.Create_Path (Badge_Root & "/.github/workflows");
      Fusa.Files.Write_File
        (Badge_Root & "/.fusa.json", "{""project"":{""name"":""badgeproj""},""standard"":""generic""}");
      Fusa.Files.Write_File (Badge_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File (Badge_Root & "/LICENSE", "MPL-2.0");
      Fusa.Files.Write_File (Badge_Root & "/README.md", "# Test fixture");
      Fusa.Files.Write_File (Badge_Root & "/t.gpr", "project T is end T;");
      Fusa.Files.Write_File (Badge_Root & "/.github/workflows/ci.yml", "name: CI");
      declare
         Exit_Code : Integer;
         Out_Clean : constant String :=
           Run_Capturing_Stdout (Args ("badge", "--dir", Badge_Root), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok, "badge exits 0 on a clean project");
         Check (Ada.Strings.Fixed.Index (Out_Clean, "<svg") = 1, "badge emits an SVG document");
         Check (Ada.Strings.Fixed.Index (Out_Clean, ">passing<") > 0,
                "badge shows 'passing' when there are no findings");
      end;
      Fusa.Files.Write_File
        (Badge_Root & "/src/bad.adb",
         "procedure Bad is begin pragma Suppress (All_Checks); end Bad;" & ASCII.LF);
      declare
         Exit_Code : Integer;
         Out_Err   : constant String :=
           Run_Capturing_Stdout (Args ("badge", "--dir", Badge_Root), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok, "badge itself still exits 0 even when the underlying "
                & "project has ERROR findings -- it always succeeds at generating the artifact");
         Check (Ada.Strings.Fixed.Index (Out_Err, ">1 errors<") > 0,
                "badge shows the error count once an ADA001 finding is present");
      end;
      declare
         Exit_Code : Integer;
         Out_Custom : constant String :=
           Run_Capturing_Stdout
             (Args ("badge", "--dir", Badge_Root, "--message", "v1.0.0", "--color", "#007ec6"),
              Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Custom, ">v1.0.0<") > 0
                and then Ada.Strings.Fixed.Index (Out_Custom, "#007ec6") > 0,
                "badge --message/--color renders a custom badge without running check at all "
                & "(no error count leaks through despite the project still having one)");
      end;
      Ada.Directories.Delete_Tree (Badge_Root);
   end;

   --  fusa:test REQ-100
   declare
      Diff_Root : constant String := "tmp_test_cli_diff";
   begin
      if Ada.Directories.Exists (Diff_Root) then
         Ada.Directories.Delete_Tree (Diff_Root);
      end if;
      Ada.Directories.Create_Path (Diff_Root & "/src");
      Fusa.Files.Write_File
        (Diff_Root & "/.fusa.json", "{""project"":{""name"":""diffproj""},""standard"":""generic""}");
      Fusa.Files.Write_File (Diff_Root & "/.fusa-reqs.json", "{""requirements"":[]}");

      Check (Fusa.Cli.Run (Args ("diff", "--dir", Diff_Root)) = Exit_Usage,
             "diff with no --baseline exits 2 (usage)");
      Check (Fusa.Cli.Run
               (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/nope.json"))
             = Exit_Runtime,
             "diff against a nonexistent baseline file exits 3 (runtime error)");

      --  Snapshot the clean state as the baseline.
      declare
         Exit_Code_A : Integer;
      begin
         Fusa.Files.Write_File
           (Diff_Root & "/baseline.json",
            Run_Capturing_Stdout
              (Args ("check", "--dir", Diff_Root, "--format", "json"), Exit_Code_A));
      end;

      Check (Fusa.Cli.Run
               (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/baseline.json"))
             = Exit_Ok,
             "diff against a baseline matching the current (live) state exits 0 "
             & "(nothing added)");

      --  Introduce a new ERROR finding; diff's "current" side is always a
      --  live check run, never a second saved file.
      Fusa.Files.Write_File
        (Diff_Root & "/src/bad.adb",
         "procedure Bad is begin pragma Suppress (All_Checks); end Bad;" & ASCII.LF);
      Check (Fusa.Cli.Run
               (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/baseline.json"))
             = Exit_Gate_Fail,
             "diff gate-fails once the live project has a new ERROR finding the baseline "
             & "did not have");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/baseline.json"),
              Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, "+ [ERROR] ADA001") > 0,
                "diff's text output marks the newly-added ADA001 finding with a leading '+'");
      end;
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/baseline.json",
                    "--format", "json"),
              Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Json, """unchanged"":") > 0,
                "diff --format json reports the unchanged count");
         Check (Ada.Strings.Fixed.Index (Out_Json, """ruleId""") = 0,
                "diff --format json's added/removed are bare fingerprint strings, "
                & "not full finding objects with a ruleId field, per the spec canonical shape");
      end;

      --  Snapshot again with bad.adb present, then remove it: the ERROR
      --  finding disappears from the live side (a "removed" case), which
      --  must never gate -- fixing something is never a failure.
      declare
         Exit_Code_B : Integer;
      begin
         Fusa.Files.Write_File
           (Diff_Root & "/baseline2.json",
            Run_Capturing_Stdout
              (Args ("check", "--dir", Diff_Root, "--format", "json"), Exit_Code_B));
      end;
      Ada.Directories.Delete_File (Diff_Root & "/src/bad.adb");
      Check (Fusa.Cli.Run
               (Args ("diff", "--dir", Diff_Root, "--baseline", Diff_Root & "/baseline2.json"))
             = Exit_Ok,
             "diff does not gate when a finding disappeared (removed), only when one "
             & "was added");
      Ada.Directories.Delete_Tree (Diff_Root);
   end;

   --  fusa:test REQ-103
   --  fusa:test REQ-104
   declare
      Deps_Root : constant String := "tmp_test_cli_deps";
   begin
      if Ada.Directories.Exists (Deps_Root) then
         Ada.Directories.Delete_Tree (Deps_Root);
      end if;
      Ada.Directories.Create_Path (Deps_Root & "/src");
      Fusa.Files.Write_File
        (Deps_Root & "/.fusa.json", "{""project"":{""name"":""depsproj""},""standard"":""generic""}");
      Fusa.Files.Write_File (Deps_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Deps_Root & "/src/pkg_a.ads", "package Pkg_A is" & ASCII.LF &
           "   procedure Do_It;" & ASCII.LF & "end Pkg_A;" & ASCII.LF);
      Fusa.Files.Write_File
        (Deps_Root & "/src/pkg_b.ads", "with Pkg_A;" & ASCII.LF & "package Pkg_B is" & ASCII.LF &
           "   procedure Do_It;" & ASCII.LF & "end Pkg_B;" & ASCII.LF);

      Check (Fusa.Cli.Run (Args ("boundary", "--dir", Deps_Root, "--format", "bogus"))
             = Exit_Usage, "boundary --format bogus exits 2");
      declare
         Exit_Code : Integer;
         Out_Dot   : constant String :=
           Run_Capturing_Stdout (Args ("boundary", "--dir", Deps_Root), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok, "boundary exits 0");
         Check (Ada.Strings.Fixed.Index (Out_Dot, "digraph Boundary") > 0
                and then Ada.Strings.Fixed.Index (Out_Dot, """Pkg_B"" -> ""Pkg_A""") > 0,
                "boundary's default DOT output includes the Pkg_B -> Pkg_A edge");
      end;
      declare
         Exit_Code : Integer;
         Out_Mmd   : constant String :=
           Run_Capturing_Stdout
             (Args ("boundary", "--dir", Deps_Root, "--format", "mermaid"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Mmd, "graph TD") = 1,
                "boundary --format mermaid emits a Mermaid graph");
         Check (Ada.Strings.Fixed.Index (Out_Mmd, "Pkg_B --> Pkg_A") > 0,
                "boundary --format mermaid's node ids have '.' replaced with '_' "
                & "and still show the Pkg_B -> Pkg_A edge");
      end;

      Check (Fusa.Cli.Run (Args ("impact", "--dir", Deps_Root)) = Exit_Usage,
             "impact with no changed files exits 2");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("impact", "--dir", Deps_Root, "src/pkg_a.ads"), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok, "impact exits 0");
         Check (Ada.Strings.Fixed.Index (Out_Text, "Pkg_A") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, "Pkg_B") > 0,
                "impact on pkg_a.ads reports Pkg_B as an impacted unit "
                & "(Pkg_B directly depends on Pkg_A)");
         --  Regression: a bare substring check for "Pkg_A"/"Pkg_B" would
         --  still pass even if the changed unit wrongly listed itself as
         --  impacted (self-inclusion), or if extra unrelated units leaked
         --  in -- the "1 impacted unit(s):" summary line and the exact
         --  "  Pkg_A" line (leading two-space indent used only by the
         --  per-unit list, not the "pkg_a.ads -> Pkg_A" resolution line)
         --  pin down both the count and the absence of self-inclusion.
         Check (Ada.Strings.Fixed.Index (Out_Text, "1 impacted unit(s):") > 0,
                "impact on pkg_a.ads reports exactly one impacted unit, "
                & "not more");
         Check (Ada.Strings.Fixed.Index
                  (Out_Text, ASCII.LF & "  Pkg_A" & ASCII.LF) = 0,
                "impact does not list the changed unit itself "
                & "(Pkg_A) among its own impacted units");
      end;
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("impact", "--dir", Deps_Root, "not-a-project-file.txt"), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok,
                "impact on a file that isn't a recognised project unit still exits 0");
         Check (Ada.Strings.Fixed.Index (Out_Text, "not a recognised project unit") > 0,
                "impact reports the unresolved file rather than silently ignoring it");
      end;
      Ada.Directories.Delete_Tree (Deps_Root);
   end;

   --  fusa:test REQ-105
   Check (Fusa.Cli.Run (Args ("coupling", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "coupling --format bogus exits 2");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("coupling", "--dir", Root), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "coupling exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, "fan-in=") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, "fan-out=") > 0,
             "coupling's text output reports fan-in/fan-out per unit");
   end;

   --  fusa:test REQ-106
   Check (not Fusa.Files.Exists (Root & "/.fusa-fmea.json"), "no .fusa-fmea.json initially");
   Check (Fusa.Cli.Run (Args ("fmea", "--dir", Root)) = Exit_Ok,
          "fmea with no .fusa-fmea.json scaffolds a template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-fmea.json"), "fmea created .fusa-fmea.json");
   Fusa.Files.Write_File
     (Root & "/.fusa-fmea.json",
      "{""entries"":[{""id"":""FMEA-001"",""severity"":8,""occurrence"":3,""detection"":4," &
        """failureMode"":""overflow""}]}");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("fmea", "--dir", Root), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "fmea against a well-formed entry exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, "RPN=96") > 0,
             "fmea's text output shows the computed RPN (8*3*4=96)");
   end;
   declare
      Exit_Code : Integer;
      Out_Csv   : constant String :=
        Run_Capturing_Stdout (Args ("fmea", "--dir", Root, "--format", "csv"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Csv, "id,item,file") = 1,
             "fmea --format csv starts with the expected header row");
      Check (Ada.Strings.Fixed.Index (Out_Csv, "FMEA-001") > 0, "the entry appears in the CSV");
   end;
   --  Regression: fmea's JSON output used to have no "summary" block at
   --  all (no componentsInProject/coveragePct), and its generic
   --  errors/warnings/infos validation tally used the same "summary" key
   --  the section 9.2 canonical coverage block now needs -- same
   --  collision gap-report/tara had, fixed the same way (findingsSummary).
   declare
      Fmea_Cov_Root : constant String := "tmp_test_cli_fmea_coverage";
   begin
      if Ada.Directories.Exists (Fmea_Cov_Root) then
         Ada.Directories.Delete_Tree (Fmea_Cov_Root);
      end if;
      Ada.Directories.Create_Path (Fmea_Cov_Root & "/src");
      Fusa.Files.Write_File
        (Fmea_Cov_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Fmea_Cov_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      --  Exactly 2 public functions -> a known componentsInProject
      --  denominator to check coveragePct's arithmetic against.
      Fusa.Files.Write_File
        (Fmea_Cov_Root & "/src/pkg.ads",
         "package Pkg is" & ASCII.LF &
         "   function A return Integer;" & ASCII.LF &
         "   function B return Integer;" & ASCII.LF &
         "end Pkg;" & ASCII.LF);
      Fusa.Files.Write_File
        (Fmea_Cov_Root & "/.fusa-fmea.json",
         "{""entries"":[{""id"":""FMEA-001"",""item"":""Pkg.A"",""file"":""src/pkg.ads""," &
         """failureMode"":""fm"",""effect"":""ef""," &
         """severity"":8,""occurrence"":3,""detection"":4}]}");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout (Args ("fmea", "--dir", Fmea_Cov_Root, "--format", "json"),
                                  Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, """summary"": {") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, """componentsAnalyzed"": 1") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, """componentsInProject"": 2") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, """coveragePct"": 50") > 0,
                "fmea --format json's summary block reports the correct "
                & "1/2 = 50% coveragePct against the real public-function count");
         Check (Ada.Strings.Fixed.Index (Out_Text, """findingsSummary""") > 0
                and then Ada.Strings.Fixed.Index (Out_Text, """ratingScale""") > 0,
                "the config-validation findings tally is under ""findingsSummary"", "
                & "and ratingScale is present since occurrence/detection were emitted");
      end;
      --  section 9.2 MUST (spec v1.15.0) -- coveragePct must never
      --  exceed 100, even when an understated componentsInProject
      --  override would otherwise produce an impossible value like 200%.
      Fusa.Files.Write_File
        (Fmea_Cov_Root & "/.fusa-fmea.json",
         "{""componentsInProject"":1,""entries"":[" &
           "{""id"":""FMEA-001"",""item"":""Pkg.A""," &
           """file"":""src/pkg.ads""," &
           """failureMode"":""fm1"",""effect"":""ef1"",""severity"":8}," &
           "{""id"":""FMEA-002"",""item"":""Pkg.B""," &
           """file"":""src/pkg.ads""," &
           """failureMode"":""fm2"",""effect"":""ef2"",""severity"":8}]}");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("fmea", "--dir", Fmea_Cov_Root, "--format", "json"),
              Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, """coveragePct"": 100") > 0,
                "fmea clamps coveragePct to 100 rather than reporting 200% "
                & "when componentsInProject understates the real denominator");
      end;
      Fusa.Files.Write_File
        (Fmea_Cov_Root & "/.fusa-fmea.json",
         "{""entries"":[{""id"":""FMEA-001"",""item"":""Pkg.A""," &
         """file"":""src/pkg.ads""," &
         """failureMode"":""fm"",""effect"":""ef""," &
         """severity"":8,""occurrence"":3,""detection"":4}]}");
      Check (Fusa.Cli.Run
               (Args ("fmea", "--dir", Fmea_Cov_Root, "--min-coverage", "60")) = Exit_Gate_Fail,
             "fmea --min-coverage 60 gate-fails when coveragePct (50) is below it");
      Check (Fusa.Cli.Run
               (Args ("fmea", "--dir", Fmea_Cov_Root, "--min-coverage", "40")) = Exit_Ok,
             "fmea --min-coverage 40 exits 0 when coveragePct (50) meets it");
      Check (Fusa.Cli.Run
               (Args ("fmea", "--dir", Fmea_Cov_Root, "--min-coverage", "bogus")) = Exit_Usage,
             "fmea --min-coverage bogus exits 2 (usage), not a crash");
      Ada.Directories.Delete_Tree (Fmea_Cov_Root);
   end;

   Fusa.Files.Write_File
     (Root & "/.fusa-fmea.json", "{""entries"":[{""failureMode"":""no id""}]}");
   Check (Fusa.Cli.Run (Args ("fmea", "--dir", Root)) = Exit_Gate_Fail,
          "fmea gate-fails once an entry with no id is present (ERROR finding)");

   --  fusa:test REQ-119: same Rule A wiring as hara/tara, over fmea's
   --  failureMode/effect/cause fields.
   Fusa.Files.Write_File
     (Root & "/.fusa-fmea.json",
      "{""entries"":[{""id"":""E1"",""item"":""comp"",""file"":" &
        """src/x.adb"",""failureMode"":""[describe failure]""," &
        """effect"":""system fails"",""severity"":5}]}");
   Check (Fusa.Cli.Run (Args ("fmea", "--dir", Root)) = Exit_Gate_Fail,
          "fmea gate-fails on a Rule A (FUSA-STUB001) placeholder "
          & "failureMode");

   --  fusa:test REQ-107
   Check (not Fusa.Files.Exists (Root & "/.fusa-safety-case.json"),
          "no .fusa-safety-case.json initially");
   Check (Fusa.Cli.Run (Args ("safety-case", "--dir", Root)) = Exit_Ok,
          "safety-case with no file scaffolds a template and exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-safety-case.json"),
          "safety-case created .fusa-safety-case.json");
   Fusa.Files.Write_File (Root & "/qualify-report.json", "{}" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/.fusa-safety-case.json",
      "{""rootGoal"":""G1"",""nodes"":[" &
        "{""id"":""G1"",""type"":""goal"",""text"":""top"",""supportedBy"":[""Sn1""]}," &
        "{""id"":""Sn1"",""type"":""solution"",""text"":""evidence""," &
        """evidence"":""qualify-report.json""}]}");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("safety-case", "--dir", Root), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "safety-case against a well-formed argument exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, "[goal] G1") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, "[solution] Sn1") > 0,
             "safety-case's text outline shows both the root goal and its supporting solution");
      Check (Ada.Strings.Fixed.Index (Out_Text, "(evidence: qualify-report.json)") > 0,
             "safety-case's text outline shows Sn1's evidence file");
   end;
   declare
      Exit_Code : Integer;
      Out_Mmd   : constant String :=
        Run_Capturing_Stdout
          (Args ("safety-case", "--dir", Root, "--format", "mermaid"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Mmd, "graph TD") = 1,
             "safety-case --format mermaid emits a Mermaid graph");
      Check (Ada.Strings.Fixed.Index (Out_Mmd, "G1 --> Sn1") > 0,
             "safety-case --format mermaid shows the supportedBy edge");
   end;
   declare
      Exit_Code : Integer;
      Out_Json  : constant String :=
        Run_Capturing_Stdout
          (Args ("safety-case", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Json, """edges"":") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """from"": ""G1""") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """to"": ""Sn1""") > 0,
             "safety-case --format json puts supportedBy in a top-level edges[] array "
             & "(from/to/type), per the spec canonical shape, not embedded per-node");
      Check (Ada.Strings.Fixed.Index (Out_Json, """supportedBy"":") = 0,
             "safety-case --format json no longer embeds supportedBy directly on each node");
      Check (Ada.Strings.Fixed.Index (Out_Json, """evidence"": ""qualify-report.json""") > 0,
             "safety-case --format json includes Sn1's evidence field");
      Check (Ada.Strings.Fixed.Index (Out_Json, """completeness"":") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """totalGoals"": 1") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """goalsWithEvidence"": 1") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """undeveloped"": 0") > 0,
             "safety-case --format json includes the completeness block "
             & "(G1 is supported by a solution with evidence)");
   end;
   Fusa.Files.Write_File
     (Root & "/.fusa-safety-case.json",
      "{""nodes"":[{""id"":""G1"",""supportedBy"":[""NOPE""]}]}");
   Check (Fusa.Cli.Run (Args ("safety-case", "--dir", Root)) = Exit_Gate_Fail,
          "safety-case gate-fails once a dangling supportedBy reference is present "
          & "(ERROR finding)");

   --  fusa:test REQ-119: same Rule A wiring as hara/tara/fmea, over a GSN
   --  node's text field.
   Fusa.Files.Write_File
     (Root & "/.fusa-safety-case.json",
      "{""rootGoal"":""G1"",""nodes"":[{""id"":""G1"",""type"":""goal""," &
        """text"":""[describe goal]""}]}");
   Check (Fusa.Cli.Run (Args ("safety-case", "--dir", Root)) = Exit_Gate_Fail,
          "safety-case gate-fails on a Rule A (FUSA-STUB001) placeholder "
          & "goal text");

   --  fusa:test REQ-108
   Check (Fusa.Cli.Run (Args ("cyber", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "cyber --format bogus exits 2");
   declare
      Exit_Code : Integer;
      Out_Json  : constant String :=
        Run_Capturing_Stdout (Args ("cyber", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "cyber exits 0 with no security findings");
      Check (Ada.Strings.Fixed.Index (Out_Json, """kind"": ""cyber-report""") > 0,
             "cyber --format json reports the cyber-report kind");
   end;
   declare
      Sec_Root : constant String := "tmp_test_cli_cyber";
   begin
      if Ada.Directories.Exists (Sec_Root) then
         Ada.Directories.Delete_Tree (Sec_Root);
      end if;
      Ada.Directories.Create_Path (Sec_Root & "/src");
      Fusa.Files.Write_File
        (Sec_Root & "/.fusa.json", "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Sec_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Sec_Root & "/src/bad.adb",
         "procedure Bad is" & ASCII.LF &
         "   Password : constant String := ""hunter2"";" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Bad;" & ASCII.LF);
      Check (Fusa.Cli.Run (Args ("cyber", "--dir", Sec_Root)) = Exit_Gate_Fail,
             "cyber gate-fails on a SEC001 ERROR finding, same as check");
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout (Args ("cyber", "--dir", Sec_Root), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, "SEC001") > 0,
                "cyber's output includes the SEC001 finding");
      end;
      Ada.Directories.Delete_Tree (Sec_Root);
   end;

   --  fusa:test REQ-109
   declare
      Exit_Code : Integer;
      Out_Json  : constant String :=
        Run_Capturing_Stdout (Args ("sci", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "sci always exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Json, """kind"": ""sci""") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """artifacts"":") > 0,
             "sci --format json reports the sci kind and the canonical "
             & "artifacts[] array (not ""items"")");
      Check (Ada.Strings.Fixed.Index (Out_Json, """hash"": ""sha256:") > 0,
             "sci's per-artifact hash field is sha256:-prefixed per section 2.7's "
             & "field-named-""hash"" rule (not a bare ""sha256"" field)");
      Check (Ada.Strings.Fixed.Index (Out_Json, """version"":") > 0,
             "sci reports the project's version per artifact");
   end;

   --  fusa:test REQ-112
   Check (Fusa.Cli.Run (Args ("analyze", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "analyze --format bogus exits 2");
   declare
      Analyze_Root : constant String := "tmp_test_cli_analyze";
   begin
      if Ada.Directories.Exists (Analyze_Root) then
         Ada.Directories.Delete_Tree (Analyze_Root);
      end if;
      Ada.Directories.Create_Path (Analyze_Root & "/src");
      Fusa.Files.Write_File
        (Analyze_Root & "/.fusa.json", "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Analyze_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Analyze_Root & "/src/unused.adb",
         "with Ada.Strings.Fixed;" & ASCII.LF &
         "procedure Unused is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
         "end Unused;" & ASCII.LF);
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout (Args ("analyze", "--dir", Analyze_Root), Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok,
                "analyze exits 0 even with an ANAL001 finding -- it's INFO severity");
         Check (Ada.Strings.Fixed.Index (Out_Text, "ANAL001") > 0,
                "analyze's output includes the ANAL001 finding");
      end;
      Ada.Directories.Delete_Tree (Analyze_Root);
   end;

   --  Regression: analyze was one of only two gating commands (of 11)
   --  that never applied .fusa-dispositions.json.
   declare
      Analyze_Disp_Root : constant String := "tmp_test_cli_analyze_disp";
   begin
      if Ada.Directories.Exists (Analyze_Disp_Root) then
         Ada.Directories.Delete_Tree (Analyze_Disp_Root);
      end if;
      Ada.Directories.Create_Path (Analyze_Disp_Root & "/src");
      Fusa.Files.Write_File
        (Analyze_Disp_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File
        (Analyze_Disp_Root & "/src/many_params.adb",
         "procedure Many_Params (A, B, C, D, E, F, G : Integer) is" &
           ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF &
           "end Many_Params;" & ASCII.LF);
      Check (Fusa.Cli.Run
               (Args ("analyze", "--dir", Analyze_Disp_Root, "--strict")) =
               Exit_Gate_Fail,
             "analyze --strict gate-fails on the ANAL002 (too many "
             & "parameters) WARNING before any disposition exists");
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("analyze", "--dir", Analyze_Disp_Root, "--format", "json"),
              Exit_Code);
         Fp_Key   : constant String := """fingerprint"": """;
         Fp_Start : constant Natural :=
           Ada.Strings.Fixed.Index (Out_Json, Fp_Key);
         Fp       : constant String :=
           Out_Json (Fp_Start + Fp_Key'Length ..
                       Ada.Strings.Fixed.Index
                         (Out_Json, """", Fp_Start + Fp_Key'Length) - 1);
      begin
         Check (Fusa.Cli.Run
                  (Args ("disposition", "add", Fp, "accepted", "reviewed",
                          "--dir", Analyze_Disp_Root)) = Exit_Ok,
                "disposition add against the ANAL002 finding exits 0");
      end;
      Check (Fusa.Cli.Run
               (Args ("analyze", "--dir", Analyze_Disp_Root, "--strict")) =
               Exit_Ok,
             "analyze --strict no longer gate-fails once the ANAL002 "
             & "finding is accepted via .fusa-dispositions.json");
      Ada.Directories.Delete_Tree (Analyze_Disp_Root);
   end;

   --  fusa:test REQ-113
   Check (Fusa.Cli.Run (Args ("lint", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "lint --format bogus exits 2");
   declare
      Lint_Root : constant String := "tmp_test_cli_lint";
   begin
      if Ada.Directories.Exists (Lint_Root) then
         Ada.Directories.Delete_Tree (Lint_Root);
      end if;
      Ada.Directories.Create_Path (Lint_Root & "/src");
      Fusa.Files.Write_File
        (Lint_Root & "/.fusa.json", "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Lint_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Lint_Root & "/src/messy.adb",
         "procedure Messy is  " & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
         "end Messy;" & ASCII.LF);
      Check (Fusa.Cli.Run (Args ("lint", "--dir", Lint_Root)) = Exit_Ok,
             "lint exits 0 without --strict (LINT findings are WARNING)");
      Check (Fusa.Cli.Run (Args ("lint", "--dir", Lint_Root, "--strict")) = Exit_Gate_Fail,
             "lint --strict gate-fails on the trailing-whitespace WARNING");

      --  Regression: lint was the other of only two gating commands (of
      --  11) that never applied .fusa-dispositions.json.
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("lint", "--dir", Lint_Root, "--format", "json"),
              Exit_Code);
         Fp_Key   : constant String := """fingerprint"": """;
         Fp_Start : constant Natural :=
           Ada.Strings.Fixed.Index (Out_Json, Fp_Key);
         Fp       : constant String :=
           Out_Json (Fp_Start + Fp_Key'Length ..
                       Ada.Strings.Fixed.Index
                         (Out_Json, """", Fp_Start + Fp_Key'Length) - 1);
      begin
         Check (Fusa.Cli.Run
                  (Args ("disposition", "add", Fp, "accepted", "reviewed",
                          "--dir", Lint_Root)) = Exit_Ok,
                "disposition add against the LINT finding exits 0");
      end;
      Check (Fusa.Cli.Run
               (Args ("lint", "--dir", Lint_Root, "--strict")) = Exit_Ok,
             "lint --strict no longer gate-fails once the trailing-"
             & "whitespace finding is accepted via .fusa-dispositions.json");
      Ada.Directories.Delete_Tree (Lint_Root);
   end;

   --  Regression: .fusa.json's "strict" field used to only be honoured
   --  by check/cyber -- trace/diff/analyze/lint accepted a --strict CLI
   --  flag but never OR'd in the project-wide config value, so a team
   --  that set "strict": true project-wide still needed every command
   --  invocation (including ad hoc/CI ones that forgot the flag) to
   --  separately pass --strict.
   declare
      Strict_Cfg_Root : constant String := "tmp_test_cli_strict_cfg";
   begin
      if Ada.Directories.Exists (Strict_Cfg_Root) then
         Ada.Directories.Delete_Tree (Strict_Cfg_Root);
      end if;
      Ada.Directories.Create_Path (Strict_Cfg_Root & "/src");
      Fusa.Files.Write_File
        (Strict_Cfg_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic"",""strict"":true}");
      Fusa.Files.Write_File (Strict_Cfg_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File
        (Strict_Cfg_Root & "/src/messy.adb",
         "procedure Messy is  " & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
         "end Messy;" & ASCII.LF);
      Check (Fusa.Cli.Run (Args ("lint", "--dir", Strict_Cfg_Root)) = Exit_Gate_Fail,
             "lint now gate-fails on a WARNING-level LINT finding purely from "
             & ".fusa.json's ""strict"": true, with no --strict CLI flag at all");
      Check (Fusa.Cli.Run (Args ("analyze", "--dir", Strict_Cfg_Root)) = Exit_Ok,
             "analyze still exits 0 under .fusa.json strict, since this "
             & "fixture has no ANAL002 (Warning) finding, only what would "
             & "be an ANAL001 (Info, never gates) if anything");
      Ada.Directories.Delete_Tree (Strict_Cfg_Root);
   end;

   declare
      Strict_Diff_Root : constant String := "tmp_test_cli_strict_diff";
      Baseline_Path    : constant String := "tmp_test_cli_strict_diff_baseline.json";
   begin
      if Ada.Directories.Exists (Strict_Diff_Root) then
         Ada.Directories.Delete_Tree (Strict_Diff_Root);
      end if;
      Ada.Directories.Create_Path (Strict_Diff_Root & "/src");
      Fusa.Files.Write_File
        (Strict_Diff_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic"",""strict"":true}");
      Fusa.Files.Write_File (Strict_Diff_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      --  An empty baseline: any WARNING-or-worse finding in the live run
      --  is therefore "added".
      Fusa.Files.Write_File (Baseline_Path, "{""findings"":[]}");
      Fusa.Files.Write_File
        (Strict_Diff_Root & "/src/messy.adb",
         "procedure Messy is  " & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
         "end Messy;" & ASCII.LF);
      Check (Fusa.Cli.Run
               (Args ("diff", "--dir", Strict_Diff_Root, "--baseline", Baseline_Path)) =
             Exit_Gate_Fail,
             "diff now gate-fails on an added (non-ERROR) finding purely "
             & "from .fusa.json's ""strict"": true, with no --strict CLI "
             & "flag at all");
      Ada.Directories.Delete_Tree (Strict_Diff_Root);
      Ada.Directories.Delete_File (Baseline_Path);
   end;

   declare
      Strict_Trace_Root : constant String := "tmp_test_cli_strict_trace";
   begin
      if Ada.Directories.Exists (Strict_Trace_Root) then
         Ada.Directories.Delete_Tree (Strict_Trace_Root);
      end if;
      Ada.Directories.Create_Path (Strict_Trace_Root & "/src");
      Fusa.Files.Write_File
        (Strict_Trace_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic"",""strict"":true}");
      Fusa.Files.Write_File
        (Strict_Trace_Root & "/.fusa-reqs.json",
         "{""requirements"":[{""id"":""REQ-1"",""title"":""untraced""}]}");
      Check (Fusa.Cli.Run (Args ("trace", "--dir", Strict_Trace_Root)) = Exit_Gate_Fail,
             "trace now gate-fails on an untraced requirement purely from "
             & ".fusa.json's ""strict"": true (implying --req-coverage 100), "
             & "with no --strict CLI flag at all");
      Ada.Directories.Delete_Tree (Strict_Trace_Root);
   end;

   --  fusa:test REQ-114
   declare
      Sas_Root : constant String := "tmp_test_cli_sas";
   begin
      if Ada.Directories.Exists (Sas_Root) then
         Ada.Directories.Delete_Tree (Sas_Root);
      end if;
      Ada.Directories.Create_Path (Sas_Root & "/src");
      Fusa.Files.Write_File
        (Sas_Root & "/.fusa.json",
         "{""project"":{""name"":""sasproj""},""standard"":""do178c""}");
      Fusa.Files.Write_File
        (Sas_Root & "/.fusa-reqs.json",
         "{""requirements"":[{""id"":""REQ-1"",""title"":""t""}]}");
      Fusa.Files.Write_File
        (Sas_Root & "/src/x.adb",
         "procedure X is" & ASCII.LF &
         "   -- fusa:req REQ-1" & ASCII.LF &
         "begin" & ASCII.LF & "   null;" & ASCII.LF & "end X;" & ASCII.LF);
      Check (not Fusa.Files.Exists (Sas_Root & "/sas.json"), "no sas.json initially");
      Check (Fusa.Cli.Run (Args ("sas", "--dir", Sas_Root)) = Exit_Ok, "sas exits 0");
      Check (Fusa.Files.Exists (Sas_Root & "/sas.json")
             and then Fusa.Files.Exists (Sas_Root & "/sas.md"),
             "sas always writes both sas.json and sas.md");
      declare
         Content : constant String := Fusa.Files.Read_File (Sas_Root & "/sas.json");
      begin
         Check (Ada.Strings.Fixed.Index (Content, """kind"": ""sas""") > 0,
                "sas.json carries kind: sas");
         Check (Ada.Strings.Fixed.Index (Content, """checklist"":") > 0,
                "sas.json has the canonical checklist[] array");
         Check (Ada.Strings.Fixed.Index
                  (Content, """item"": ""Software Requirements Data""") > 0
                and then Ada.Strings.Fixed.Index (Content, """clause"": ""11.9""") > 0
                and then Ada.Strings.Fixed.Index
                  (Content, """evidence"": "".fusa-reqs.json""") > 0,
                "sas.json's checklist marks 11.9 present with real evidence, "
                & "since a non-empty .fusa-reqs.json exists");
         Check (Ada.Strings.Fixed.Index
                  (Content, """item"": ""Plan for Software Aspects of Certification""") > 0
                and then Ada.Strings.Fixed.Index (Content, """clause"": ""11.1""") > 0,
                "sas.json's checklist still lists items ada-FuSa cannot observe "
                & "(no fabricated presence)");
         Check (Ada.Strings.Fixed.Index (Content, """total"": 20") > 0
                and then Ada.Strings.Fixed.Index (Content, """present"": 3") > 0,
                "sas.json's summary: 3 of 20 items present (requirements data, "
                & "source code, and the SAS document itself)");
      end;
      declare
         Md : constant String := Fusa.Files.Read_File (Sas_Root & "/sas.md");
      begin
         Check (Ada.Strings.Fixed.Index (Md, "# Software Accomplishment Summary") = 1,
                "sas.md starts with a level-1 heading");
         Check (Ada.Strings.Fixed.Index (Md, "Software Requirements Data") > 0
                and then Ada.Strings.Fixed.Index (Md, "3/20 present") > 0,
                "sas.md's checklist table and summary match sas.json");
      end;

      --  fusa:test REQ-120: sas has no input file of its own, so section
      --  1.6.2's carry-forward MUST is exercised by re-running the
      --  command over an sas.json a prior run (or a human) already
      --  attested -- the same attestation object must come back
      --  unchanged rather than being silently dropped.
      declare
         Doc : Unbounded_String :=
           To_Unbounded_String
             (Fusa.Files.Read_File (Sas_Root & "/sas.json"));
         Close_Brace : constant Natural :=
           Ada.Strings.Fixed.Index
             (To_String (Doc), "}", Ada.Strings.Backward);
      begin
         Insert
           (Doc, Close_Brace,
            "," & """attestation"": {""status"": ""reviewed""," &
              """implementationAuthor"": ""auto""," &
              """independentReviewer"": ""Jane Doe <jane@example.com>""}");
         Fusa.Files.Write_File (Sas_Root & "/sas.json", To_String (Doc));
      end;
      Check (Fusa.Cli.Run (Args ("sas", "--dir", Sas_Root)) = Exit_Ok,
             "sas re-run exits 0 after a prior sas.json was hand-attested");
      declare
         Content : constant String :=
           Fusa.Files.Read_File (Sas_Root & "/sas.json");
      begin
         Check (Ada.Strings.Fixed.Index (Content, """attestation"":") > 0
                and then Ada.Strings.Fixed.Index
                           (Content, """status"": ""reviewed""") > 0,
                "sas carries a prior run's attestation forward onto the "
                & "freshly-regenerated document rather than discarding it");
      end;

      --  Regression: Fusa.Files.Read_File wraps every OS-level failure
      --  (not just malformed JSON) as Read_Error -- an unreadable prior
      --  sas.json (permission denied) must degrade to "no attestation to
      --  carry forward", not crash the whole run.
      declare
         function C_Chmod
           (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int)
            return Interfaces.C.int;
         pragma Import (C, C_Chmod, "chmod");

         procedure Chmod (Path : String; Mode : Interfaces.C.int) is
            C_Path : Interfaces.C.Strings.chars_ptr :=
              Interfaces.C.Strings.New_String (Path);
            Rc     : Interfaces.C.int;
            pragma Unreferenced (Rc);
         begin
            Rc := C_Chmod (C_Path, Mode);
            Interfaces.C.Strings.Free (C_Path);
         end Chmod;
      begin
         --  Write-only, no read permission -- unreadable (what this
         --  regression is about) without also blocking the write this
         --  same command run needs to perform to regenerate sas.json.
         Chmod (Sas_Root & "/sas.json", 8#200#);
         Check (Fusa.Cli.Run (Args ("sas", "--dir", Sas_Root)) = Exit_Ok,
                "sas re-run exits 0 (not a crash) when the prior sas.json "
                & "is unreadable -- degrades to no attestation to carry "
                & "forward, same as a malformed prior file");
         Chmod (Sas_Root & "/sas.json", 8#644#);
      end;
      Ada.Directories.Delete_Tree (Sas_Root);
   end;

   --  fusa:test REQ-115
   Check (Fusa.Cli.Run (Args ("template")) = Exit_Usage,
          "template with no subcommand exits 2");
   Check (Fusa.Cli.Run (Args ("template", "bogus")) = Exit_Usage,
          "template with an unknown subcommand exits 2");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("template", "list"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "template list exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Text, "default:") > 0,
             "template list mentions the default template");
   end;
   Check (Fusa.Cli.Run (Args ("template", "list", "--format", "bogus")) = Exit_Usage,
          "template list rejects an unsupported --format with a usage error");
   declare
      Tmpl_Root : constant String := "tmp_test_cli_template";
   begin
      if Ada.Directories.Exists (Tmpl_Root) then
         Ada.Directories.Delete_Tree (Tmpl_Root);
      end if;
      Check (Fusa.Cli.Run (Args ("template", "apply")) = Exit_Usage,
             "template apply with no name exits 2");
      Check (Fusa.Cli.Run
               (Args ("template", "apply", "bogus", "--dir", Tmpl_Root)) = Exit_Usage,
             "template apply with an unknown template name exits 2");
      Check (Fusa.Cli.Run
               (Args ("template", "apply", "default", "--dir", Tmpl_Root,
                      "--project-name", "demoapp")) = Exit_Ok,
             "template apply default exits 0");
      Check (Fusa.Files.Exists (Tmpl_Root & "/demoapp.gpr")
             and then Fusa.Files.Exists (Tmpl_Root & "/README.md")
             and then Fusa.Files.Exists (Tmpl_Root & "/.github/workflows/ci.yml")
             and then Fusa.Files.Is_Directory (Tmpl_Root & "/src")
             and then Fusa.Files.Is_Directory (Tmpl_Root & "/tests"),
             "template apply default scaffolds the .gpr, README, CI workflow, "
             & "and src/tests directories");
      Check (not Fusa.Files.Exists (Tmpl_Root & "/LICENSE"),
             "template apply never writes a LICENSE file -- that's the "
             & "user's own legal/business decision");
      declare
         Readme : constant String := Fusa.Files.Read_File (Tmpl_Root & "/README.md");
      begin
         Check (Ada.Strings.Fixed.Index (Readme, "choose and add a LICENSE") > 0,
                "the scaffolded README explicitly tells the user to add a LICENSE");
      end;
      Fusa.Files.Write_File (Tmpl_Root & "/demoapp.gpr", "-- customised by the user");
      Check (Fusa.Cli.Run
               (Args ("template", "apply", "default", "--dir", Tmpl_Root,
                      "--project-name", "demoapp")) = Exit_Ok,
             "re-applying the template without --force still exits 0");
      Check (Fusa.Files.Read_File (Tmpl_Root & "/demoapp.gpr") = "-- customised by the user",
             "re-applying without --force leaves an already-customised file untouched");
      Check (Fusa.Cli.Run
               (Args ("template", "apply", "default", "--dir", Tmpl_Root,
                      "--project-name", "demoapp", "--force")) = Exit_Ok,
             "re-applying with --force exits 0");
      Check (Fusa.Files.Read_File (Tmpl_Root & "/demoapp.gpr") /= "-- customised by the user",
             "re-applying with --force overwrites the customised file");
      Ada.Directories.Delete_Tree (Tmpl_Root);
   end;

   --  fusa:test REQ-116
   declare
      Fix_Root : constant String := "tmp_test_cli_fix";
      Src_Path : constant String := Fix_Root & "/src/messy.adb";
      Messy    : constant String :=
        "procedure Messy is  " & ASCII.LF & "begin" & ASCII.LF & ASCII.LF & ASCII.LF &
        "   null;" & ASCII.LF & "end Messy;" & ASCII.LF;
   begin
      if Ada.Directories.Exists (Fix_Root) then
         Ada.Directories.Delete_Tree (Fix_Root);
      end if;
      Ada.Directories.Create_Path (Fix_Root & "/src");
      Fusa.Files.Write_File
        (Fix_Root & "/.fusa.json", "{""project"":{""name"":""t""},""standard"":""generic""}");
      Fusa.Files.Write_File (Fix_Root & "/.fusa-reqs.json", "{""requirements"":[]}");
      Fusa.Files.Write_File (Src_Path, Messy);

      Check (Fusa.Cli.Run (Args ("fix", "--dir", Fix_Root, "--format", "bogus")) = Exit_Usage,
             "fix --format bogus exits 2");

      Check (Fusa.Cli.Run (Args ("fix", "--dir", Fix_Root)) = Exit_Gate_Fail,
             "fix without --apply gate-fails when a file would change "
             & "(the gofmt -l / prettier --check pattern)");
      Check (Fusa.Files.Read_File (Src_Path) = Messy,
             "fix without --apply NEVER writes to disk -- the file is byte-for-byte "
             & "unchanged after a dry run");

      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout (Args ("fix", "--dir", Fix_Root), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Text, "would fix  src/messy.adb") > 0,
                "fix's dry-run text output names the file that would change, "
                & "prefixed 'would fix', not 'fixed'");
      end;

      Check (Fusa.Cli.Run (Args ("fix", "--dir", Fix_Root, "--apply")) = Exit_Ok,
             "fix --apply exits 0");
      Check (Fusa.Files.Read_File (Src_Path) /=
               Messy,
             "fix --apply actually rewrote the file this time");
      Check (Ada.Strings.Fixed.Index (Fusa.Files.Read_File (Src_Path), "  " & ASCII.LF) = 0,
             "the applied fix actually removed the trailing whitespace");

      Check (Fusa.Cli.Run (Args ("fix", "--dir", Fix_Root)) = Exit_Ok,
             "re-running fix (dry-run) after --apply exits 0 -- nothing left to fix "
             & "(Fix_Content is idempotent)");
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("fix", "--dir", Fix_Root, "--format", "json"), Exit_Code);
      begin
         Check (Ada.Strings.Fixed.Index (Out_Json, """files"": []") > 0,
                "fix --format json reports an empty files array once nothing needs fixing");
      end;

      Ada.Directories.Delete_Tree (Fix_Root);
   end;

   --  fusa:test REQ-090
   Check (Fusa.Cli.Run (Args ("req")) = Exit_Usage, "req with no subcommand exits 2");
   Check (Fusa.Cli.Run (Args ("req", "bogus")) = Exit_Usage,
          "req with an unknown subcommand exits 2");
   Check (Fusa.Cli.Run (Args ("req", "add", "REQ-900", "A new req", "--dir", Root)) = Exit_Ok,
          "req add with an id and title exits 0");
   Check (Fusa.Cli.Run (Args ("req", "add", "REQ-900", "dup", "--dir", Root)) = Exit_Usage,
          "req add rejects a duplicate id");
   Check (Fusa.Cli.Run (Args ("req", "add", "REQ-901", "--dir", Root)) = Exit_Usage,
          "req add requires both <id> and <title>");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("req", "list", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """id"": ""REQ-900""") > 0,
             "req list --format json includes the newly added requirement");
   end;
   --  Regression: req/disposition/pr/template list all fell through to
   --  plain text for any --format value that wasn't exactly "json",
   --  silently accepting bogus values instead of rejecting them like
   --  every other --format-taking command.
   Check (Fusa.Cli.Run (Args ("req", "list", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "req list rejects an unsupported --format with a usage error");

   --  fusa:test REQ-091
   --  fusa:test REQ-088
   Check (Fusa.Cli.Run (Args ("disposition", "add", "ADA001", "accepted", "reviewed",
                              "--dir", Root)) = Exit_Ok,
          "disposition add with a bare rule id exits 0");
   Check (Fusa.Cli.Run (Args ("disposition", "add", "ADA002", "bogus", "x",
                              "--dir", Root)) = Exit_Usage,
          "disposition add rejects an unrecognised status");
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout
          (Args ("disposition", "list", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """ruleId"": ""ADA001""") > 0
             and then Ada.Strings.Fixed.Index (Out_Text, """status"": ""accepted""") > 0,
             "disposition list --format json includes the newly added entry");
   end;
   Check (Fusa.Cli.Run
            (Args ("disposition", "list", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "disposition list rejects an unsupported --format with a usage error");

   --  fusa:test REQ-091: section 4.2's content-based fingerprint folds
   --  digit differences together, so two distinct findings (same rule,
   --  same file, messages differing only in a number) can share one
   --  fingerprint. This isn't something to route around in the
   --  fingerprint algorithm itself (the spec MUST-mandates the exact
   --  algorithm for cross-tool compatibility) -- instead, `disposition
   --  add` warns the human up front when the fingerprint they're about
   --  to waive currently matches more than one real finding.
   declare
      Fp_Root : constant String := "tmp_test_cli_fp_collision";
      Shared_Fp : Unbounded_String := Null_Unbounded_String;
   begin
      if Ada.Directories.Exists (Fp_Root) then
         Ada.Directories.Delete_Tree (Fp_Root);
      end if;
      Ada.Directories.Create_Path (Fp_Root & "/src");
      Fusa.Files.Write_File
        (Fp_Root & "/.fusa.json",
         "{""project"":{""name"":""t""},""standard"":""generic""}");
      declare
         --  Two ADA005 (line-too-long) findings whose actual lengths
         --  differ (86 vs 96 characters) -- so the pre-normalization
         --  messages differ ("...(86)" vs "...(96)") but Normalize_Message
         --  folds both digit runs to "#", producing one identical
         --  normalized message and hence one shared fingerprint.
         Long_86 : constant String := "   -- " & String'(1 .. 80 => 'x');
         Long_96 : constant String := "   -- " & String'(1 .. 90 => 'y');
      begin
         Fusa.Files.Write_File
           (Fp_Root & "/src/x.adb",
            "procedure X is" & ASCII.LF &
              "begin" & ASCII.LF &
              Long_86 & ASCII.LF &
              "   null;" & ASCII.LF &
              Long_96 & ASCII.LF &
              "   null;" & ASCII.LF &
              "end X;" & ASCII.LF);
      end;
      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("check", "--dir", Fp_Root, "--format", "json"), Exit_Code);
         Fp_Key   : constant String := """fingerprint"": """;
         Fp_Start : constant Natural :=
           Ada.Strings.Fixed.Index (Out_Json, Fp_Key);
      begin
         Shared_Fp := To_Unbounded_String
           (Out_Json (Fp_Start + Fp_Key'Length ..
                        Ada.Strings.Fixed.Index
                          (Out_Json, """", Fp_Start + Fp_Key'Length) - 1));
      end;
      declare
         Exit_Code : Integer;
         Out_Text  : constant String :=
           Run_Capturing_Stdout
             (Args ("disposition", "add", To_String (Shared_Fp), "accepted",
                     "line length is intentional", "--dir", Fp_Root),
              Exit_Code);
      begin
         Check (Exit_Code = Exit_Ok,
                "disposition add on a colliding fingerprint still succeeds "
                & "(the warning is advisory, not blocking)");
         Check (Ada.Strings.Fixed.Index (Out_Text, "currently matches") > 0,
                "disposition add warns when the fingerprint being waived "
                & "currently matches more than one finding");
      end;
      Ada.Directories.Delete_Tree (Fp_Root);
   end;

   --  fusa:test REQ-095
   declare
      Pr_Root : constant String := "tmp_test_cli_pr";
   begin
      if Ada.Directories.Exists (Pr_Root) then
         Ada.Directories.Delete_Tree (Pr_Root);
      end if;
      Ada.Directories.Create_Path (Pr_Root);
      --  fusa:test REQ-089
      Check (Fusa.Cli.Run (Args ("pr", "init", "--dir", Pr_Root)) = Exit_Ok,
             "pr init exits 0 and creates .fusa-pr.json");
      Check (Fusa.Files.Exists (Pr_Root & "/.fusa-pr.json"), "pr init created .fusa-pr.json");
      Check (Fusa.Cli.Run
               (Args ("pr", "add", "PR-001", "crash on startup", "--dir", Pr_Root)) = Exit_Ok,
             "pr add exits 0");
      Check (Fusa.Cli.Run (Args ("pr", "close", "PR-999", "--dir", Pr_Root)) = Exit_Usage,
             "pr close on an unknown id exits 2");
      Check (Fusa.Cli.Run (Args ("pr", "close", "PR-001", "--dir", Pr_Root)) = Exit_Ok,
             "pr close on a known id exits 0");
      Check (Fusa.Cli.Run (Args ("pr", "list", "--dir", Pr_Root, "--format", "bogus")) = Exit_Usage,
             "pr list rejects an unsupported --format with a usage error");
      declare
         Reports : constant Fusa.Config.Problem_Report_List := Fusa.Config.Load_Pr (Pr_Root);
      begin
         Check (Natural (Reports.Length) = 1
                and then To_String (Reports.Element (1).Status) = "closed",
                "the closed PR's status is persisted as closed");
      end;
      Ada.Directories.Delete_Tree (Pr_Root);
   end;

   --  fusa:test REQ-094
   Check (Fusa.Cli.Run (Args ("metrics", "record", "--dir", Root)) = Exit_Ok,
          "metrics record exits 0");
   Check (Fusa.Files.Exists (Root & "/.fusa-metrics.json"),
          "metrics record created .fusa-metrics.json");
   Check (Fusa.Cli.Run (Args ("metrics", "record", "--dir", Root)) = Exit_Ok,
          "a second metrics record exits 0 (appends, does not overwrite)");
   declare
      Snapshots : constant Fusa.Config.Metric_Snapshot_List := Fusa.Config.Load_Metrics (Root);
   begin
      Check (Natural (Snapshots.Length) = 2,
             "two metrics record calls produce two accumulated snapshots");
   end;

   --  fusa:test REQ-093
   declare
      Sign_Root : constant String := "tmp_test_cli_sign";
   begin
      if Ada.Directories.Exists (Sign_Root) then
         Ada.Directories.Delete_Tree (Sign_Root);
      end if;
      Ada.Directories.Create_Path (Sign_Root);
      Fusa.Files.Write_File (Sign_Root & "/evidence.txt", "important data");

      Check (Fusa.Cli.Run (Args ("sign")) = Exit_Usage, "sign with no subcommand exits 2");
      Check (Fusa.Cli.Run
               (Args ("sign", "sign", Sign_Root & "/evidence.txt")) = Exit_Usage,
             "sign sign without --key exits 2 (usage)");
      Check (Fusa.Cli.Run
               (Args ("sign", "sign", Sign_Root & "/evidence.txt", "--key", "k")) = Exit_Ok,
             "sign sign with --key exits 0");
      Check (Fusa.Files.Exists (Sign_Root & "/evidence.txt.sig"), "sign sign wrote a .sig file");
      Check (Fusa.Cli.Run
               (Args ("sign", "verify", Sign_Root & "/evidence.txt", "--key", "k")) = Exit_Ok,
             "sign verify with the correct key exits 0");
      Check (Fusa.Cli.Run
               (Args ("sign", "verify", Sign_Root & "/evidence.txt", "--key", "wrong"))
             = Exit_Gate_Fail,
             "sign verify with the wrong key exits 1 (gate fail)");

      --  Regression: sign accepted --dir syntactically (to avoid
      --  misparsing its value as the positional <file>) but never
      --  actually resolved <file>/--sig/--key-file against it.
      Check (Fusa.Cli.Run
               (Args ("sign", "sign", "evidence.txt", "--key", "k",
                       "--dir", Sign_Root)) = Exit_Ok,
             "sign sign resolves a relative <file> against --dir");
      Check (Fusa.Cli.Run
               (Args ("sign", "verify", "evidence.txt", "--key", "k",
                       "--dir", Sign_Root)) = Exit_Ok,
             "sign verify resolves a relative <file> against --dir too");
      Ada.Directories.Delete_Tree (Sign_Root);
   end;

   --  fusa:test REQ-092
   declare
      Hooks_Root : constant String := "tmp_test_cli_hooks";
   begin
      if Ada.Directories.Exists (Hooks_Root) then
         Ada.Directories.Delete_Tree (Hooks_Root);
      end if;
      Ada.Directories.Create_Path (Hooks_Root & "/.git");
      Check (Fusa.Cli.Run (Args ("hooks")) = Exit_Usage, "hooks with no subcommand exits 2");
      Check (Fusa.Cli.Run (Args ("hooks", "install", "--dir", Hooks_Root)) = Exit_Ok,
             "hooks install exits 0 in a git repository");
      Check (Fusa.Files.Exists (Hooks_Root & "/.git/hooks/pre-commit"),
             "hooks install wrote .git/hooks/pre-commit");
      --  Regression: Make_Executable used to discard chmod()'s return
      --  code, so a chmod failure would have gone unnoticed and left a
      --  non-executable hook that git silently skips -- assert the file
      --  is actually executable, not just present.
      Check (GNAT.OS_Lib.Is_Executable_File (Hooks_Root & "/.git/hooks/pre-commit"),
             "the installed pre-commit hook is actually executable "
             & "(chmod succeeded)");
      Check (Fusa.Cli.Run (Args ("hooks", "remove", "--dir", Hooks_Root)) = Exit_Ok,
             "hooks remove exits 0");
      Check (not Fusa.Files.Exists (Hooks_Root & "/.git/hooks/pre-commit"),
             "hooks remove deleted the pre-commit hook");
      Ada.Directories.Delete_Tree (Hooks_Root);
   end;
   declare
      No_Git_Root : constant String := "tmp_test_cli_nogit";
   begin
      if Ada.Directories.Exists (No_Git_Root) then
         Ada.Directories.Delete_Tree (No_Git_Root);
      end if;
      Ada.Directories.Create_Path (No_Git_Root);
      Check (Fusa.Cli.Run (Args ("hooks", "install", "--dir", No_Git_Root)) = Exit_Runtime,
             "hooks install outside a git repository exits 3 (runtime error)");
      Ada.Directories.Delete_Tree (No_Git_Root);
   end;

   --  trace: no requirements yet -> zero totals, still exits 0
   --  fusa:test REQ-011
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root)) = Exit_Ok,
          "trace with no requirements file exits 0");
   Check (Fusa.Cli.Run (Args ("trace", "--dir", Root, "--format", "json")) = Exit_Ok,
          "trace --format json exits 0");
   --  Regression: trace --format json used to omit the section 3.2
   --  report-extension fields (projectRoot MUST, standard SHOULD, ...)
   --  entirely.
   declare
      Exit_Code : Integer;
      Out_Text  : constant String :=
        Run_Capturing_Stdout (Args ("trace", "--dir", Root, "--format", "json"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Out_Text, """projectRoot"": """) > 0,
             "trace --format json now includes the MUST projectRoot field");
      --  Regression: presence-only checks would still pass for an
      --  absolute path to the wrong directory, or a "standard" pulled
      --  from a different source than the project's actual config.
      Check (Ada.Strings.Fixed.Index (Out_Text, "/" & Root & """") > 0,
             "trace --format json's projectRoot resolves to the actual "
             & "project directory");
      Check (Ada.Strings.Fixed.Index
               (Out_Text, """standard"": ""generic""") > 0,
             "trace --format json's standard carries the project's "
             & "actual configured value (""generic"")");
   end;
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
               (Args ("init", "--dir", Func_Strict_Root, "--name", "t",
                      "--standard", "generic")) = Exit_Ok,
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

      declare
         Exit_Code : Integer;
         Out_Json  : constant String :=
           Run_Capturing_Stdout
             (Args ("check", "--dir", No_Cfg_Dir, "--format", "json"), Exit_Code);
      begin
         Check (Exit_Code = Exit_Runtime,
                "check --format json on a no-config directory still exits 3");
         Check (Ada.Strings.Fixed.Index (Out_Json, """code"": ""no-config""") > 0,
                "the JSON-format runtime error carries the structured error.code field");
      end;
      declare
         Exit_Code : Integer;
      begin
         Exit_Code := Fusa.Cli.Run (Args ("trace", "--dir", No_Cfg_Dir, "--format", "json"));
         Check (Exit_Code = Exit_Runtime, "trace on a no-config directory exits 3");
      end;
   end;

   --  fusa:test REQ-007
   declare
      Exit_Code : Integer;
      Out_Json  : constant String :=
        Run_Capturing_Stdout (Args ("version", "--format", "json"), Exit_Code);
   begin
      Check (Exit_Code = Exit_Ok, "version --format json exits 0");
      Check (Ada.Strings.Fixed.Index (Out_Json, """tool"": ""ada-FuSa""") > 0
             and then Ada.Strings.Fixed.Index (Out_Json, """specVersion"":") > 0,
             "version --format json carries the tool and specVersion fields (no envelope)");
   end;

   declare
      Exit_Code : Integer;
      Sarif     : constant String :=
        Run_Capturing_Stdout (Args ("check", "--dir", Root, "--format", "sarif"), Exit_Code);
   begin
      Check (Ada.Strings.Fixed.Index (Sarif, """version"": ""2.1.0""") > 0,
             "check --format sarif produces a valid SARIF document");
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

      Check (Fusa.Cli.Run
               (Args ("init", "--dir", Root2, "positional-name",
                      "--standard", "generic")) = Exit_Ok,
             "init accepts a positional project name");
      Check (Fusa.Cli.Run
               (Args ("init", "--dir", Root2, "--name", "ignored",
                      "--standard", "generic")) = Exit_Ok,
             "a second init without --force still exits 0 (name/standard "
             & "are still required, but the existing config file is left alone)");

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
