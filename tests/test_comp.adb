with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Files;
with Fusa.Comp;
with Test_Framework; use Test_Framework;

procedure Test_Comp is
   Root : constant String := "tmp_test_comp";

   function Find (Results : Fusa.Comp.Comp_Result_List; Name : String)
     return Fusa.Comp.Comp_Result
   is
   begin
      for R of Results loop
         if To_String (R.Name) = Name then
            return R;
         end if;
      end loop;
      return (File => Null_Unbounded_String, Line => 1,
              Name => Null_Unbounded_String, Complexity => 1,
              Exceeds_Threshold => False);
   end Find;
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/src");

   --  fusa:test REQ-080
   --  Hand-computed V(G): if(1) + elsif(1) + when x3(3) + for(1) + while(1)
   --  + and-then(1) + if(1) + or-else(1) = 10 decisions -> V(G) = 11.
   Fusa.Files.Write_File
     (Root & "/src/example.adb",
      "procedure Example (X : Integer; Y : Integer) is" & ASCII.LF &
      "begin" & ASCII.LF &
      "   if X > 0 then" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   elsif X < 0 then" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end if;" & ASCII.LF &
      ASCII.LF &
      "   case Y is" & ASCII.LF &
      "      when 1 =>" & ASCII.LF &
      "         null;" & ASCII.LF &
      "      when 2 =>" & ASCII.LF &
      "         null;" & ASCII.LF &
      "      when others =>" & ASCII.LF &
      "         null;" & ASCII.LF &
      "   end case;" & ASCII.LF &
      ASCII.LF &
      "   for I in 1 .. 10 loop" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end loop;" & ASCII.LF &
      ASCII.LF &
      "   while X > 0 loop" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end loop;" & ASCII.LF &
      ASCII.LF &
      "   declare" & ASCII.LF &
      "      B : Boolean := X > 0 and then Y > 0;" & ASCII.LF &
      "   begin" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end;" & ASCII.LF &
      ASCII.LF &
      "   if X > 0 or else Y > 0 then" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end if;" & ASCII.LF &
      "end Example;" & ASCII.LF);

   --  A nested subprogram's decision points are attributed to its
   --  innermost enclosing subprogram (documented limitation, not a
   --  separate result): if(1, Inner) + if(1, Outer) = 2 decisions on
   --  Outer -> V(G) = 3. Inner is not reported separately.
   Fusa.Files.Write_File
     (Root & "/src/nested.adb",
      "procedure Outer (X : Integer) is" & ASCII.LF &
      "   function Inner (Y : Integer) return Integer is" & ASCII.LF &
      "   begin" & ASCII.LF &
      "      if Y > 0 then" & ASCII.LF &
      "         return Y;" & ASCII.LF &
      "      end if;" & ASCII.LF &
      "      return 0;" & ASCII.LF &
      "   end Inner;" & ASCII.LF &
      "begin" & ASCII.LF &
      "   if X > 0 then" & ASCII.LF &
      "      null;" & ASCII.LF &
      "   end if;" & ASCII.LF &
      "end Outer;" & ASCII.LF);

   Fusa.Files.Write_File
     (Root & "/src/trivial.adb",
      "procedure Trivial is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF & "end Trivial;" & ASCII.LF);

   declare
      Files   : String_List;
      Results : Fusa.Comp.Comp_Result_List;
   begin
      Files.Append ("src/example.adb");
      Files.Append ("src/nested.adb");
      Files.Append ("src/trivial.adb");
      Results := Fusa.Comp.Analyze (Root, Files, 10);

      Check (Natural (Results.Length) = 3,
             "Outer and Trivial are reported, but Inner (nested) is not "
             & "reported separately -- three results, not four");

      declare
         R : constant Fusa.Comp.Comp_Result := Find (Results, "Example");
      begin
         Check (R.Complexity = 11,
                "Example's complexity matches the hand-computed V(G) = 11 "
                & "(if + elsif + 3 whens + for + while + and-then + if + "
                & "or-else = 10 decisions, plus the baseline path)");
         Check (R.Exceeds_Threshold, "complexity 11 exceeds the threshold of 10");
      end;

      declare
         R : constant Fusa.Comp.Comp_Result := Find (Results, "Outer");
      begin
         Check (R.Complexity = 3,
                "Outer's complexity (3) includes Inner's nested decision "
                & "point (1) plus Outer's own (1) plus the baseline (1)");
         Check (not R.Exceeds_Threshold, "complexity 3 does not exceed the threshold of 10");
      end;

      declare
         R : constant Fusa.Comp.Comp_Result := Find (Results, "Trivial");
      begin
         Check (R.Complexity = 1, "a function with no decision points has V(G) = 1");
      end;
   end;

   --  Regression: "end if;"/"end loop;" must not themselves be counted as
   --  decision points (the trailing ";" excludes them from the "IF "/
   --  "LOOP "-style matching, but this is worth a dedicated check since
   --  it's the exact false-positive this heuristic must avoid).
   Fusa.Files.Write_File
     (Root & "/src/exitwhen.adb",
      "procedure Exitwhen is" & ASCII.LF &
      "   I : Integer := 0;" & ASCII.LF &
      "begin" & ASCII.LF &
      "   loop" & ASCII.LF &
      "      exit when I > 10;" & ASCII.LF &
      "      I := I + 1;" & ASCII.LF &
      "   end loop;" & ASCII.LF &
      "end Exitwhen;" & ASCII.LF);
   declare
      Files   : String_List;
      Results : Fusa.Comp.Comp_Result_List;
      R       : Fusa.Comp.Comp_Result;
   begin
      Files.Append ("src/exitwhen.adb");
      Results := Fusa.Comp.Analyze (Root, Files, 10);
      R := Find (Results, "Exitwhen");
      Check (R.Complexity = 2,
             "an unconditional loop with 'exit when' has V(G) = 2 (the "
             & "'exit when' condition is the only decision point -- the "
             & "bare 'loop'/'end loop;' keywords are not decisions "
             & "themselves)");
   end;

   Ada.Directories.Delete_Tree (Root);
end Test_Comp;
