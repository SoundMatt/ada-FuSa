with Fusa.Files;
with Fusa.Json;
use type Fusa.Json.Value_Access;

package body Fusa.Proof_Analyze is

   function Proof_Pct_Tenths (R : Proof_Report) return Integer is
   begin
      if R.Total_Obligations = 0 then
         return 1000;
      end if;
      declare
         Raw : constant Long_Float :=
           100.0 * Long_Float (R.Proved_Obligations) / Long_Float (R.Total_Obligations);
      begin
         return Integer (Long_Float'Rounding (Raw * 10.0));
      end;
   end Proof_Pct_Tenths;

   function Proof_Pct (R : Proof_Report) return Long_Float is
   begin
      return Long_Float (Proof_Pct_Tenths (R)) / 10.0;
   end Proof_Pct;

   --  True when every check_tree entry under Vc has at least one prover
   --  attempt with "result": "Valid". A VC with no check_tree entries at
   --  all (no proof attempt was ever recorded for it) is conservatively
   --  treated as unproved -- absence of evidence is not evidence of
   --  proof for a safety-relevant coverage metric.
   function Is_Vc_Proved (Vc : Fusa.Json.Value_Access) return Boolean is
      Check_Tree : constant Fusa.Json.Value_Access :=
        Fusa.Json.Get_Array (Vc, "check_tree");
   begin
      if Check_Tree = null or else Fusa.Json.Array_Length (Check_Tree) = 0 then
         return False;
      end if;
      for I in 1 .. Fusa.Json.Array_Length (Check_Tree) loop
         declare
            Item     : constant Fusa.Json.Value_Access :=
              Fusa.Json.Array_Item (Check_Tree, I);
            Attempts : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Member (Item, "proof_attempts");
            Solved   : Boolean := False;
         begin
            if Attempts /= null and then Fusa.Json.Is_Object (Attempts) then
               for M of Attempts.Members loop
                  if Fusa.Json.Get_String (M.Val, "result") = "Valid" then
                     Solved := True;
                     exit;
                  end if;
               end loop;
            end if;
            if not Solved then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Is_Vc_Proved;

   function Parse_Proof_File (Path : String) return Proof_Report is
      Content : constant String := Fusa.Files.Read_File (Path);
      Root    : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Content);
      Result  : Proof_Report;

      function Func_Index (Name, File : String) return Natural is
      begin
         for I in 1 .. Natural (Result.Functions.Length) loop
            if To_String (Result.Functions.Element (I).Name) = Name
              and then To_String (Result.Functions.Element (I).File) = File
            then
               return I;
            end if;
         end loop;
         return 0;
      end Func_Index;

      procedure Process_Unit (Unit : Fusa.Json.Value_Access) is
         Proof_Arr : constant Fusa.Json.Value_Access :=
           Fusa.Json.Get_Array (Unit, "proof");
      begin
         if Proof_Arr = null then
            return;
         end if;
         for I in 1 .. Fusa.Json.Array_Length (Proof_Arr) loop
            declare
               Vc          : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Array_Item (Proof_Arr, I);
               Entity      : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Get_Member (Vc, "entity");
               Name        : constant String := Fusa.Json.Get_String (Entity, "name");
               Sloc_Arr    : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Get_Array (Entity, "sloc");
               File        : constant String :=
                 (if Sloc_Arr /= null and then Fusa.Json.Array_Length (Sloc_Arr) > 0
                  then Fusa.Json.Get_String (Fusa.Json.Array_Item (Sloc_Arr, 1), "file")
                  else "");
               Vc_Proved   : constant Boolean := Is_Vc_Proved (Vc);
               Idx         : Natural := Func_Index (Name, File);
            begin
               Result.Total_Obligations := Result.Total_Obligations + 1;
               if Vc_Proved then
                  Result.Proved_Obligations := Result.Proved_Obligations + 1;
               end if;

               if Idx = 0 then
                  Result.Functions.Append
                    (Func_Proof_Stat'
                       (Name               => To_Unbounded_String (Name),
                        File               => To_Unbounded_String (File),
                        Total_Obligations  => 1,
                        Proved_Obligations => (if Vc_Proved then 1 else 0)));
               else
                  declare
                     F : Func_Proof_Stat := Result.Functions.Element (Idx);
                  begin
                     F.Total_Obligations := F.Total_Obligations + 1;
                     if Vc_Proved then
                        F.Proved_Obligations := F.Proved_Obligations + 1;
                     end if;
                     Result.Functions.Replace_Element (Idx, F);
                  end;
               end if;
            end;
         end loop;
      end Process_Unit;
   begin
      if Root /= null and then Fusa.Json.Is_Array (Root) then
         for I in 1 .. Fusa.Json.Array_Length (Root) loop
            Process_Unit (Fusa.Json.Array_Item (Root, I));
         end loop;
      else
         Process_Unit (Root);
      end if;
      return Result;
   end Parse_Proof_File;

end Fusa.Proof_Analyze;
