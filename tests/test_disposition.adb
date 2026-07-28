with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Config;
with Fusa.Files;
with Fusa.Report;
with Test_Framework; use Test_Framework;

procedure Test_Disposition is
   Root : constant String := "tmp_test_disposition";

   function Count_By_Rule (Findings : Finding_List; Rule_Id : String) return Natural is
      N : Natural := 0;
   begin
      for F of Findings loop
         if To_String (F.Rule_Id) = Rule_Id then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count_By_Rule;
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root);

   Check (not Fusa.Config.Dispositions_Exist (Root),
          "no dispositions file initially");
   declare
      Empty : constant Fusa.Config.Disposition_List :=
        Fusa.Config.Load_Dispositions (Root);
   begin
      Check (Natural (Empty.Length) = 0,
             "Load_Dispositions returns an empty list when absent");
   end;

   --  fusa:test REQ-071
   Fusa.Files.Write_File
     (Root & "/.fusa-dispositions.json",
      "{""dispositions"":[" &
      "{""fingerprint"":""sha256:aaa"",""status"":""accepted"",""note"":""n1""}," &
      "{""ruleId"":""ADA002"",""file"":""src/x.adb"",""line"":5,""status"":""deferred""}," &
      "{""ruleId"":""ADA003"",""status"":""rejected""}," &
      "{""ruleId"":""ADA009"",""status"":""bogus""}" &
      "]}");

   Check (Fusa.Config.Dispositions_Exist (Root), "dispositions file now exists");

   declare
      Disps : constant Fusa.Config.Disposition_List :=
        Fusa.Config.Load_Dispositions (Root);
   begin
      Check (Natural (Disps.Length) = 4, "all four entries parsed, "
             & "including the one with an unrecognised status");
      Check (Disps.Element (1).Status = Accepted, "status 'accepted' parses correctly");
      Check (Disps.Element (2).Status = Deferred
             and then Disps.Element (2).Line = 5,
             "status 'deferred' and numeric 'line' parse correctly");
      Check (Disps.Element (3).Status = Rejected, "status 'rejected' parses correctly");
      Check (Disps.Element (4).Status = Open,
             "an unrecognised status value is not applied (stays Open)");

      --  fusa:test REQ-072
      declare
         Findings : Finding_List;
         Orphans  : Finding_List;
      begin
         Findings.Append
           (Make_Finding ("ADA001", Error, "e1", Make_Location ("src/a.adb", 1)));
         --  Fingerprint match
         declare
            F : Finding := Make_Finding ("ADA001", Error, "fp-match",
                                          Make_Location ("src/z.adb", 9));
         begin
            F.Fingerprint := To_Unbounded_String ("sha256:aaa");
            Findings.Append (F);
         end;
         --  ruleId+file+line match
         Findings.Append
           (Make_Finding ("ADA002", Warning, "rfl-match",
                          Make_Location ("src/x.adb", 5)));
         --  ruleId+file+line MISS (wrong line)
         Findings.Append
           (Make_Finding ("ADA002", Warning, "rfl-miss",
                          Make_Location ("src/x.adb", 6)));
         --  rule-level match (ADA003, no file/line on the entry)
         Findings.Append
           (Make_Finding ("ADA003", Error, "rule-level-match",
                          Make_Location ("src/anywhere.adb", 99)));

         Fusa.Config.Apply_Dispositions (Findings, Disps, Orphans);

         declare
            F1 : constant Finding := Findings.Element (2); -- fp-match
            F2 : constant Finding := Findings.Element (3); -- rfl-match
            F3 : constant Finding := Findings.Element (4); -- rfl-miss
            F4 : constant Finding := Findings.Element (5); -- rule-level-match
         begin
            Check (F1.Disposition = Accepted,
                   "a finding whose fingerprint matches an entry is dispositioned "
                   & "by that entry's status, even when ruleId/file/line also "
                   & "happen to differ");
            Check (F2.Disposition = Deferred,
                   "a finding matches via ruleId+file+line fallback when no "
                   & "fingerprint match exists");
            Check (F3.Disposition = Open,
                   "a finding with the right ruleId+file but wrong line does "
                   & "not match the ruleId+file+line entry");
            Check (F4.Disposition = Rejected,
                   "a finding matches a rule-level (ruleId-only) entry when no "
                   & "file/line is given on the disposition");
         end;

         Check (Natural (Orphans.Length) = 0,
                "no orphan warnings when every accepted/deferred entry "
                & "matched a finding (the bogus-status entry is not an "
                & "orphan candidate -- it never applies to anything)");
      end;
   end;

   --  An accepted entry that matches no current finding is a genuine
   --  orphaned waiver and SHOULD warn (category config).
   declare
      Disps : Fusa.Config.Disposition_List;
      E     : Fusa.Config.Disposition_Entry;
      Findings : Finding_List;
      Orphans  : Finding_List;
   begin
      E.Fingerprint := To_Unbounded_String ("sha256:stale");
      E.Status      := Accepted;
      Disps.Append (E);
      Fusa.Config.Apply_Dispositions (Findings, Disps, Orphans);
      Check (Count_By_Rule (Orphans, "DISP001") = 1,
             "an accepted entry matching no finding produces exactly one "
             & "orphaned-disposition warning");
      for O of Orphans loop
         Check (O.Severity = Warning, "an orphaned disposition warning is severity WARNING");
         Check (O.Category = Config_Category,
                "an orphaned disposition warning has category 'config'");
      end loop;
   end;

   --  A rejected orphan (waiver denied, no matching finding) must be
   --  silent -- the denied finding was resolved, which is success.
   Fusa.Files.Write_File
     (Root & "/.fusa-dispositions.json",
      "{""dispositions"":[{""ruleId"":""ADA099"",""status"":""rejected""}]}");
   declare
      Disps    : constant Fusa.Config.Disposition_List :=
        Fusa.Config.Load_Dispositions (Root);
      Findings : Finding_List;
      Orphans  : Finding_List;
   begin
      Fusa.Config.Apply_Dispositions (Findings, Disps, Orphans);
      Check (Natural (Orphans.Length) = 0,
             "an orphaned 'rejected' entry emits no warning (silent per spec)");
   end;

   --  fusa:test REQ-070
   --  Regression: Has_Gate_Failure previously only excluded Disposition =
   --  Open from gating, which meant a "rejected" finding (a denied waiver,
   --  still open per spec section 4.1) would incorrectly stop gating too.
   declare
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "e", Make_Location ("a.adb"),
                       Disposition => Rejected));
      Check (Fusa.Report.Has_Gate_Failure (Findings, False),
             "a 'rejected' finding still gates -- rejected means the waiver "
             & "request was denied, not that the finding is dismissed");
   end;
   declare
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "e", Make_Location ("a.adb"),
                       Disposition => Accepted));
      Check (not Fusa.Report.Has_Gate_Failure (Findings, False),
             "an 'accepted' finding does not gate");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Disposition;
