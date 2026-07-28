with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Comp is

   function Has_Suffix (S, Suffix : String) return Boolean is
     (S'Length >= Suffix'Length
      and then S (S'Last - Suffix'Length + 1 .. S'Last) = Suffix);

   function Starts_With (S, Prefix : String) return Boolean is
     (S'Length >= Prefix'Length
      and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);

   function To_Upper (S : String) return String is
      Result : String (S'Range);
   begin
      for I in S'Range loop
         if S (I) in 'a' .. 'z' then
            Result (I) := Character'Val (Character'Pos (S (I)) - 32);
         else
            Result (I) := S (I);
         end if;
      end loop;
      return Result;
   end To_Upper;

   --  Collapses whitespace runs to a single space and trims, so keyword
   --  matching below is tolerant of alignment spacing (mirrors
   --  Fusa.Rules_Style.Normalize_For_Match).
   function Normalize (S : String) return String is
      Result   : String (1 .. S'Length);
      Out_Len  : Natural := 0;
      In_Space : Boolean := False;
   begin
      for C of S loop
         if C = ' ' or else C = ASCII.HT then
            if not In_Space and then Out_Len > 0 then
               Out_Len := Out_Len + 1;
               Result (Out_Len) := ' ';
            end if;
            In_Space := True;
         else
            Out_Len := Out_Len + 1;
            Result (Out_Len) := C;
            In_Space := False;
         end if;
      end loop;
      while Out_Len > 0 and then Result (Out_Len) = ' ' loop
         Out_Len := Out_Len - 1;
      end loop;
      return Result (1 .. Out_Len);
   end Normalize;

   --  True if Norm_Line (already uppercased+normalized) ends in the bare
   --  word "IS" -- i.e. a subprogram body header's terminating "is", not a
   --  word merely ending in the letters I-S (e.g. "THIS").
   function Ends_With_Bare_Is (Norm_Line : String) return Boolean is
   begin
      if not Has_Suffix (Norm_Line, "IS") then
         return False;
      end if;
      if Norm_Line'Length = 2 then
         return True; --  the whole (trimmed) line is just "IS"
      end if;
      declare
         Before : constant Character := Norm_Line (Norm_Line'Last - 2);
      begin
         return not (Before in 'A' .. 'Z' or else Before in '0' .. '9'
                     or else Before = '_');
      end;
   end Ends_With_Bare_Is;

   function Extract_Name (Decl_After_Keyword : String) return String is
      Trimmed : constant String :=
        Ada.Strings.Fixed.Trim (Decl_After_Keyword, Ada.Strings.Left);
   begin
      for I in Trimmed'Range loop
         if Trimmed (I) = ' ' or else Trimmed (I) = '(' or else Trimmed (I) = ';' then
            return Trimmed (Trimmed'First .. I - 1);
         end if;
      end loop;
      return Trimmed;
   end Extract_Name;

   --  Counts occurrences of Needle (already normalized) in Norm_Line,
   --  non-overlapping, left to right.
   function Count_Occurrences (Norm_Line, Needle : String) return Natural is
      Count : Natural := 0;
      Pos   : Natural := Norm_Line'First;
   begin
      loop
         declare
            Idx : constant Natural :=
              Ada.Strings.Fixed.Index (Norm_Line (Pos .. Norm_Line'Last), Needle);
         begin
            exit when Idx = 0;
            Count := Count + 1;
            Pos := Idx + Needle'Length;
            exit when Pos > Norm_Line'Last;
         end;
      end loop;
      return Count;
   end Count_Occurrences;

   --  §6.3.4 McCabe V(G), approximated by text search rather than a real
   --  control-flow graph: 1 (baseline path) plus one per decision point:
   --  "IF " (catches both "if" and "elsif", since "ELSIF " ends in "IF ";
   --  "END IF;" is naturally excluded since "IF" there is followed by ";"
   --  not a space), "WHEN " (case alternatives and exception-handler
   --  alternatives alike -- both are textually "when ... =>"), "FOR "/
   --  "WHILE " (loop headers), "EXIT WHEN " (conditional exit from an
   --  unconditional loop -- a bare "loop ... end loop;" contributes no
   --  decision on its own), and "AND THEN "/"OR ELSE " (short-circuit
   --  operators, each introducing an additional branch).
   function Count_Decision_Points (Norm_Line : String) return Natural is
   begin
      return Count_Occurrences (Norm_Line, "IF ")
        + Count_Occurrences (Norm_Line, "WHEN ")
        + Count_Occurrences (Norm_Line, "FOR ")
        + Count_Occurrences (Norm_Line, "WHILE ")
        + Count_Occurrences (Norm_Line, "AND THEN ")
        + Count_Occurrences (Norm_Line, "OR ELSE ");
      --  Note: "EXIT WHEN " is already counted once by "WHEN " above, so
      --  it is not double-counted here.
   end Count_Decision_Points;

   function Analyze
     (Project_Root : String;
      Files        : String_List;
      Threshold    : Positive) return Comp_Result_List
   is
      Result : Comp_Result_List;
   begin
      for Rel of Files loop
         if Has_Suffix (Rel, ".adb") then
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, Rel);
            begin
               if Fusa.Files.Exists (Full) then
                  declare
                     Content : constant String := Fusa.Files.Read_File (Full);
                     Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                     N       : constant Natural := Natural (Lines.Length);
                     --  0 = not currently inside a tracked subprogram body;
                     --  otherwise the line number of that body's "end
                     --  NAME;" -- lines up to and including it are skipped
                     --  for *starting* a new detection, so a nested
                     --  subprogram's header is not itself reported as a
                     --  separate result (its decision points are still
                     --  counted, as part of the enclosing range below).
                     Current_End : Natural := 0;
                  begin
                     for I in 1 .. N loop
                        if I > Current_End then
                           declare
                              Trimmed : constant String :=
                                Ada.Strings.Fixed.Trim (Lines.Element (I), Ada.Strings.Both);
                              Upper   : constant String := To_Upper (Trimmed);
                           begin
                              if Starts_With (Upper, "PROCEDURE ")
                                or else Starts_With (Upper, "FUNCTION ")
                              then
                                 declare
                                    Kw_Len : constant Positive :=
                                      (if Starts_With (Upper, "FUNCTION ") then 9 else 10);
                                    Name   : constant String :=
                                      Extract_Name (Trimmed (Trimmed'First + Kw_Len .. Trimmed'Last));
                                    Header_End : Natural := 0;
                                 begin
                                    --  Search forward (bounded window) for
                                    --  the header's terminating "is". Bail
                                    --  out early (treat as not a body) on
                                    --  hitting "begin" or another
                                    --  subprogram header first -- a bare
                                    --  declaration/rename ending in ";"
                                    --  with no "is" at all is exactly the
                                    --  case this must not misdetect.
                                    for J in I .. Natural'Min (I + 19, N) loop
                                       declare
                                          U : constant String :=
                                            To_Upper
                                              (Normalize
                                                 (Ada.Strings.Fixed.Trim
                                                    (Lines.Element (J), Ada.Strings.Both)));
                                       begin
                                          if J > I
                                            and then (Starts_With (U, "BEGIN")
                                                      or else Starts_With (U, "PROCEDURE ")
                                                      or else Starts_With (U, "FUNCTION "))
                                          then
                                             exit;
                                          end if;
                                          if Ends_With_Bare_Is (U) then
                                             Header_End := J;
                                             exit;
                                          end if;
                                       end;
                                    end loop;

                                    if Header_End > 0 then
                                       declare
                                          Upper_Name : constant String := To_Upper (Name);
                                          End_Line   : Natural := 0;
                                       begin
                                          for J in Header_End + 1 .. N loop
                                             declare
                                                U : constant String :=
                                                  To_Upper
                                                    (Normalize
                                                       (Ada.Strings.Fixed.Trim
                                                          (Lines.Element (J), Ada.Strings.Both)));
                                             begin
                                                if U = "END " & Upper_Name & ";" then
                                                   End_Line := J;
                                                   exit;
                                                end if;
                                             end;
                                          end loop;

                                          if End_Line > 0 then
                                             declare
                                                Decisions : Natural := 0;
                                             begin
                                                for J in Header_End + 1 .. End_Line - 1 loop
                                                   Decisions := Decisions +
                                                     Count_Decision_Points
                                                       (To_Upper (Normalize (Lines.Element (J))));
                                                end loop;
                                                declare
                                                   Complexity : constant Positive := 1 + Decisions;
                                                begin
                                                   Result.Append
                                                     (Comp_Result'
                                                        (File              => To_Unbounded_String (Rel),
                                                         Line              => I,
                                                         Name              => To_Unbounded_String (Name),
                                                         Complexity        => Complexity,
                                                         Exceeds_Threshold =>
                                                           Complexity > Threshold));
                                                end;
                                                Current_End := End_Line;
                                             end;
                                          end if;
                                       end;
                                    end if;
                                 end;
                              end if;
                           end;
                        end if;
                     end loop;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Result;
   end Analyze;

end Fusa.Comp;
