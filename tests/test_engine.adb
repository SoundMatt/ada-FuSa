with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Engine;
with Fusa.Files;
with Fusa.Source_Scan;
with Fusa.Config;
with Fusa.Rules_Style;
pragma Unreferenced (Fusa.Rules_Style);
with Fusa.Rules_Project;
pragma Unreferenced (Fusa.Rules_Project);
with Test_Engine_Rules;
with Test_Framework; use Test_Framework;

procedure Test_Engine is
   Root : constant String := "tmp_test_engine";
begin
   --  fusa:test REQ-017
   --  fusa:test REQ-041
   Check (Fusa.Engine.Rule_Count >= 8, "at least the 8 starter rules are registered");

   declare
      Prev : Unbounded_String := Null_Unbounded_String;
      Ok   : Boolean := True;
   begin
      --  fusa:test REQ-038
      for I in 1 .. Fusa.Engine.Rule_Count loop
         declare
            Cur : constant String := Fusa.Engine.Get_Rule (I).Id;
         begin
            if Length (Prev) > 0 and then Cur < To_String (Prev) then
               Ok := False;
            end if;
            Prev := To_Unbounded_String (Cur);
         end;
      end loop;
      Check (Ok, "registered rules are ordered by ascending id");
   end;

   --  Description isn't consumed by any command yet (no `check --list-rules`
   --  or similar exists), so without this test every concrete rule's
   --  override of it would go completely unexercised.
   --  fusa:test REQ-038
   declare
      All_Non_Empty : Boolean := True;
   begin
      for I in 1 .. Fusa.Engine.Rule_Count loop
         if Fusa.Engine.Get_Rule (I).Description'Length = 0 then
            All_Non_Empty := False;
         end if;
      end loop;
      Check (All_Non_Empty, "every registered rule's Description is non-empty");
   end;

   declare
      --  Fusa.Engine's registry is a process-lifetime singleton, so a Rule
      --  handed to Register must outlive this test procedure -- allocate
      --  on the heap (matching how Rule_Access is meant to be populated),
      --  not a stack-local 'Access, which would dangle the moment this
      --  declare block exits and corrupt every later Run_All call.
      D      : constant Fusa.Engine.Rule_Access := new Test_Engine_Rules.Dummy_Rule;
      Raised : Boolean := False;
   begin
      --  fusa:test REQ-040
      begin
         Fusa.Engine.Register (D);
      exception
         when Fusa.Engine.Duplicate_Rule_Error =>
            Raised := True;
      end;
      Check (Raised, "registering a duplicate rule id raises Duplicate_Rule_Error");
   end;

   declare
      --  Sorts before every already-registered rule id ("ADA001".."ADA008"),
      --  exercising Register's "insert before an existing entry" branch,
      --  which the 8 starter rules never hit since they self-register in
      --  already-ascending order.
      F : constant Fusa.Engine.Rule_Access := new Test_Engine_Rules.First_Rule;
   begin
      Fusa.Engine.Register (F);
      Check (Fusa.Engine.Get_Rule (1).Id = "AAA001",
             "a rule sorting before all existing ones is inserted at the front, "
             & "not appended to the end");
   end;

   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");
   Fusa.Files.Write_File
     (Root & "/src/x.adb",
      "procedure X is" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end X;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/y.adb",
      "procedure Y is" & ASCII.LF &
      "   pragma Suppress (All_Checks); -- fusa:unsafe reviewed in SC-42" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Y;" & ASCII.LF);

   --  fusa:test REQ-039
   --  fusa:test REQ-042
   --  fusa:test REQ-056
   declare
      Cfg      : constant Fusa.Config.Project_Config := Fusa.Config.Default_Config ("t");
      Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Root, Cfg);
      Findings : constant Finding_List := Fusa.Engine.Run_All (Root, Files);
      Hits_X, Hits_Y : Natural := 0;
   begin
      Check (Natural (Files.Length) = 2, "source scan finds both fixture files");
      for Fnd of Findings loop
         if To_String (Fnd.Rule_Id) = "ADA001" then
            if To_String (Fnd.Loc.File) = "src/x.adb" then
               Hits_X := Hits_X + 1;
            elsif To_String (Fnd.Loc.File) = "src/y.adb" then
               Hits_Y := Hits_Y + 1;
            end if;
         end if;
      end loop;
      Check (Hits_X = 1, "ADA001 fires on an unjustified pragma Suppress");
      Check (Hits_Y = 0, "ADA001 is suppressed by a trailing -- fusa:unsafe comment");
   end;

   --  Regression: the "-- fusa:unsafe" suppression window (5 lines back,
   --  2 lines ahead) had no negative-path test proving a justification
   --  comment OUTSIDE that window fails to suppress -- only the trivial
   --  same-line case (Y.adb above) was covered, so a boundary-arithmetic
   --  bug (off-by-one, or an accidentally unbounded window) could have
   --  shipped undetected in either direction.
   Fusa.Files.Write_File
     (Root & "/src/lookback_in.adb",
      "procedure Lookback_In is" & ASCII.LF &
      "   -- fusa:unsafe justified" & ASCII.LF &
      "   null;" & ASCII.LF & "   null;" & ASCII.LF &
      "   null;" & ASCII.LF & "   null;" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Lookback_In;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/lookback_out.adb",
      "procedure Lookback_Out is" & ASCII.LF &
      "   -- fusa:unsafe justified" & ASCII.LF &
      "   null;" & ASCII.LF & "   null;" & ASCII.LF &
      "   null;" & ASCII.LF & "   null;" & ASCII.LF & "   null;" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Lookback_Out;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/lookahead_in.adb",
      "procedure Lookahead_In is" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "   null;" & ASCII.LF &
      "   -- fusa:unsafe justified" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Lookahead_In;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/lookahead_out.adb",
      "procedure Lookahead_Out is" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "   null;" & ASCII.LF & "   null;" & ASCII.LF &
      "   -- fusa:unsafe justified" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Lookahead_Out;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Hits_Back_In, Hits_Back_Out, Hits_Ahead_In, Hits_Ahead_Out : Natural := 0;
   begin
      Files.Append ("src/lookback_in.adb");
      Files.Append ("src/lookback_out.adb");
      Files.Append ("src/lookahead_in.adb");
      Files.Append ("src/lookahead_out.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA001" then
            if To_String (F.Loc.File) = "src/lookback_in.adb" then
               Hits_Back_In := Hits_Back_In + 1;
            elsif To_String (F.Loc.File) = "src/lookback_out.adb" then
               Hits_Back_Out := Hits_Back_Out + 1;
            elsif To_String (F.Loc.File) = "src/lookahead_in.adb" then
               Hits_Ahead_In := Hits_Ahead_In + 1;
            elsif To_String (F.Loc.File) = "src/lookahead_out.adb" then
               Hits_Ahead_Out := Hits_Ahead_Out + 1;
            end if;
         end if;
      end loop;
      Check (Hits_Back_In = 0,
             "a justification exactly 5 lines above the flagged line (the "
             & "edge of the lookback window) still suppresses");
      Check (Hits_Back_Out = 1,
             "a justification 6 lines above the flagged line (just outside "
             & "the lookback window) does NOT suppress -- the finding "
             & "still fires");
      Check (Hits_Ahead_In = 0,
             "a justification exactly 2 lines below the flagged line (the "
             & "edge of the lookahead window) still suppresses");
      Check (Hits_Ahead_Out = 1,
             "a justification 3 lines below the flagged line (just outside "
             & "the lookahead window) does NOT suppress -- the finding "
             & "still fires");
   end;

   --  Regression (critical security): a sourceDirs entry of "../..." used
   --  to escape the project root entirely -- Find_Source_Files would
   --  scan (and, downstream via `fix --apply`, could overwrite) files
   --  well outside Root. It must now be silently skipped, the same way a
   --  non-existent directory already is.
   --  fusa:test REQ-056
   declare
      Outside_Root : constant String := "tmp_test_engine_outside_secret";
   begin
      if Ada.Directories.Exists (Outside_Root) then
         Ada.Directories.Delete_Tree (Outside_Root);
      end if;
      Ada.Directories.Create_Path (Outside_Root);
      Fusa.Files.Write_File
        (Outside_Root & "/leak.ads", "package Leak is end Leak;" & ASCII.LF);

      declare
         Cfg : Fusa.Config.Project_Config := Fusa.Config.Default_Config ("t");
      begin
         Cfg.Source_Dirs.Append ("../" & Outside_Root);
         declare
            Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Root, Cfg);
         begin
            Check (Files.Is_Empty,
                   "a sourceDirs entry resolving outside the project root is "
                   & "silently skipped, not walked -- Find_Source_Files must never "
                   & "read (or let `fix --apply` later write) anything outside Root");
         end;
      end;
      Ada.Directories.Delete_Tree (Outside_Root);
   end;

   --  Regressions from the deep audit: case-sensitive / same-line-only /
   --  whitespace-brittle matching in the lint rules.
   Fusa.Files.Write_File
     (Root & "/src/z.adb",
      "procedure Z is" & ASCII.LF &
      "   PRAGMA SUPPRESS (All_Checks);" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Z;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/w.adb",
      "procedure W is" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "   -- fusa:unsafe justified two lines down" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end W;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/v.adb",
      "procedure V is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "exception" & ASCII.LF & "   when   others   =>" & ASCII.LF &
      "      null;" & ASCII.LF & "end V;" & ASCII.LF);

   declare
      Cfg      : constant Fusa.Config.Project_Config := Fusa.Config.Default_Config ("t");
      Files    : String_List;
   begin
      Files.Append ("src/z.adb");
      Files.Append ("src/w.adb");
      Files.Append ("src/v.adb");
      declare
         Findings : constant Finding_List := Fusa.Engine.Run_All (Root, Files);
         Hits_Z, Hits_W, Hits_V : Natural := 0;
      begin
         for Fnd of Findings loop
            if To_String (Fnd.Rule_Id) = "ADA001"
              and then To_String (Fnd.Loc.File) = "src/z.adb"
            then
               Hits_Z := Hits_Z + 1;
            elsif To_String (Fnd.Rule_Id) = "ADA001"
              and then To_String (Fnd.Loc.File) = "src/w.adb"
            then
               Hits_W := Hits_W + 1;
            elsif To_String (Fnd.Rule_Id) = "ADA002"
              and then To_String (Fnd.Loc.File) = "src/v.adb"
            then
               Hits_V := Hits_V + 1;
            end if;
         end loop;
         Check (Hits_Z = 1,
                "ADA001 fires on 'PRAGMA SUPPRESS' (uppercase -- Ada is "
                & "case-insensitive)");
         Check (Hits_W = 0,
                "ADA001 is suppressed by a -- fusa:unsafe comment two lines below");
         Check (Hits_V = 1,
                "ADA002 fires on 'when   others   =>' with extra alignment whitespace");
      end;
   end;

   --  fusa:test REQ-023
   Fusa.Files.Write_File
     (Root & "/src/u.adb",
      "procedure U is" & ASCII.LF &
      "   pragma Suppress (All_Checks);" & ASCII.LF &
      "   pragma Warnings (Off, ""x"");" & ASCII.LF &
      "   X : Integer := 1234567890123456789012345678901234567890123456789012345678901234567890;" & ASCII.LF &
      "begin" & ASCII.LF & ASCII.HT & "null;" & ASCII.LF & "end U;" & ASCII.LF);

   declare
      Cfg      : constant Fusa.Config.Project_Config := Fusa.Config.Default_Config ("t");
      Files    : String_List;
   begin
      Files.Append ("src/u.adb");
      declare
         Findings : constant Finding_List := Fusa.Engine.Run_All (Root, Files);
         Style_Category_Count, Safety_Category_Count : Natural := 0;
      begin
         for Fnd of Findings loop
            if (To_String (Fnd.Rule_Id) = "ADA005"
                or else To_String (Fnd.Rule_Id) = "ADA006"
                or else To_String (Fnd.Rule_Id) = "ADA008")
              and then Fnd.Category = Style
            then
               Style_Category_Count := Style_Category_Count + 1;
            elsif To_String (Fnd.Rule_Id) = "ADA001" and then Fnd.Category = Safety then
               Safety_Category_Count := Safety_Category_Count + 1;
            end if;
         end loop;
         Check (Style_Category_Count = 3,
                "ADA005 (line length), ADA006 (tabs), and ADA008 (Warnings "
                & "suppression) report category 'style', not the blanket "
                & "ADA -> safety mapping (#37)");
         Check (Safety_Category_Count = 1,
                "ADA001 (unjustified pragma Suppress) still reports category "
                & "'safety', unaffected by the ADA005/ADA006/ADA008 override");
      end;
   end;

   --  fusa:test REQ-078
   --  fusa:sec-test REQ-078
   --  Each case lives in its own file, far enough from any fusa:unsafe
   --  comment in another case that the Suppress_Lookback/Lookahead windows
   --  (5/2 lines) can't overlap between cases.
   Fusa.Files.Write_File
     (Root & "/src/sec1.adb",
      "procedure Sec1 is" & ASCII.LF &
      "   Password : constant String := ""hunter2"";" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Sec1;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/sec1_justified.adb",
      "procedure Sec1_Justified is" & ASCII.LF &
      "   -- fusa:unsafe test fixture only" & ASCII.LF &
      "   Password : constant String := ""hunter2"";" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Sec1_Justified;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/sec1_dynamic.adb",
      "procedure Sec1_Dynamic is" & ASCII.LF &
      "   Auth_Token : constant String := Read_Env_Var;" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Sec1_Dynamic;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/weak.adb",
      "with GNAT.MD5;" & ASCII.LF &
      "with GNAT.OS_Lib;" & ASCII.LF &
      "procedure Weak is" & ASCII.LF &
      "begin" & ASCII.LF &
      "   null;" & ASCII.LF &
      "end Weak;" & ASCII.LF);

   declare
      Files    : String_List;
      Findings : Finding_List;
      Sec001_Hits_Total, Sec001_Hits_Justified, Sec001_Hits_Dynamic : Natural := 0;
      Sec003_Hits : Natural := 0;
   begin
      Files.Append ("src/sec1.adb");
      Files.Append ("src/sec1_justified.adb");
      Files.Append ("src/sec1_dynamic.adb");
      Files.Append ("src/weak.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "SEC001" then
            if To_String (F.Loc.File) = "src/sec1.adb" then
               Sec001_Hits_Total := Sec001_Hits_Total + 1;
            elsif To_String (F.Loc.File) = "src/sec1_justified.adb" then
               Sec001_Hits_Justified := Sec001_Hits_Justified + 1;
            elsif To_String (F.Loc.File) = "src/sec1_dynamic.adb" then
               Sec001_Hits_Dynamic := Sec001_Hits_Dynamic + 1;
            end if;
         elsif To_String (F.Rule_Id) = "SEC003" then
            Sec003_Hits := Sec003_Hits + 1;
         end if;
      end loop;
      Check (Sec001_Hits_Total = 1,
             "SEC001 fires on an identifier ending in 'password' directly "
             & "assigned a string literal");
      Check (Sec001_Hits_Justified = 0,
             "SEC001 is suppressed by a preceding -- fusa:unsafe comment");
      Check (Sec001_Hits_Dynamic = 0,
             "SEC001 does not fire when the identifier doesn't contain "
             & "'password' at all, even for a similarly-themed name "
             & "like 'Auth_Token'");
      Check (Sec003_Hits = 1, "SEC003 fires on a GNAT.MD5 with-clause");
   end;

   --  Regression: Scan_Substring never stripped comments before matching,
   --  so a comment merely mentioning a flagged construct by name (not
   --  actually using it) produced a false-positive finding. Affects
   --  ADA001/ADA003/ADA004/ADA008/SEC003/SEC004; ADA001 is exercised here
   --  as the representative case.
   Fusa.Files.Write_File
     (Root & "/src/prose.adb",
      "procedure Prose is" & ASCII.LF &
      "   -- see ADA001: pragma Suppress disables a check, don't do it" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Prose;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Ada001_Hits : Natural := 0;
   begin
      Files.Append ("src/prose.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA001" then
            Ada001_Hits := Ada001_Hits + 1;
         end if;
      end loop;
      Check (Ada001_Hits = 0,
             "ADA001 does not fire on a comment that merely mentions "
             & """pragma Suppress"" by name -- comments are stripped "
             & "before matching");
   end;

   --  Regression: ADA007's "TODO" needle is only ever meaningful inside a
   --  comment -- Scan_Substring's comment-stripping fix above must not
   --  also blind ADA007 to the very comments it exists to find.
   Fusa.Files.Write_File
     (Root & "/src/deferred.adb",
      "procedure Deferred is" & ASCII.LF &
      "begin" & ASCII.LF & "   null; -- TODO fix this" & ASCII.LF & "end Deferred;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Ada007_Hits : Natural := 0;
   begin
      Files.Append ("src/deferred.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA007" then
            Ada007_Hits := Ada007_Hits + 1;
         end if;
      end loop;
      Check (Ada007_Hits = 1,
             "ADA007 still fires on a real ""-- TODO"" comment -- it is "
             & "exempted from the comment-stripping fix, since its whole "
             & "purpose is to scan comment text");
   end;

   --  Regression: ADA007's "TODO" needle used to be matched against the
   --  whole line (comments stripped would hide the marker it exists to
   --  find), which also matched any identifier merely containing "TODO",
   --  e.g. "Todo_List". Comment_Only now confines the search to the
   --  comment text specifically.
   Fusa.Files.Write_File
     (Root & "/src/todo_ident.adb",
      "procedure Todo_Ident is" & ASCII.LF &
      "   Todo_List : array (1 .. 3) of Integer := (others => 0);" &
      ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Todo_Ident;" &
      ASCII.LF);
   declare
      Files       : String_List;
      Findings    : Finding_List;
      Ada007_Hits : Natural := 0;
   begin
      Files.Append ("src/todo_ident.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA007" then
            Ada007_Hits := Ada007_Hits + 1;
         end if;
      end loop;
      Check (Ada007_Hits = 0,
             "ADA007 does not fire on an identifier like ""Todo_List"" that "
             & "merely contains ""TODO"" as a code token, not a comment "
             & "marker");
   end;

   --  Regression: SEC001/SEC002's own Description says "identifier ending
   --  in" the keyword, but a plain substring match also fired on any
   --  identifier merely *containing* it, e.g. "Secretary_Name" (contains
   --  "SECRET") or "Password_Hint" (contains "PASSWORD" but doesn't end
   --  in it).
   Fusa.Files.Write_File
     (Root & "/src/sec_boundary.adb",
      "procedure Sec_Boundary is" & ASCII.LF &
      "   Secretary_Name : constant String := ""Jane Smith"";" & ASCII.LF &
      "   Password_Hint  : constant String := ""your pet's name"";" &
      ASCII.LF &
      "   Db_Password    : constant String := ""hunter2"";" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Sec_Boundary;" &
      ASCII.LF);
   declare
      Files       : String_List;
      Findings    : Finding_List;
      Hits        : Natural := 0;
   begin
      Files.Append ("src/sec_boundary.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "SEC001"
           or else To_String (F.Rule_Id) = "SEC002"
         then
            Hits := Hits + 1;
         end if;
      end loop;
      Check (Hits = 1,
             "SEC001/SEC002 fire exactly once -- on Db_Password (a real "
             & "identifier ending in ""password""), not on Secretary_Name "
             & "(contains ""SECRET"" but doesn't end in it) or "
             & "Password_Hint (contains ""PASSWORD"" but doesn't end in it)");
   end;

   --  Regression: SEC004's "OS_LIB.SPAWN" needle never matched an
   --  unqualified call reachable via "use GNAT.OS_Lib;".
   Fusa.Files.Write_File
     (Root & "/src/spawn_qualified.adb",
      "with GNAT.OS_Lib;" & ASCII.LF &
      "procedure Spawn_Qualified is" & ASCII.LF & "begin" & ASCII.LF &
      "   GNAT.OS_Lib.Spawn (""ls"", (1 .. 0 => <>));" & ASCII.LF &
      "end Spawn_Qualified;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/spawn_unqualified.adb",
      "with GNAT.OS_Lib; use GNAT.OS_Lib;" & ASCII.LF &
      "procedure Spawn_Unqualified is" & ASCII.LF & "begin" & ASCII.LF &
      "   Spawn (""ls"", (1 .. 0 => <>));" & ASCII.LF &
      "end Spawn_Unqualified;" & ASCII.LF);
   Fusa.Files.Write_File
     (Root & "/src/respawn.adb",
      "procedure Respawn is" & ASCII.LF &
      "   Respawn_Count : Natural := 0;" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Respawn;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Hits_Qualified, Hits_Unqualified, Hits_Respawn : Natural := 0;
   begin
      Files.Append ("src/spawn_qualified.adb");
      Files.Append ("src/spawn_unqualified.adb");
      Files.Append ("src/respawn.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "SEC004" then
            if To_String (F.Loc.File) = "src/spawn_qualified.adb" then
               Hits_Qualified := Hits_Qualified + 1;
            elsif To_String (F.Loc.File) = "src/spawn_unqualified.adb" then
               Hits_Unqualified := Hits_Unqualified + 1;
            elsif To_String (F.Loc.File) = "src/respawn.adb" then
               Hits_Respawn := Hits_Respawn + 1;
            end if;
         end if;
      end loop;
      Check (Hits_Qualified = 1, "SEC004 still fires on a fully-qualified GNAT.OS_Lib.Spawn call");
      Check (Hits_Unqualified = 1,
             "SEC004 now also fires on an unqualified Spawn call reachable "
             & "via a preceding ""use GNAT.OS_Lib;""");
      Check (Hits_Respawn = 0,
             "SEC004 does not fire on ""Respawn_Count"", which merely "
             & "contains ""SPAWN"" as a substring, not as a standalone "
             & "identifier (word-boundary check)");
   end;

   --  Regression: ADA008's needle never matched the GNATprove-scoped
   --  three-argument form "pragma Warnings (GNATprove, Off, ...)".
   Fusa.Files.Write_File
     (Root & "/src/warnoff.adb",
      "pragma Warnings (Off, ""x"");" & ASCII.LF &
      "pragma Warnings (GNATprove, Off, ""y"");" & ASCII.LF &
      "procedure Warnoff is" & ASCII.LF & "begin" & ASCII.LF &
      "   null;" & ASCII.LF & "end Warnoff;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Ada008_Hits : Natural := 0;
   begin
      Files.Append ("src/warnoff.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA008" then
            Ada008_Hits := Ada008_Hits + 1;
         end if;
      end loop;
      Check (Ada008_Hits = 2,
             "ADA008 fires on both the plain ""pragma Warnings (Off"" form "
             & "and the GNATprove-scoped ""pragma Warnings (GNATprove, "
             & "Off"" form");
   end;

   --  Regression: ADA002's fixed lookback window missed a real exception
   --  handler once more than a few when-branches preceded "when others =>".
   Fusa.Files.Write_File
     (Root & "/src/many_handlers.adb",
      "procedure Many_Handlers is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "exception" & ASCII.LF &
      "   when Constraint_Error => null;" & ASCII.LF &
      "   when Storage_Error => null;" & ASCII.LF &
      "   when Program_Error => null;" & ASCII.LF &
      "   when Tasking_Error => null;" & ASCII.LF &
      "   when Numeric_Error => null;" & ASCII.LF &
      "   when Data_Error => null;" & ASCII.LF &
      "   when Name_Error => null;" & ASCII.LF &
      "   when Device_Error => null;" & ASCII.LF &
      "   when others => null;" & ASCII.LF &
      "end Many_Handlers;" & ASCII.LF);
   declare
      Files    : String_List;
      Findings : Finding_List;
      Ada002_Hits : Natural := 0;
   begin
      Files.Append ("src/many_handlers.adb");
      Findings := Fusa.Engine.Run_All (Root, Files);
      for F of Findings loop
         if To_String (F.Rule_Id) = "ADA002" then
            Ada002_Hits := Ada002_Hits + 1;
         end if;
      end loop;
      Check (Ada002_Hits = 1,
             "ADA002 still finds a real blanket ""when others"" handler "
             & "even with 8 other when-branches preceding it -- well "
             & "beyond the old fixed 6-line lookback window");
   end;

   --  fusa:test REQ-079
   declare
      Proj_Root : constant String := "tmp_test_engine_project";
      Files     : String_List;
      Fusa_Findings : Finding_List;
      Fusa_Hits : Natural := 0;
   begin
      if Ada.Directories.Exists (Proj_Root) then
         Ada.Directories.Delete_Tree (Proj_Root);
      end if;
      Ada.Directories.Create_Path (Proj_Root);
      Fusa_Findings := Fusa.Engine.Run_All (Proj_Root, Files);
      for F of Fusa_Findings loop
         if To_String (F.Rule_Id) (1 .. 4) = "FUSA" then
            Fusa_Hits := Fusa_Hits + 1;
         end if;
      end loop;
      Check (Fusa_Hits = 4,
             "all four FUSA00x rules fire when a project root has no .gpr, "
             & "LICENSE, README, or .github/workflows");

      Ada.Directories.Create_Path (Proj_Root & "/.github/workflows");
      Fusa.Files.Write_File (Proj_Root & "/LICENSE", "MPL-2.0");
      Fusa.Files.Write_File (Proj_Root & "/README.md", "# T");
      Fusa.Files.Write_File (Proj_Root & "/t.gpr", "project T is end T;");

      Fusa_Findings := Fusa.Engine.Run_All (Proj_Root, Files);
      Fusa_Hits := 0;
      for F of Fusa_Findings loop
         if To_String (F.Rule_Id) (1 .. 4) = "FUSA" then
            Fusa_Hits := Fusa_Hits + 1;
         end if;
      end loop;
      Check (Fusa_Hits = 0,
             "none of the FUSA00x rules fire once all four markers are present");

      Ada.Directories.Delete_Tree (Proj_Root);
   end;

   --  fusa:test REQ-082
   --  Determine_Asil: the published ISO 26262-3:2018 Table 4 lookup.
   --  Not exhaustive over all 36 S/E/C combinations, but covers every
   --  corner of the table (the all-QM low corner, the sole ASIL-D cell,
   --  a representative cell of each other rank) plus invalid-input
   --  fail-safe behaviour, so a transcription error anywhere in the
   --  table is very likely to be caught.
   Check (Fusa.Config.Determine_Asil ("S1", "E1", "C1") = "QM",
          "S1/E1/C1 -> QM (the table's lowest-risk corner)");
   Check (Fusa.Config.Determine_Asil ("S1", "E3", "C3") = "ASIL-A",
          "S1/E3/C3 -> ASIL-A");
   Check (Fusa.Config.Determine_Asil ("S2", "E4", "C2") = "ASIL-B",
          "S2/E4/C2 -> ASIL-B");
   Check (Fusa.Config.Determine_Asil ("S3", "E3", "C3") = "ASIL-C",
          "S3/E3/C3 -> ASIL-C");
   Check (Fusa.Config.Determine_Asil ("S3", "E4", "C3") = "ASIL-D",
          "S3/E4/C3 -> ASIL-D (the table's sole highest-risk cell)");
   Check (Fusa.Config.Determine_Asil ("S0", "E4", "C3") = "",
          "S0 is outside the table's S1-S3 range -- fails safe to blank, "
          & "not a guessed ASIL");
   Check (Fusa.Config.Determine_Asil ("S1", "E0", "C1") = "",
          "E0 is outside the table's E1-E4 range -- fails safe to blank");
   Check (Fusa.Config.Determine_Asil ("bogus", "E1", "C1") = "",
          "an unrecognised severity code fails safe to blank");

   --  fusa:test REQ-083
   --  Determine_Tara_Risk: the section 9.2 (v1.14.1) canonical feasibility
   --  x impact -> risk combination table. impact.* uses the closed enum
   --  critical|major|moderate|negligible -- a DISTINCT scale from
   --  attackFeasibility's high|medium|low|very-low, not the same
   --  high/medium/low vocabulary reused (that was this codebase's own
   --  pre-v1.14.1 bug, since fixed).
   declare
      Critical_Impact : constant Fusa.Config.Sfop_Impact :=
        (Safety => To_Unbounded_String ("critical"),
         Financial => To_Unbounded_String ("negligible"),
         Operational => To_Unbounded_String ("negligible"),
         Privacy => To_Unbounded_String ("negligible"));
      Moderate_Impact : constant Fusa.Config.Sfop_Impact :=
        (Safety => To_Unbounded_String ("moderate"),
         Financial => To_Unbounded_String ("negligible"),
         Operational => To_Unbounded_String ("moderate"),
         Privacy => To_Unbounded_String ("negligible"));
   begin
      Check (Fusa.Config.Determine_Tara_Risk ("very-low", Moderate_Impact) = "low",
             "very-low feasibility + moderate-or-lower impact -> low risk");
      Check (Fusa.Config.Determine_Tara_Risk ("very-low", Critical_Impact) = "medium",
             "even very-low feasibility doesn't fully suppress a critical "
             & "SFOP impact -- risk is still elevated to medium, not low");
      Check (Fusa.Config.Determine_Tara_Risk ("high", Moderate_Impact) = "medium",
             "high feasibility with only moderate-or-lower impact yields "
             & "medium risk, not critical -- risk is a genuine table lookup "
             & "on both inputs, not driven by feasibility alone");
      Check (Fusa.Config.Determine_Tara_Risk ("high", Critical_Impact) = "critical",
             "high feasibility with a critical SFOP impact yields critical risk");
      Check (Fusa.Config.Determine_Tara_Risk ("bogus", Moderate_Impact) = "",
             "an unrecognised attackFeasibility fails safe to blank");
      Check (Fusa.Config.Determine_Tara_Risk ("high", Fusa.Config.Sfop_Impact'
               (Safety => To_Unbounded_String ("bogus"),
                Financial => To_Unbounded_String ("bogus"),
                Operational => To_Unbounded_String ("bogus"),
                Privacy => To_Unbounded_String ("bogus"))) = "",
             "when none of the four impact axes is a recognised value, "
             & "risk fails safe to blank too, even with valid feasibility");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Engine;
