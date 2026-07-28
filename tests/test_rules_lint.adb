with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Rules_Lint;
with Fusa.Files;
with Fusa.Report;
with Test_Framework; use Test_Framework;

procedure Test_Rules_Lint is
   Root : constant String := "tmp_test_rules_lint";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   --  Trailing whitespace, a run of 3 consecutive blank lines, and a
   --  correctly-terminated final line.
   Fusa.Files.Write_File
     (Root & "/src/messy.adb",
      "procedure Messy is  " & ASCII.LF &
      "begin" & ASCII.LF &
      ASCII.LF & ASCII.LF & ASCII.LF &
      "   null;" & ASCII.LF &
      "end Messy;" & ASCII.LF);

   --  No trailing newline at all.
   Fusa.Files.Write_File (Root & "/src/no_trailing_nl.adb", "procedure P is begin null; end P;");

   --  Two trailing newlines (one too many).
   Fusa.Files.Write_File
     (Root & "/src/extra_trailing_nl.adb",
      "procedure Q is begin null; end Q;" & ASCII.LF & ASCII.LF);

   --  Perfectly clean file.
   Fusa.Files.Write_File
     (Root & "/src/clean.adb",
      "procedure Clean is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "end Clean;" & ASCII.LF);

   declare
      Files : String_List;
   begin
      Files.Append ("src/messy.adb");
      Files.Append ("src/no_trailing_nl.adb");
      Files.Append ("src/extra_trailing_nl.adb");
      Files.Append ("src/clean.adb");

      declare
         Findings : constant Finding_List := Fusa.Rules_Lint.Scan (Root, Files);
         Lint001, Lint002, Lint003 : Natural := 0;
      begin
         for F of Findings loop
            --  fusa:test REQ-111
            if To_String (F.Rule_Id) = "LINT001" then
               Lint001 := Lint001 + 1;
               Check (To_String (F.Loc.File) = "src/messy.adb",
                      "LINT001 fires on messy.adb's trailing-whitespace line");
            elsif To_String (F.Rule_Id) = "LINT002" then
               Lint002 := Lint002 + 1;
            elsif To_String (F.Rule_Id) = "LINT003" then
               Lint003 := Lint003 + 1;
            end if;
         end loop;
         Check (Lint001 = 1, "LINT001 fires exactly once (one line has trailing whitespace)");
         Check (Lint002 = 1,
                "LINT002 fires exactly once for the run of 3 consecutive blank lines "
                & "(flagged once per run, not once per extra blank line)");
         Check (Lint003 = 2,
                "LINT003 fires for both no_trailing_nl.adb (missing) and "
                & "extra_trailing_nl.adb (one too many), but not for messy.adb or "
                & "clean.adb, which both end correctly");
         Check (not Fusa.Report.Has_Gate_Failure (Findings, False),
                "all LINT findings are WARNING and never gate without --strict");
         Check (Fusa.Report.Has_Gate_Failure (Findings, True),
                "LINT findings do gate under --strict, like any other WARNING");
      end;
   end;

   declare
      Clean_Only : String_List;
   begin
      Clean_Only.Append ("src/clean.adb");
      Check (Fusa.Rules_Lint.Scan (Root, Clean_Only).Is_Empty,
             "a perfectly clean file produces no LINT findings at all");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Rules_Lint;
