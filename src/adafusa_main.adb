with Ada.Command_Line;
with Fusa; use Fusa;
with Fusa.Cli;

--  Forces elaboration of the starter rule packs so their rules register
--  themselves with Fusa.Engine before any command runs.
with Fusa.Rules_Style;
pragma Unreferenced (Fusa.Rules_Style);
with Fusa.Rules_Project;
pragma Unreferenced (Fusa.Rules_Project);

procedure Adafusa_Main is
   Args : String_List;
begin
   for I in 1 .. Ada.Command_Line.Argument_Count loop
      Args.Append (Ada.Command_Line.Argument (I));
   end loop;
   Ada.Command_Line.Set_Exit_Status
     (Ada.Command_Line.Exit_Status (Fusa.Cli.Run (Args)));
end Adafusa_Main;
