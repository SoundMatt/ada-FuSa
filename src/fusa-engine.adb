with Ada.Containers.Vectors;

package body Fusa.Engine is

   package Rule_Vectors is new Ada.Containers.Vectors (Positive, Rule_Access);

   Rules : Rule_Vectors.Vector;

   procedure Register (R : Rule_Access) is
      Insert_At : Positive := Positive (Natural (Rules.Length) + 1);
   begin
      for I in 1 .. Natural (Rules.Length) loop
         if Rules.Element (I).Id = R.Id then
            raise Duplicate_Rule_Error with "duplicate rule id: " & R.Id;
         end if;
         if R.Id < Rules.Element (I).Id then
            Insert_At := I;
            exit;
         end if;
      end loop;
      Rules.Insert (Before => Insert_At, New_Item => R);
   end Register;

   function Rule_Count return Natural is (Natural (Rules.Length));

   function Get_Rule (Index : Positive) return Rule_Access is
     (Rules.Element (Index));

   function Run_All
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List;
   begin
      for I in 1 .. Rule_Count loop
         declare
            R     : constant Rule_Access := Get_Rule (I);
            Found : constant Finding_List := R.Run (Project_Root, Files);
         begin
            for F of Found loop
               Result.Append (F);
            end loop;
         end;
      end loop;
      return Result;
   end Run_All;

end Fusa.Engine;
