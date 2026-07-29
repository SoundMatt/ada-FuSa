with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Fusa.Fmea_Analyze is

   function To_Lower (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         end if;
      end loop;
      return R;
   end To_Lower;

   --  Strips the directory and ".ads"/".adb" extension from a
   --  project-relative file path, giving the GNAT-convention file stem
   --  that (modulo the dash-for-dot substitution GNAT's own default
   --  naming scheme uses) names the package the function was found in --
   --  e.g. "src/fusa-sha256.ads" -> "fusa-sha256". Kept as the file stem
   --  verbatim (not reconstructed into "Fusa.Sha256") since that
   --  reconstruction cannot always recover the real declared casing --
   --  see Item_Of's own doc comment.
   function File_Stem (Rel : String) return String is
      Slash    : Natural := 0;
      Dot      : Natural := 0;
   begin
      for I in reverse Rel'Range loop
         if Rel (I) = '/' then
            Slash := I;
            exit;
         end if;
      end loop;
      for I in reverse Rel'Range loop
         if Rel (I) = '.' then
            Dot := I;
            exit;
         end if;
      end loop;
      declare
         First : constant Positive := (if Slash > 0 then Slash + 1 else Rel'First);
         Last  : constant Natural := (if Dot > Slash then Dot - 1 else Rel'Last);
      begin
         return Rel (First .. Last);
      end;
   end File_Stem;

   --  Builds the section 9.2 "item" (component/function identifier). Uses
   --  the raw GNAT file stem rather than attempting to reconstruct the
   --  package's declared-case dotted name (e.g. "Fusa.Sha256") -- GNAT's
   --  own default file-naming convention (all-lowercase, "." -> "-")
   --  loses the original casing entirely, so any reconstruction would be
   --  a guess, not a fact this tool has actually verified against the
   --  source; "file" (a separate, exact field) already gives the precise
   --  location.
   function Item_Of (Component, Function_Name : String) return String is
     (Component & "." & Function_Name);

   type Bucket is
     (Write_Like, Crypto_Like, Run_Like, Parse_Like, Default_Like);

   function Classify (Name_Lower : String) return Bucket is
      function Has (Needle : String) return Boolean is
        (Ada.Strings.Fixed.Index (Name_Lower, Needle) > 0);
   begin
      --  Ordered most-specific-risk-signal first, mirroring go-FuSa's own
      --  fmea.deriveAnalysis bucket ordering.
      if Has ("write") or else Has ("save") or else Has ("store")
        or else Has ("delete") or else Has ("remove")
      then
         return Write_Like;
      elsif Has ("sign") or else Has ("verify") or else Has ("hash")
        or else Has ("encrypt") or else Has ("decrypt") or else Has ("hmac")
      then
         return Crypto_Like;
      elsif Has ("run") or else Has ("execute") or else Has ("start")
        or else Has ("scan") or else Has ("analyze") or else Has ("process")
      then
         return Run_Like;
      elsif Has ("parse") or else Has ("load") or else Has ("read")
        or else Has ("decode")
      then
         return Parse_Like;
      else
         return Default_Like;
      end if;
   end Classify;

   procedure Fill_By_Bucket
     (B : Bucket; Item : String; E : in out Fusa.Config.Fmea_Entry)
   is
   begin
      case B is
         when Write_Like =>
            E.Severity := 7;
            E.Failure_Mode :=
              To_Unbounded_String ("partial write / data corruption in " & Item);
            E.Effect :=
              To_Unbounded_String ("incorrect persisted state after " & Item & " runs");
            E.Cause :=
              To_Unbounded_String
                ("an interrupted write in " & Item &
                 " (crash, disk full, concurrent access) leaving a partial artifact");
            E.Mitigations.Append
              ("write via a temp file and atomic rename, or validate the write's result");
         when Crypto_Like =>
            E.Severity := 8;
            E.Failure_Mode :=
              To_Unbounded_String (Item & " produces an incorrect cryptographic result");
            E.Effect :=
              To_Unbounded_String
                ("an integrity/authenticity check downstream of " & Item &
                 " silently passes when it should fail, or vice versa");
            E.Cause :=
              To_Unbounded_String
                ("a logic error in " & Item & "'s algorithm implementation, not caught " &
                 "by a known-answer test");
            E.Mitigations.Append
              ("verify against published known-answer test vectors for this algorithm");
         when Run_Like =>
            E.Severity := 6;
            E.Failure_Mode :=
              To_Unbounded_String ("uncontrolled execution in " & Item);
            E.Effect :=
              To_Unbounded_String ("resource exhaustion triggered from " & Item);
            E.Cause :=
              To_Unbounded_String
                ("no bound on iteration count, input size, or execution time in " & Item);
            E.Mitigations.Append ("add an explicit resource/iteration bound");
         when Parse_Like =>
            E.Severity := 5;
            E.Failure_Mode :=
              To_Unbounded_String (Item & " mishandles malformed/unexpected input");
            E.Effect :=
              To_Unbounded_String
                ("incorrect or partially-populated data accepted downstream of " & Item);
            E.Cause :=
              To_Unbounded_String
                (Item & " does not fully validate its input before using it");
            E.Mitigations.Append
              ("add requirement-traced unit tests covering malformed/boundary input");
         when Default_Like =>
            E.Severity := 4;
            E.Failure_Mode :=
              To_Unbounded_String (Item & " produces incorrect output for a given input");
            E.Effect := To_Unbounded_String ("incorrect system behavior from " & Item);
            E.Cause :=
              To_Unbounded_String
                ("a logic error in " & Item & " not surfaced as an exception");
            E.Mitigations.Append
              ("add requirement-traced unit tests covering this function's documented behaviour");
      end case;
   end Fill_By_Bucket;

   function Derive_Entries
     (Funcs : Fusa.Func_Scan.Func_List) return Fusa.Config.Fmea_Entry_List
   is
      Result : Fusa.Config.Fmea_Entry_List;
   begin
      for F of Funcs loop
         declare
            Component : constant String := File_Stem (To_String (F.File));
            Fn_Name   : constant String := To_String (F.Name);
            Item      : constant String := Item_Of (Component, Fn_Name);
            Entry_Rec : Fusa.Config.Fmea_Entry;
         begin
            Entry_Rec.Id   := To_Unbounded_String ("AUTO-" & Component & "-" & Fn_Name);
            Entry_Rec.Item := To_Unbounded_String (Item);
            Entry_Rec.File := F.File;
            Fill_By_Bucket (Classify (To_Lower (Fn_Name)), Item, Entry_Rec);
            Result.Append (Entry_Rec);
         end;
      end loop;
      return Result;
   end Derive_Entries;

end Fusa.Fmea_Analyze;
