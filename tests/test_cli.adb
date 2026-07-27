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

   Fusa.Files.Write_File
     (Root & "/src/bad.adb",
      "procedure Bad is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "exception" & ASCII.LF & "   when others =>" & ASCII.LF &
      "      null;" & ASCII.LF & "end Bad;" & ASCII.LF);

   Check (Fusa.Cli.Run (Args ("check", "--dir", Root)) = Exit_Ok,
          "check exits 0 for a WARNING-only finding without --strict");
   Check (Fusa.Cli.Run (Args ("check", "--dir", Root, "--strict")) = Exit_Gate_Fail,
          "check --strict exits 1 (gate fail) once a WARNING is present");
   --  fusa:test REQ-015
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root)) = Exit_Ok,
          "report always exits 0, even with findings present");
   Check (Fusa.Cli.Run (Args ("report", "--dir", Root, "--strict")) = Exit_Usage,
          "report rejects --strict with a usage error");

   --  fusa:test REQ-012
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root)) = Exit_Ok,
          "qualify passes its own known-answer tests");
   Check (Fusa.Files.Exists (Root & "/qualify-report.json"),
          "qualify writes qualify-report.json by default");
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root, "--format", "json")) = Exit_Ok,
          "qualify --format json also exits 0");
   Check (Fusa.Cli.Run (Args ("qualify", "--dir", Root, "--format", "bogus")) = Exit_Usage,
          "qualify rejects an unsupported --format with a usage error");

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
end Test_Cli;
