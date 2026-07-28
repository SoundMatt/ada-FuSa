with Ada.Strings.Fixed;
with Fusa.Files;

package body Fusa.Analyze is

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

   function Strip_Comment (Line : String) return String is
   begin
      for I in Line'First .. Line'Last - 1 loop
         if Line (I) = '-' and then Line (I + 1) = '-' then
            return Line (Line'First .. I - 1);
         end if;
      end loop;
      return Line;
   end Strip_Comment;

   --  Last "."-separated component of a with-clause name, e.g.
   --  "Ada.Text_IO" -> "Text_IO" -- the part that would still appear at
   --  every use site even with a `use` clause bringing the rest into
   --  scope.
   function Last_Component (Name : String) return String is
   begin
      for I in reverse Name'Range loop
         if Name (I) = '.' then
            return Name (I + 1 .. Name'Last);
         end if;
      end loop;
      return Name;
   end Last_Component;

   function Contains_Ci (Haystack, Needle : String) return Boolean is
      Up_H : constant String := To_Upper (Haystack);
      Up_N : constant String := To_Upper (Needle);
   begin
      if Up_N'Length = 0 or else Up_H'Length < Up_N'Length then
         return False;
      end if;
      for I in Up_H'First .. Up_H'Last - Up_N'Length + 1 loop
         if Up_H (I .. I + Up_N'Length - 1) = Up_N then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Ci;

   --  Index (relative to S'First) of the ')' matching the '(' at Open,
   --  or 0 if unmatched before the end of S.
   function Matching_Paren (S : String; Open : Positive) return Natural is
      Depth : Natural := 0;
   begin
      for I in Open .. S'Last loop
         if S (I) = '(' then
            Depth := Depth + 1;
         elsif S (I) = ')' then
            Depth := Depth - 1;
            if Depth = 0 then
               return I;
            end if;
         end if;
      end loop;
      return 0;
   end Matching_Paren;

   --  Replaces every character inside a double-quoted string literal
   --  (the quotes themselves included) with a space, same length and
   --  position as the input. Used before scanning Text for structural
   --  ';'/':' delimiters -- without this, a default-value string literal
   --  containing either character (e.g. `X : String := "a;b:c"`) is
   --  indistinguishable from a real parameter-group separator or
   --  name/type colon, inflating the parameter count with phantom
   --  entries parsed out of the literal's own contents.
   function Mask_String_Literals (S : String) return String is
      Result    : String (S'Range) := S;
      In_String : Boolean := False;
   begin
      for I in S'Range loop
         if S (I) = '"' then
            In_String := not In_String;
            Result (I) := ' ';
         elsif In_String then
            Result (I) := ' ';
         end if;
      end loop;
      return Result;
   end Mask_String_Literals;

   --  Number of individual formal-parameter names in a parenthesised
   --  parameter-profile's interior text, e.g. "A, B : Integer; C : Float"
   --  -> 3. Each ';'-separated group may declare several comma-separated
   --  names sharing one mode/type.
   function Count_Params (Raw_Text : String) return Natural is
      Text        : constant String := Mask_String_Literals (Raw_Text);
      Count       : Natural := 0;
      Group_Start : Positive := Text'First;

      procedure Count_Group (Group : String) is
         Colon : Natural := 0;
      begin
         for I in Group'Range loop
            if Group (I) = ':' then
               Colon := I;
               exit;
            end if;
         end loop;
         if Colon = 0 then
            return;
         end if;
         declare
            Names : constant String := Group (Group'First .. Colon - 1);
            Start : Positive := Names'First;
         begin
            if Names'Length = 0 then
               return;
            end if;
            for I in Names'Range loop
               if Names (I) = ',' then
                  if Ada.Strings.Fixed.Trim (Names (Start .. I - 1), Ada.Strings.Both)'Length > 0
                  then
                     Count := Count + 1;
                  end if;
                  Start := I + 1;
               end if;
            end loop;
            if Ada.Strings.Fixed.Trim (Names (Start .. Names'Last), Ada.Strings.Both)'Length > 0
            then
               Count := Count + 1;
            end if;
         end;
      end Count_Group;
   begin
      if Text'Length = 0 then
         return 0;
      end if;
      for I in Text'Range loop
         if Text (I) = ';' then
            Count_Group (Text (Group_Start .. I - 1));
            Group_Start := I + 1;
         end if;
      end loop;
      Count_Group (Text (Group_Start .. Text'Last));
      return Count;
   end Count_Params;

   Max_Params : constant := 6;

   function Analyze
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List;
   begin
      for Rel of Files loop
         if Has_Suffix (Rel, ".ads") or else Has_Suffix (Rel, ".adb") then
            declare
               Full : constant String := Fusa.Files.Join (Project_Root, Rel);
            begin
               if Fusa.Files.Exists (Full) then
                  declare
                     Content : constant String := Fusa.Files.Read_File (Full);
                     Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                     In_Context : Boolean := True;
                     Body_Start : Positive := 1; --  1-indexed line where the
                                                  --  context clause ended
                  begin
                     --  ANAL001: a with-clause whose last dotted component
                     --  never appears again after the context clause.
                     --  DOCUMENTED LIMITATION: a package used only via a
                     --  `use` clause with no qualification anywhere (e.g.
                     --  `use Ada.Text_IO; ... Put_Line (...)`, never
                     --  writing `Text_IO` again) is a false positive --
                     --  hence Info severity, which never gates even under
                     --  --strict. Only single-line with-clauses are
                     --  recognised (same limitation as Fusa.Deps).
                     for I in 1 .. Natural (Lines.Length) loop
                        declare
                           Trimmed : constant String :=
                             Ada.Strings.Fixed.Trim
                               (Strip_Comment (Lines.Element (I)), Ada.Strings.Both);
                           Upper   : constant String := To_Upper (Trimmed);
                        begin
                           if not In_Context then
                              null;
                           elsif Starts_With (Upper, "WITH ")
                             or else Starts_With (Upper, "PRIVATE WITH ")
                           then
                              declare
                                 Kw_Len : constant Positive :=
                                   (if Starts_With (Upper, "PRIVATE WITH ") then 13 else 5);
                                 Semi   : Natural := 0;
                              begin
                                 for J in Trimmed'First + Kw_Len .. Trimmed'Last loop
                                    if Trimmed (J) = ';' then
                                       Semi := J;
                                       exit;
                                    end if;
                                 end loop;
                                 if Semi > 0 then
                                    declare
                                       With_Name : constant String :=
                                         Ada.Strings.Fixed.Trim
                                           (Trimmed (Trimmed'First + Kw_Len .. Semi - 1),
                                            Ada.Strings.Both);
                                       Rest_Text : Unbounded_String := Null_Unbounded_String;
                                    begin
                                       for K in I + 1 .. Natural (Lines.Length) loop
                                          Append (Rest_Text, Lines.Element (K) & " ");
                                       end loop;
                                       if With_Name'Length > 0
                                         and then not Contains_Ci
                                           (To_String (Rest_Text), Last_Component (With_Name))
                                       then
                                          Result.Append
                                            (Make_Finding
                                               (Rule_Id     => "ANAL001",
                                                Severity    => Info,
                                                Message     =>
                                                  "possibly unused with-clause """ & With_Name &
                                                  """ (its last component never appears again " &
                                                  "in this file -- a false positive if it's " &
                                                  "only used via a bare name brought into " &
                                                  "scope by ""use"")",
                                                Loc         => Make_Location (Rel, I),
                                                Category    => Fusa.Lint,
                                                Remediation =>
                                                  "remove the with-clause if truly unused, or " &
                                                  "ignore if used only via a ""use"" clause"));
                                       end if;
                                    end;
                                 end if;
                              end;
                           elsif Starts_With (Upper, "PACKAGE ")
                             or else Starts_With (Upper, "PROCEDURE ")
                             or else Starts_With (Upper, "FUNCTION ")
                           then
                              In_Context := False;
                              Body_Start := I;
                           end if;
                        end;
                     end loop;

                     --  ANAL002: a subprogram spec/body header with more
                     --  than Max_Params formal parameter names.
                     for I in Body_Start .. Natural (Lines.Length) loop
                        declare
                           Trimmed : constant String :=
                             Ada.Strings.Fixed.Trim
                               (Strip_Comment (Lines.Element (I)), Ada.Strings.Both);
                           Upper   : constant String := To_Upper (Trimmed);
                        begin
                           if Starts_With (Upper, "PROCEDURE ")
                             or else Starts_With (Upper, "FUNCTION ")
                           then
                              declare
                                 --  The parameter list's opening '(' isn't
                                 --  always on the same line as the
                                 --  keyword -- a common Ada style puts it
                                 --  on the next line. Pull in further
                                 --  lines (bounded, to avoid scanning deep
                                 --  into an unrelated body when a
                                 --  parameterless subprogram's header
                                 --  never has a '(' at all) until either a
                                 --  '(' or a ';'/bare-"is" line-ending
                                 --  (meaning no parameter list) is seen.
                                 Joined       : Unbounded_String := To_Unbounded_String (Trimmed);
                                 Open         : Natural := Index (Joined, "(");
                                 No_Params    : Boolean :=
                                   Open = 0
                                   and then (Ada.Strings.Fixed.Index (Trimmed, ";") > 0
                                             or else Has_Suffix (Upper, " IS")
                                             or else Upper = "IS");
                                 Extra_Lines  : Natural := 0;
                              begin
                                 while Open = 0 and then not No_Params
                                   and then I + Extra_Lines < Natural (Lines.Length)
                                   and then Extra_Lines < 10
                                 loop
                                    Extra_Lines := Extra_Lines + 1;
                                    declare
                                       Next : constant String :=
                                         Ada.Strings.Fixed.Trim
                                           (Strip_Comment (Lines.Element (I + Extra_Lines)),
                                            Ada.Strings.Both);
                                       Next_Upper : constant String := To_Upper (Next);
                                    begin
                                       Append (Joined, " " & Next);
                                       Open := Index (Joined, "(");
                                       No_Params :=
                                         Open = 0
                                         and then (Ada.Strings.Fixed.Index (Next, ";") > 0
                                                   or else Has_Suffix (Next_Upper, " IS")
                                                   or else Next_Upper = "IS");
                                    end;
                                 end loop;

                                 if Open > 0 then
                                    while Matching_Paren (To_String (Joined), Open) = 0
                                      and then I + Extra_Lines < Natural (Lines.Length)
                                      and then Extra_Lines < 20
                                    loop
                                       Extra_Lines := Extra_Lines + 1;
                                       Append (Joined, " " & Lines.Element (I + Extra_Lines));
                                    end loop;
                                    declare
                                       Full_Text : constant String := To_String (Joined);
                                       Close     : constant Natural :=
                                         Matching_Paren (Full_Text, Open);
                                    begin
                                       if Close > Open + 1 then
                                             declare
                                                N : constant Natural :=
                                                  Count_Params
                                                    (Full_Text (Open + 1 .. Close - 1));
                                             begin
                                                if N > Max_Params then
                                                   Result.Append
                                                     (Make_Finding
                                                        (Rule_Id     => "ANAL002",
                                                         Severity    => Warning,
                                                         Message     =>
                                                           "subprogram has" & Natural'Image (N) &
                                                           " parameters, exceeding" &
                                                           Natural'Image (Max_Params) &
                                                           " -- consider grouping related " &
                                                           "parameters into a record",
                                                         Loc         => Make_Location (Rel, I),
                                                         Category    => Fusa.Lint,
                                                         Remediation =>
                                                           "group related parameters into a " &
                                                           "record type, or split the " &
                                                           "subprogram's responsibilities"));
                                                end if;
                                             end;
                                          end if;
                                       end;
                                    end if;
                                 end;
                              end if;
                        end;
                     end loop;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Result;
   end Analyze;

end Fusa.Analyze;
