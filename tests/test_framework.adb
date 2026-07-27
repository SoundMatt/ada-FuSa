with Ada.Text_IO; use Ada.Text_IO;

package body Test_Framework is

   Total  : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Condition : Boolean; Description : String) is
   begin
      Total := Total + 1;
      if not Condition then
         Failed := Failed + 1;
         Put_Line ("FAIL: " & Description);
      end if;
   end Check;

   function Report return Boolean is
   begin
      Put_Line (Natural'Image (Total) & " checks," & Natural'Image (Failed) & " failed");
      return Failed = 0;
   end Report;

end Test_Framework;
