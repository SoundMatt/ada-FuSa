with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Fusa.Stub_Detect is

   function Trim_Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   function To_Lower_Str (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         end if;
      end loop;
      return R;
   end To_Lower_Str;

   function Contains_Ci (Haystack, Needle : String) return Boolean is
     (Ada.Strings.Fixed.Index
        (To_Lower_Str (Haystack), To_Lower_Str (Needle)) > 0);

   function Has_Bracket_Placeholder (Text : String) return Boolean is
   begin
      for I in Text'Range loop
         if Text (I) = '[' and then I + 1 <= Text'Last
           and then Text (I + 1) in 'A' .. 'Z' | 'a' .. 'z'
         then
            for J in I + 1 .. Text'Last loop
               if Text (J) = ']' then
                  return True;
               end if;
            end loop;
         end if;
      end loop;
      return False;
   end Has_Bracket_Placeholder;

   function Is_Placeholder (Text : String) return Boolean is
   begin
      if Text'Length = 0 then
         return False;
      end if;
      if Has_Bracket_Placeholder (Text) then
         return True;
      end if;
      return Contains_Ci (Text, "replace with")
        or else Contains_Ci (Text, "example hazard")
        or else Contains_Ci (Text, "tbd")
        or else Contains_Ci (Text, "lorem ipsum")
        or else Contains_Ci (Text, "fill in");
   end Is_Placeholder;

   procedure Check_Placeholder
     (Findings   : in out Fusa.Finding_List;
      File       : String;
      Entry_Id   : String;
      Field_Name : String;
      Text       : String)
   is
   begin
      if Is_Placeholder (Text) then
         Findings.Append
           (Fusa.Make_Finding
              (Rule_Id     => "FUSA-STUB001",
               Severity    => Fusa.Error,
               Message     =>
                 "entry """ & Entry_Id & """'s """ & Field_Name &
                 """ field contains placeholder/instructional text in " & File,
               Loc         => Fusa.Make_Location (File),
               Category    => Fusa.Safety,
               Remediation =>
                 "replace the placeholder with real, entry-specific " &
                 "content, or waive this specific finding via a " &
                 "disposition if it is a genuine false positive"));
      end if;
   end Check_Placeholder;

   procedure Check_Blanket_Fallback
     (Findings   : in out Fusa.Finding_List;
      File       : String;
      Field_Name : String;
      Values     : Fusa.String_List;
      Suppressed : Boolean)
   is
      Total : constant Natural := Natural (Values.Length);
   begin
      if Total < 10 or else Suppressed then
         return;
      end if;
      declare
         Distinct : Fusa.String_List;
      begin
         for V of Values loop
            declare
               Found : Boolean := False;
            begin
               for D of Distinct loop
                  if D = V then
                     Found := True;
                     exit;
                  end if;
               end loop;
               if not Found then
                  Distinct.Append (V);
               end if;
            end;
         end loop;
         declare
            Ratio : constant Float := Float (Distinct.Length) / Float (Total);
         begin
            if Ratio < 0.1 then
               Findings.Append
                 (Fusa.Make_Finding
                    (Rule_Id     => "FUSA-STUB002",
                     Severity    => Fusa.Warning,
                     Message     =>
                       """" & Field_Name & """ has only " &
                       Trim_Img (Natural (Distinct.Length)) &
                       " distinct value(s) across " & Trim_Img (Total) &
                       " entries in " & File &
                       " (below the 0.1 distinct-value-ratio threshold)",
                     Loc         => Fusa.Make_Location (File),
                     Category    => Fusa.Safety,
                     Remediation =>
                       "vary """ & Field_Name & """ with each entry's " &
                       "actual signature/behaviour, or add a reviewed " &
                       "attestation (section 1.6.2) if the similarity is " &
                       "genuine"));
            end if;
         end;
      end;
   end Check_Blanket_Fallback;

   function Has_Unsuppressed_Rule_B
     (Findings : Fusa.Finding_List) return Boolean
   is
   begin
      for F of Findings loop
         if To_String (F.Rule_Id) = "FUSA-STUB002"
           and then (F.Disposition = Fusa.Open
                     or else F.Disposition = Fusa.Rejected)
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Unsuppressed_Rule_B;

end Fusa.Stub_Detect;
