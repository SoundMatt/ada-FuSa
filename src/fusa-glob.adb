with Ada.Containers.Vectors;

package body Fusa.Glob is

   --  Regression: the original Match_Rec was a naive recursive
   --  backtracking matcher -- for a pattern with several '*' atoms
   --  against a text with no valid match, it explores exponentially many
   --  split points (e.g. "a*a*a*a*...*b" against a long run of "a"s with
   --  no trailing "b"). Since excludePatterns is untrusted project
   --  config, a crafted pattern hangs any source-scanning command. This
   --  is a textbook wildcard-matching problem with a well-known
   --  polynomial solution: tokenize the pattern into atoms first (so a
   --  "**" run is a single Double_Star atom, matching the original
   --  greedy two-at-a-time '*' consumption exactly), then fill a
   --  dynamic-programming table of size (atom count + 1) x
   --  (text length + 1) -- O(pattern_len * text_len) time and space,
   --  never exponential, regardless of how adversarial the pattern is.

   type Atom_Kind is (Lit, Any_Char, Star, Double_Star);

   type Atom is record
      Kind : Atom_Kind;
      Ch   : Character := ' ';  --  meaningful only when Kind = Lit
   end record;

   package Atom_Vectors is new Ada.Containers.Vectors (Positive, Atom);

   function Tokenize (Pattern : String) return Atom_Vectors.Vector is
      Result : Atom_Vectors.Vector;
      I      : Integer := Pattern'First;
   begin
      while I <= Pattern'Last loop
         if Pattern (I) = '*' then
            if I < Pattern'Last and then Pattern (I + 1) = '*' then
               Result.Append (Atom'(Kind => Double_Star, Ch => ' '));
               I := I + 2;
            else
               Result.Append (Atom'(Kind => Star, Ch => ' '));
               I := I + 1;
            end if;
         elsif Pattern (I) = '?' then
            Result.Append (Atom'(Kind => Any_Char, Ch => ' '));
            I := I + 1;
         else
            Result.Append (Atom'(Kind => Lit, Ch => Pattern (I)));
            I := I + 1;
         end if;
      end loop;
      return Result;
   end Tokenize;

   function Match (Pattern, Text : String) return Boolean is
      Atoms : constant Atom_Vectors.Vector := Tokenize (Pattern);
      An    : constant Natural := Natural (Atoms.Length);
      Tn    : constant Natural := Text'Length;

      --  Dp (I, J) = True iff Atoms (1 .. I) matches Text's first J
      --  characters.
      Dp : array (0 .. An, 0 .. Tn) of Boolean :=
        (others => (others => False));
   begin
      Dp (0, 0) := True;
      for I in 1 .. An loop
         case Atoms (I).Kind is
            when Star | Double_Star => Dp (I, 0) := Dp (I - 1, 0);
            when Lit | Any_Char      => Dp (I, 0) := False;
         end case;
      end loop;

      for I in 1 .. An loop
         declare
            A : constant Atom := Atoms (I);
         begin
            for J in 1 .. Tn loop
               declare
                  Tc : constant Character := Text (Text'First + J - 1);
               begin
                  case A.Kind is
                     when Lit =>
                        Dp (I, J) := Dp (I - 1, J - 1) and then Tc = A.Ch;
                     when Any_Char =>
                        Dp (I, J) := Dp (I - 1, J - 1) and then Tc /= '/';
                     when Star =>
                        --  Zero or more characters, never crossing '/'.
                        Dp (I, J) :=
                          Dp (I - 1, J)
                          or else (Dp (I, J - 1) and then Tc /= '/');
                     when Double_Star =>
                        --  Zero or more characters, '/' included.
                        Dp (I, J) := Dp (I - 1, J) or else Dp (I, J - 1);
                  end case;
               end;
            end loop;
         end;
      end loop;

      return Dp (An, Tn);
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
