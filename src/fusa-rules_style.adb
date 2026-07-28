with Ada.Strings.Fixed;
with Fusa.Files;
with Fusa.Engine; use Fusa.Engine;

package body Fusa.Rules_Style is

   Max_Line_Length : constant := 79; --  AQSG-recommended line length limit

   --  How many lines before/after the matched one a "-- fusa:unsafe"
   --  justification may appear on and still suppress the finding --
   --  covers both a justification comment placed on the line(s)
   --  immediately above the code it explains (a common Ada convention)
   --  and one placed after a statement that was wrapped (e.g. to satisfy
   --  ADA005's line-length limit).
   Suppress_Lookback  : constant := 5;
   Suppress_Lookahead : constant := 2;

   --  Uppercases and collapses whitespace runs to a single space, so
   --  substring matching against Ada source is both case-insensitive
   --  (Ada keywords/identifiers are case-insensitive by language
   --  definition -- "PRAGMA SUPPRESS" is exactly as legal as
   --  "pragma Suppress") and tolerant of extra alignment whitespace
   --  (e.g. "when   others   =>").
   function Normalize_For_Match (S : String) return String is
      Result   : String (1 .. S'Length);
      Out_Len  : Natural := 0;
      In_Space : Boolean := False;
   begin
      for C of S loop
         declare
            Uc : Character := C;
         begin
            if Uc in 'a' .. 'z' then
               Uc := Character'Val (Character'Pos (Uc) - 32);
            end if;
            if Uc = ' ' or else Uc = ASCII.HT then
               if not In_Space and then Out_Len > 0 then
                  Out_Len := Out_Len + 1;
                  Result (Out_Len) := ' ';
               end if;
               In_Space := True;
            else
               Out_Len := Out_Len + 1;
               Result (Out_Len) := Uc;
               In_Space := False;
            end if;
         end;
      end loop;
      return Result (1 .. Out_Len);
   end Normalize_For_Match;

   --  Approximate "is Pos inside a quoted region" check: counts
   --  double-quote characters before Pos on the (normalized) line. An odd
   --  count means Pos falls inside quotes -- either a real Ada string
   --  literal (e.g. a test fixture, or one of this rule pack's own
   --  known-answer fixtures in Fusa.Cli's Cmd_Qualify, which legitimately
   --  contain text like "pragma Suppress" as fixture *data*, not real
   --  code to flag) or a quoted example in a doc comment (e.g. this
   --  package's own comments quoting "PRAGMA SUPPRESS" as an example of
   --  case-insensitive matching). Same technique as
   --  Fusa.Annotations.In_String_Literal.
   function Is_Quoted (Line : String; Pos : Positive) return Boolean is
      Quote_Count : Natural := 0;
   begin
      for I in Line'First .. Pos - 1 loop
         if Line (I) = '"' then
            Quote_Count := Quote_Count + 1;
         end if;
      end loop;
      return Quote_Count mod 2 = 1;
   end Is_Quoted;

   --  How many lines before a "when others =>" to search for a bare
   --  "exception" keyword when distinguishing a real exception handler
   --  from a "case ... is ... when others =>" default branch -- see
   --  Scan_Exception_Handler.
   Exception_Lookback : constant := 6;

   function Scan_Substring
     (Project_Root      : String;
      Files             : String_List;
      Rule_Id           : String;
      Severity          : Severity_Kind;
      Needle            : String;
      Message           : String;
      Remediation       : String;
      Require_No_Unsafe : Boolean) return Finding_List
   is
      Result      : Finding_List;
      Norm_Needle : constant String := Normalize_For_Match (Needle);
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content : constant String := Fusa.Files.Read_File (Full);
                  Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
               begin
                  for I in 1 .. Natural (Lines.Length) loop
                     declare
                        Line      : constant String := Lines.Element (I);
                        Norm_Line : constant String := Normalize_For_Match (Line);
                        Match_Pos : constant Natural :=
                          Ada.Strings.Fixed.Index (Norm_Line, Norm_Needle);
                     begin
                        if Match_Pos > 0
                          and then not Is_Quoted (Norm_Line, Match_Pos)
                        then
                           declare
                              Suppressed : Boolean := False;
                           begin
                              if Require_No_Unsafe then
                                 for J in Natural'Max (1, I - Suppress_Lookback) ..
                                   Natural'Min (I + Suppress_Lookahead, Natural (Lines.Length))
                                 loop
                                    if Ada.Strings.Fixed.Index
                                         (Lines.Element (J), "fusa:unsafe") > 0
                                    then
                                       Suppressed := True;
                                       exit;
                                    end if;
                                 end loop;
                              end if;

                              if not Suppressed then
                                 Result.Append
                                   (Make_Finding
                                      (Rule_Id     => Rule_Id,
                                       Severity    => Severity,
                                       Message     => Message,
                                       Loc         => Make_Location (Rel, I),
                                       Category    => Derive_Category (Rule_Id),
                                       Remediation => Remediation));
                              end if;
                           end;
                        end if;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return Result;
   end Scan_Substring;

   --  ADA002-specific: the catch-all handler arrow is textually identical
   --  whether it introduces a real exception handler (the safety concern
   --  ADA002 exists to catch) or a `case` statement's default branch (a
   --  completely normal, often-required Ada idiom with no bearing on
   --  exception handling at all). Only flag the former, by requiring a
   --  bare "exception" keyword on one of the nearby preceding
   --  lines.
   function Scan_Exception_Handler
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result      : Finding_List;
      Norm_Needle : constant String := Normalize_For_Match ("when others =>");
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content : constant String := Fusa.Files.Read_File (Full);
                  Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
               begin
                  for I in 1 .. Natural (Lines.Length) loop
                     declare
                        Norm_Line : constant String :=
                          Normalize_For_Match (Lines.Element (I));
                        Match_Pos : constant Natural :=
                          Ada.Strings.Fixed.Index (Norm_Line, Norm_Needle);
                     begin
                        if Match_Pos > 0
                          and then not Is_Quoted (Norm_Line, Match_Pos)
                        then
                           declare
                              Is_Exception_Handler : Boolean := False;
                           begin
                              for J in Natural'Max (1, I - Exception_Lookback) .. I - 1 loop
                                 if Ada.Strings.Fixed.Index
                                      (Normalize_For_Match (Lines.Element (J)),
                                       "EXCEPTION") > 0
                                 then
                                    Is_Exception_Handler := True;
                                    exit;
                                 end if;
                              end loop;

                              if Is_Exception_Handler then
                                 declare
                                    Suppressed : Boolean := False;
                                 begin
                                    for J in Natural'Max (1, I - Suppress_Lookback) ..
                                      Natural'Min (I + Suppress_Lookahead, Natural (Lines.Length))
                                    loop
                                       if Ada.Strings.Fixed.Index
                                            (Lines.Element (J), "fusa:unsafe") > 0
                                       then
                                          Suppressed := True;
                                          exit;
                                       end if;
                                    end loop;

                                    if not Suppressed then
                                       Result.Append
                                         (Make_Finding
                                            (Rule_Id  => "ADA002",
                                             Severity => Warning,
                                             Message  =>
                                               "blanket ""when others"" handler " &
                                               "may hide unanticipated exceptions",
                                             Loc      => Make_Location (Rel, I),
                                             Category => Derive_Category ("ADA002"),
                                             Remediation =>
                                               "handle specific exceptions, or " &
                                               "justify with a trailing " &
                                               """-- fusa:unsafe <reason>"" comment"));
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
      end loop;
      return Result;
   end Scan_Exception_Handler;

   function Scan_Line_Length
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List;
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content : constant String := Fusa.Files.Read_File (Full);
                  Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                  Line_No : Positive := 1;
               begin
                  for Line of Lines loop
                     if Line'Length > Max_Line_Length then
                        Result.Append
                          (Make_Finding
                             (Rule_Id  => "ADA005",
                              Severity => Warning,
                              Message  =>
                                "line exceeds" & Max_Line_Length'Image &
                                " characters (" & Line'Length'Image & ")",
                              Loc         => Make_Location (Rel, Line_No),
                              Category    => Derive_Category ("ADA005"),
                              Remediation => "wrap or split the line to fit within " &
                                Max_Line_Length'Image & " characters"));
                     end if;
                     Line_No := Line_No + 1;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return Result;
   end Scan_Line_Length;

   function Scan_Tabs
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List;
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content : constant String := Fusa.Files.Read_File (Full);
                  Lines   : constant String_List := Fusa.Files.Split_Lines (Content);
                  Line_No : Positive := 1;
               begin
                  for Line of Lines loop
                     if Ada.Strings.Fixed.Index (Line, "" & ASCII.HT) > 0 then
                        Result.Append
                          (Make_Finding
                             (Rule_Id     => "ADA006",
                              Severity    => Warning,
                              Message     => "line contains a tab character",
                              Loc         => Make_Location (Rel, Line_No),
                              Category    => Derive_Category ("ADA006"),
                              Remediation => "use spaces, not tabs, for indentation"));
                     end if;
                     Line_No := Line_No + 1;
                  end loop;
               end;
            end if;
         end;
      end loop;
      return Result;
   end Scan_Tabs;

   ----------------------------------------------------------------------
   --  ADA001 -- unjustified check-disabling Suppress pragma
   ----------------------------------------------------------------------

   type Ada001_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada001_Rule) return String is ("ADA001");
   overriding function Description (R : Ada001_Rule) return String is
     ("pragma Suppress used without a -- fusa:unsafe justification");
   overriding function Run
     (R : Ada001_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "ADA001", Error, "pragma Suppress",
          "pragma Suppress disables a language-defined check",
          "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or remove the suppression",
          Require_No_Unsafe => True));

   ----------------------------------------------------------------------
   --  ADA002 -- blanket "when others =>" exception handler
   ----------------------------------------------------------------------

   type Ada002_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada002_Rule) return String is ("ADA002");
   overriding function Description (R : Ada002_Rule) return String is
     ("blanket ""when others =>"" exception handler without -- fusa:unsafe");
   overriding function Run
     (R : Ada002_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Exception_Handler (Project_Root, Files));

   ----------------------------------------------------------------------
   --  ADA003 -- unjustified strong-typing-bypassing conversion
   ----------------------------------------------------------------------

   type Ada003_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada003_Rule) return String is ("ADA003");
   overriding function Description (R : Ada003_Rule) return String is
     ("Unchecked_Conversion used without a -- fusa:unsafe justification");
   overriding function Run
     (R : Ada003_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "ADA003", Error, "Unchecked_Conversion",
          "Unchecked_Conversion bypasses Ada's strong typing",
          "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or avoid the conversion",
          Require_No_Unsafe => True));

   ----------------------------------------------------------------------
   --  ADA004 -- unjustified manual memory deallocation
   ----------------------------------------------------------------------

   type Ada004_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada004_Rule) return String is ("ADA004");
   overriding function Description (R : Ada004_Rule) return String is
     ("Unchecked_Deallocation used without a -- fusa:unsafe justification");
   overriding function Run
     (R : Ada004_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "ADA004", Warning, "Unchecked_Deallocation",
          "Unchecked_Deallocation risks dangling references",
          "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or use a safer ownership pattern",
          Require_No_Unsafe => True));

   ----------------------------------------------------------------------
   --  ADA005 -- line too long
   ----------------------------------------------------------------------

   type Ada005_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada005_Rule) return String is ("ADA005");
   overriding function Description (R : Ada005_Rule) return String is
     ("line exceeds" & Max_Line_Length'Image & " characters");
   overriding function Run
     (R : Ada005_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Line_Length (Project_Root, Files));

   ----------------------------------------------------------------------
   --  ADA006 -- tab character in source
   ----------------------------------------------------------------------

   type Ada006_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada006_Rule) return String is ("ADA006");
   overriding function Description (R : Ada006_Rule) return String is
     ("line contains a tab character");
   overriding function Run
     (R : Ada006_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Tabs (Project_Root, Files));

   ----------------------------------------------------------------------
   --  ADA007 -- incomplete-work marker comment
   ----------------------------------------------------------------------

   type Ada007_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada007_Rule) return String is ("ADA007");
   overriding function Description (R : Ada007_Rule) return String is
     ("TODO comment marks incomplete work");
   overriding function Run
     (R : Ada007_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "ADA007", Info, "TODO",
          "TODO comment marks incomplete work",
          "resolve the TODO or file a tracked issue before release",
          Require_No_Unsafe => False));

   ----------------------------------------------------------------------
   --  ADA008 -- unjustified compiler-diagnostic suppression
   ----------------------------------------------------------------------

   type Ada008_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada008_Rule) return String is ("ADA008");
   overriding function Description (R : Ada008_Rule) return String is
     ("pragma Warnings (Off, ...) used without a -- fusa:unsafe justification");
   overriding function Run
     (R : Ada008_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "ADA008", Warning, "pragma Warnings (Off",
          "pragma Warnings (Off) silences compiler diagnostics",
          "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or fix the underlying warning",
          Require_No_Unsafe => True));

   ----------------------------------------------------------------------
   --  Registration
   ----------------------------------------------------------------------

   R001 : aliased Ada001_Rule;
   R002 : aliased Ada002_Rule;
   R003 : aliased Ada003_Rule;
   R004 : aliased Ada004_Rule;
   R005 : aliased Ada005_Rule;
   R006 : aliased Ada006_Rule;
   R007 : aliased Ada007_Rule;
   R008 : aliased Ada008_Rule;

begin
   Register (R001'Access);
   Register (R002'Access);
   Register (R003'Access);
   Register (R004'Access);
   Register (R005'Access);
   Register (R006'Access);
   Register (R007'Access);
   Register (R008'Access);
end Fusa.Rules_Style;
