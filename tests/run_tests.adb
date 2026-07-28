with Ada.Command_Line;
with Test_Framework;
with Test_Sha256;
with Test_Json;
with Test_Fusa_Core;
with Test_Report;
with Test_Config;
with Test_Files;
with Test_Glob;
with Test_Engine;
with Test_Annotations;
with Test_Zip;
with Test_Func_Scan;
with Test_Disposition;
with Test_Cli;

procedure Run_Tests is
begin
   Test_Sha256;
   Test_Json;
   Test_Fusa_Core;
   Test_Report;
   Test_Config;
   Test_Files;
   Test_Glob;
   Test_Engine;
   Test_Annotations;
   Test_Zip;
   Test_Func_Scan;
   Test_Disposition;
   Test_Cli;

   if Test_Framework.Report then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Run_Tests;
