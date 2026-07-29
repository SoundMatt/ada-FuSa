with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

package body Fusa.Tara_Analyze is

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

   --  Same file-stem extraction as Fusa.Fmea_Analyze.File_Stem (kept as
   --  an independent copy rather than a shared dependency, matching this
   --  codebase's existing convention of self-contained analysis units --
   --  see e.g. Fusa.Comp/Fusa.Deps).
   function File_Stem (Rel : String) return String is
      Slash : Natural := 0;
      Dot   : Natural := 0;
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

   type Bucket is (Crypto_Like, Write_Like, Run_Like, Default_Like);

   --  A component's bucket is the single worst (most specific-risk)
   --  signal found across ANY of its functions' names -- ordered the
   --  same way Fusa.Fmea_Analyze.Classify orders its own buckets.
   function Classify_One (Name_Lower : String) return Bucket is
      function Has (Needle : String) return Boolean is
        (Ada.Strings.Fixed.Index (Name_Lower, Needle) > 0);
   begin
      if Has ("sign") or else Has ("verify") or else Has ("hash")
        or else Has ("encrypt") or else Has ("decrypt") or else Has ("hmac")
      then
         return Crypto_Like;
      elsif Has ("write") or else Has ("save") or else Has ("store")
        or else Has ("delete") or else Has ("remove")
      then
         return Write_Like;
      elsif Has ("run") or else Has ("execute") or else Has ("start")
        or else Has ("scan") or else Has ("analyze") or else Has ("process")
      then
         return Run_Like;
      else
         return Default_Like;
      end if;
   end Classify_One;

   function Worse (A, B : Bucket) return Bucket is
     (if Bucket'Pos (A) < Bucket'Pos (B) then A else B);

   procedure Fill_By_Bucket
     (B : Bucket; Asset : String; T : in out Fusa.Config.Threat)
   is
      Impact : Fusa.Config.Sfop_Impact;
   begin
      case B is
         when Crypto_Like =>
            T.Description := To_Unbounded_String
              ("a cryptographic/integrity weakness in " & Asset &
               " lets an attacker forge or tamper with data it signs, " &
               "hashes, or verifies without detection");
            T.Attack_Vector := To_Unbounded_String ("local");
            Impact.Safety := To_Unbounded_String ("moderate");
            Impact.Financial := To_Unbounded_String ("moderate");
            Impact.Operational := To_Unbounded_String ("major");
            Impact.Privacy := To_Unbounded_String ("major");
            T.Mitigations.Append
              ("verify the cryptographic implementation against published "
               & "known-answer test vectors and review for timing/side-channel issues");
         when Write_Like =>
            T.Description := To_Unbounded_String
              ("an attacker with local access tampers with or corrupts "
               & Asset & "'s persisted output");
            T.Attack_Vector := To_Unbounded_String ("local");
            Impact.Safety := To_Unbounded_String ("moderate");
            Impact.Financial := To_Unbounded_String ("moderate");
            Impact.Operational := To_Unbounded_String ("major");
            Impact.Privacy := To_Unbounded_String ("negligible");
            T.Mitigations.Append
              ("validate/authenticate persisted artifacts before they are trusted "
               & "again, and write via a temp file + atomic rename");
         when Run_Like =>
            T.Description := To_Unbounded_String
              ("an attacker triggers unbounded execution in " & Asset &
               " to exhaust CPU/memory (denial of service)");
            T.Attack_Vector := To_Unbounded_String ("local");
            Impact.Safety := To_Unbounded_String ("negligible");
            Impact.Financial := To_Unbounded_String ("moderate");
            Impact.Operational := To_Unbounded_String ("major");
            Impact.Privacy := To_Unbounded_String ("negligible");
            T.Mitigations.Append
              ("add an explicit resource/iteration/time bound on this component's "
               & "entry points");
         when Default_Like =>
            T.Description := To_Unbounded_String
              ("an attacker supplies unexpected input to " & Asset &
               " to cause unauthorized modification of program state");
            T.Attack_Vector := To_Unbounded_String ("local");
            Impact.Safety := To_Unbounded_String ("moderate");
            Impact.Financial := To_Unbounded_String ("negligible");
            Impact.Operational := To_Unbounded_String ("moderate");
            Impact.Privacy := To_Unbounded_String ("negligible");
            T.Mitigations.Append
              ("add requirement-traced unit tests covering this component's "
               & "input validation");
      end case;
      T.Attack_Feasibility := To_Unbounded_String ("medium");
      T.Impact := Impact;
      T.Risk := To_Unbounded_String
        (Fusa.Config.Determine_Tara_Risk (To_String (T.Attack_Feasibility), Impact));
      T.Treatment := To_Unbounded_String ("mitigate");
   end Fill_By_Bucket;

   type Component_Info is record
      Name   : Unbounded_String;
      Bucket_Val : Bucket;
      File   : Unbounded_String;
   end record;

   package Component_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Component_Info);

   function Derive_Threats
     (Funcs : Fusa.Func_Scan.Func_List) return Fusa.Config.Threat_List
   is
      Components : Component_Vectors.Vector;

      function Index_Of (Component : String) return Natural is
      begin
         for I in 1 .. Natural (Components.Length) loop
            if To_String (Components.Element (I).Name) = Component then
               return I;
            end if;
         end loop;
         return 0;
      end Index_Of;

      Result : Fusa.Config.Threat_List;
   begin
      for F of Funcs loop
         declare
            Component : constant String := File_Stem (To_String (F.File));
            Idx       : constant Natural := Index_Of (Component);
            B         : constant Bucket := Classify_One (To_Lower (To_String (F.Name)));
         begin
            if Idx = 0 then
               Components.Append
                 (Component_Info'
                    (Name       => To_Unbounded_String (Component),
                     Bucket_Val => B,
                     File       => F.File));
            else
               declare
                  Info : Component_Info := Components.Element (Idx);
               begin
                  Info.Bucket_Val := Worse (Info.Bucket_Val, B);
                  Components.Replace_Element (Idx, Info);
               end;
            end if;
         end;
      end loop;

      for Info of Components loop
         declare
            Asset : constant String := To_String (Info.Name);
            T     : Fusa.Config.Threat;
         begin
            T.Id    := To_Unbounded_String ("AUTO-TARA-" & Asset);
            T.Asset := To_Unbounded_String (Asset);
            T.Location.Present := True;
            T.Location.File := Info.File;
            Fill_By_Bucket (Info.Bucket_Val, Asset, T);
            Result.Append (T);
         end;
      end loop;
      return Result;
   end Derive_Threats;

end Fusa.Tara_Analyze;
