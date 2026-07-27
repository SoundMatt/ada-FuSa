package body Fusa.Glob is

   function Match_Rec
     (Pattern : String; Pi : Integer; Text : String; Ti : Integer) return Boolean;

   function Match_Rec
     (Pattern : String; Pi : Integer; Text : String; Ti : Integer) return Boolean
   is
   begin
      if Pi > Pattern'Last then
         return Ti > Text'Last;
      end if;

      declare
         C : constant Character := Pattern (Pi);
      begin
         if C = '*' and then Pi < Pattern'Last and then Pattern (Pi + 1) = '*' then
            for J in Ti .. Text'Last + 1 loop
               if Match_Rec (Pattern, Pi + 2, Text, J) then
                  return True;
               end if;
            end loop;
            return False;

         elsif C = '*' then
            declare
               Limit : Integer := Text'Last + 1;
            begin
               for J in Ti .. Text'Last loop
                  if Text (J) = '/' then
                     Limit := J;
                     exit;
                  end if;
               end loop;
               for J in Ti .. Limit loop
                  if Match_Rec (Pattern, Pi + 1, Text, J) then
                     return True;
                  end if;
               end loop;
               return False;
            end;

         elsif C = '?' then
            if Ti <= Text'Last and then Text (Ti) /= '/' then
               return Match_Rec (Pattern, Pi + 1, Text, Ti + 1);
            end if;
            return False;

         else
            if Ti <= Text'Last and then Text (Ti) = C then
               return Match_Rec (Pattern, Pi + 1, Text, Ti + 1);
            end if;
            return False;
         end if;
      end;
   end Match_Rec;

   function Match (Pattern, Text : String) return Boolean is
   begin
      return Match_Rec (Pattern, Pattern'First, Text, Text'First);
   end Match;

   function Is_Excluded (Patterns : String_List; Rel_Path : String) return Boolean is
   begin
      for P of Patterns loop
         declare
            Has_Slash : Boolean := False;
         begin
            for C of P loop
               if C = '/' then
                  Has_Slash := True;
                  exit;
               end if;
            end loop;

            if Has_Slash then
               if Match (P, Rel_Path) then
                  return True;
               end if;
            else
               --  Match against every path segment.
               declare
                  Seg_Start : Integer := Rel_Path'First;
               begin
                  for I in Rel_Path'First .. Rel_Path'Last + 1 loop
                     if I > Rel_Path'Last or else Rel_Path (I) = '/' then
                        if I > Seg_Start
                          and then Match (P, Rel_Path (Seg_Start .. I - 1))
                        then
                           return True;
                        end if;
                        Seg_Start := I + 1;
                     end if;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return False;
   end Is_Excluded;

end Fusa.Glob;
