with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Engine;
with Fusa.Files;
with Fusa.Source_Scan;
with Fusa.Config;
with Fusa.Rules_Style;
pragma Unreferenced (Fusa.Rules_Style);
with Test_Engine_Rules;
with Test_Framework; use Test_Framework;

procedure Test_Engine is
   Root : constant String := "tmp_test_engine";
begin
   Check (Fusa.Engine.Rule_Count >= 8, "at least the 8 starter rules are registered");

   declare
      Prev : Unbounded_String := Null_Unbounded_String;
      Ok   : Boolean := True;
   begin
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

   declare
      --  Fusa.Engine's registry is a process-lifetime singleton, so a Rule
      --  handed to Register must outlive this test procedure -- allocate
      --  on the heap (matching how Rule_Access is meant to be populated),
      --  not a stack-local 'Access, which would dangle the moment this
      --  declare block exits and corrupt every later Run_All call.
      D      : constant Fusa.Engine.Rule_Access := new Test_Engine_Rules.Dummy_Rule;
      Raised : Boolean := False;
   begin
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

   Ada.Directories.Delete_Tree (Root);
end Test_Engine;
