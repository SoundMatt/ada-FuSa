with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Analyze;
with Fusa.Files;
with Fusa.Report;
with Test_Framework; use Test_Framework;

procedure Test_Analyze is
   Root : constant String := "tmp_test_analyze";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   Fusa.Files.Write_File
     (Root & "/src/unused.adb",
      "with Ada.Text_IO;" & ASCII.LF &
      "with Ada.Strings.Fixed;" & ASCII.LF &
      "procedure Unused is" & ASCII.LF &
      "begin" & ASCII.LF &
      "   Ada.Text_IO.Put_Line (""hi"");" & ASCII.LF &
      "end Unused;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/longparams.adb",
      "procedure Longparams" & ASCII.LF &
      "  (A : Integer; B : Integer; C : Integer; D : Integer;" & ASCII.LF &
      "   E : Integer; F : Integer; G : Integer)" & ASCII.LF &
      "is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Longparams;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/shortparams.adb",
      "procedure Shortparams (A, B, C : Integer) is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Shortparams;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/noparams.adb",
      "procedure Noparams is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Noparams;" & ASCII.LF);

   declare
      Files : String_List;
   begin
      Files.Append ("src/unused.adb");
      Files.Append ("src/longparams.adb");
      Files.Append ("src/shortparams.adb");
      Files.Append ("src/noparams.adb");

      declare
         Findings : constant Finding_List := Fusa.Analyze.Analyze (Root, Files);
         Anal001, Anal002 : Natural := 0;
      begin
         for F of Findings loop
            if To_String (F.Rule_Id) = "ANAL001" then
               Anal001 := Anal001 + 1;
               --  fusa:test REQ-110
               Check (F.Severity = Info,
                      "ANAL001 is always INFO severity (a false-positive-prone "
                      & "heuristic must never gate)");
            elsif To_String (F.Rule_Id) = "ANAL002" then
               Anal002 := Anal002 + 1;
               Check (To_String (F.Loc.File) = "src/longparams.adb",
                      "ANAL002 fires on the 7-parameter subprogram, not the "
                      & "3-parameter or 0-parameter ones");
            end if;
         end loop;
         Check (Anal001 = 1,
                "ANAL001 fires exactly once, for the truly-unused "
                & "Ada.Strings.Fixed with-clause -- not for Ada.Text_IO, "
                & "which is used via Ada.Text_IO.Put_Line");
         Check (Anal002 = 1,
                "ANAL002 fires exactly once, even though the opening '(' of "
                & "longparams.adb's parameter list is on the line AFTER "
                & "the procedure keyword, not the same line");
         Check (not Fusa.Report.Has_Gate_Failure (Findings, False),
                "ANAL001 (Info) and ANAL002 (Warning) never gate without --strict");
      end;
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Analyze;
