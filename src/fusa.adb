with Fusa.Sha256;

package body Fusa is

   ----------------------------------------------------------------------
   --  Image
   ----------------------------------------------------------------------

   function Image (S : Severity_Kind) return String is
   begin
      case S is
         when Info    => return "INFO";
         when Warning => return "WARNING";
         when Error   => return "ERROR";
      end case;
   end Image;

   function Image (C : Category_Kind) return String is
   begin
      case C is
         when Lint            => return "lint";
         when Style           => return "style";
         when Safety          => return "safety";
         when Security        => return "security";
         when Coverage        => return "coverage";
         when Requirement     => return "requirement";
         when Concurrency     => return "concurrency";
         when Supply_Chain    => return "supply-chain";
         when Config_Category => return "config";
         when Other           => return "other";
      end case;
   end Image;

   function Image (D : Disposition_Kind) return String is
   begin
      case D is
         when Open     => return "open";
         when Accepted => return "accepted";
         when Deferred => return "deferred";
         when Rejected => return "rejected";
      end case;
   end Image;

   ----------------------------------------------------------------------
   --  Make_Location / Make_Finding
   ----------------------------------------------------------------------

   function Make_Location
     (File       : String;
      Line       : Natural := 0;
      Column     : Natural := 0;
      End_Line   : Natural := 0;
      End_Column : Natural := 0) return Location
   is
   begin
      return (File       => To_Unbounded_String (File),
              Line       => Line,
              Column     => Column,
              End_Line   => End_Line,
              End_Column => End_Column);
   end Make_Location;

   function Make_Finding
     (Rule_Id     : String;
      Severity    : Severity_Kind;
      Message     : String;
      Loc         : Location;
      Category    : Category_Kind := Other;
      Standard    : String := "";
      Clause      : String := "";
      Remediation : String := "";
      Disposition : Disposition_Kind := Open) return Finding
   is
      F : Finding :=
        (Rule_Id     => To_Unbounded_String (Rule_Id),
         Severity    => Severity,
         Message     => To_Unbounded_String (Message),
         Loc         => Loc,
         Category    => Category,
         Standard    => To_Unbounded_String (Standard),
         Clause      => To_Unbounded_String (Clause),
         Remediation => To_Unbounded_String (Remediation),
         Disposition => Disposition,
         Fingerprint => Null_Unbounded_String);
   begin
      F.Fingerprint := To_Unbounded_String (Compute_Fingerprint (F));
      return F;
   end Make_Finding;

   ----------------------------------------------------------------------
   --  Derive_Category (§1.5.1 prefix registry)
   ----------------------------------------------------------------------

   function Derive_Category (Rule_Id : String) return Category_Kind is
      Upper : String := Rule_Id;
      Cut   : Natural := 0;
   begin
      for I in Upper'Range loop
         declare
            C : constant Character := Upper (I);
         begin
            if C in 'a' .. 'z' then
               Upper (I) := Character'Val (Character'Pos (C) - 32);
            end if;
         end;
      end loop;

      for I in Upper'Range loop
         if Upper (I) in '0' .. '9' or else Upper (I) = '-' then
            Cut := I;
            exit;
         end if;
      end loop;

      declare
         Prefix : constant String :=
           (if Cut > Upper'First then Upper (Upper'First .. Cut - 1) else Upper);
      begin
         if Prefix = "LINT" then
            return Lint;
         elsif Prefix = "STYLE" then
            return Style;
         elsif Prefix = "FUSA" or else Prefix = "ADA" then
            return Safety;
         elsif Prefix = "SEC" or else Prefix = "CWE" then
            return Security;
         elsif Prefix = "COV" then
            return Coverage;
         elsif Prefix = "REQ" then
            return Requirement;
         elsif Prefix = "CONC" or else Prefix = "RACE" then
            return Concurrency;
         elsif Prefix = "SBOM" or else Prefix = "SLSA" or else Prefix = "VULN" then
            return Supply_Chain;
         elsif Prefix = "CFG" then
            return Config_Category;
         else
            return Other;
         end if;
      end;
   end Derive_Category;

   ----------------------------------------------------------------------
   --  Normalize_Message (§4.2)
   ----------------------------------------------------------------------

   function Normalize_Message (Msg : String) return String is
      Result    : String (1 .. Msg'Length * 1);
      Out_Len   : Natural := 0;
      In_Digits : Boolean := False;
      In_Space  : Boolean := False;

      procedure Append (C : Character) is
      begin
         Out_Len := Out_Len + 1;
         Result (Out_Len) := C;
      end Append;
   begin
      for I in Msg'Range loop
         declare
            C : constant Character := Msg (I);
         begin
            if C in '0' .. '9' then
               if not In_Digits then
                  if In_Space and Out_Len > 0 then
                     Append (' ');
                  end if;
                  Append ('#');
                  In_Digits := True;
               end if;
               In_Space := False;
            elsif C = ' ' or else C = ASCII.HT
              or else C = ASCII.LF or else C = ASCII.CR
            then
               In_Digits := False;
               In_Space  := True;
            else
               if In_Space and Out_Len > 0 then
                  Append (' ');
               end if;
               Append (C);
               In_Digits := False;
               In_Space  := False;
            end if;
         end;
      end loop;
      return Result (1 .. Out_Len);
   end Normalize_Message;

   ----------------------------------------------------------------------
   --  Compute_Fingerprint (§4.2)
   ----------------------------------------------------------------------

   Unit_Separator : constant Character := Character'Val (16#1F#);

   function Compute_Fingerprint (F : Finding) return String is
      Canonical : constant String :=
        To_String (F.Rule_Id) & Unit_Separator &
        To_String (F.Loc.File) & Unit_Separator &
        Normalize_Message (To_String (F.Message));
   begin
      return "sha256:" & Fusa.Sha256.Hex_Digest (Canonical);
   end Compute_Fingerprint;

end Fusa;
