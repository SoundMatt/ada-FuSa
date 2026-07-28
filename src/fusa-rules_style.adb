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

   --  Returns the "code portion" of Line: everything before a "--"
   --  comment marker that isn't itself inside a string literal (so
   --  `S : String := "a -- b";` is NOT truncated at the embedded "--").
   --  Used to strip comments before substring-matching, so a rule
   --  doesn't flag prose that merely mentions a dangerous construct by
   --  name (e.g. "-- see ADA001 re: pragma Suppress" should not itself
   --  trigger ADA001). Deliberately NOT applied when scanning for a
   --  "-- fusa:unsafe" suppression comment -- that lookup specifically
   --  searches inside comments.
   function Code_Portion (Line : String) return String is
      In_String : Boolean := False;
   begin
      for I in Line'First .. Line'Last loop
         if Line (I) = '"' then
            In_String := not In_String;
         elsif not In_String and then I < Line'Last
           and then Line (I) = '-' and then Line (I + 1) = '-'
         then
            return Line (Line'First .. I - 1);
         end if;
      end loop;
      return Line;
   end Code_Portion;

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

   --  fusa:req REQ-023
   --  Derive_Category's blanket ADA -> Safety mapping (spec section 1.5.1)
   --  is too coarse for a consumer filtering "show me only safety-relevant
   --  findings": ADA005 (line length), ADA006 (tabs), and ADA008 (compiler
   --  diagnostic suppression) read as style/lint concerns, not safety
   --  concerns, unlike e.g. ADA001/ADA003/ADA004 (unjustified
   --  check-disabling, strong-typing-bypassing, or manual-deallocation
   --  constructs). This overrides the category for just those three rule
   --  ids rather than renumbering them, which would be a breaking change
   --  for anyone already referencing ADA005/ADA006 in a
   --  .fusa-dispositions.json or CI allowlist.
   function Rule_Category (Rule_Id : String) return Category_Kind is
     (if Rule_Id = "ADA005" or else Rule_Id = "ADA006" or else Rule_Id = "ADA008"
      then Style
      else Derive_Category (Rule_Id));

   function Scan_Substring
     (Project_Root      : String;
      Files             : String_List;
      Rule_Id           : String;
      Severity          : Severity_Kind;
      Needle            : String;
      Message           : String;
      Remediation       : String;
      Require_No_Unsafe : Boolean;
      --  False for rules whose needle is itself only ever meaningful
      --  inside a comment (e.g. ADA007's "TODO" marker) -- Code_Portion
      --  would strip exactly the text those rules exist to find.
      Strip_Comments    : Boolean := True) return Finding_List
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
                        Norm_Line : constant String :=
                          Normalize_For_Match
                            (if Strip_Comments then Code_Portion (Line) else Line);
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
                                       Category    => Rule_Category (Rule_Id),
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
                          Normalize_For_Match (Code_Portion (Lines.Element (I)));
                        Match_Pos : constant Natural :=
                          Ada.Strings.Fixed.Index (Norm_Line, Norm_Needle);
                     begin
                        if Match_Pos > 0
                          and then not Is_Quoted (Norm_Line, Match_Pos)
                        then
                           declare
                              Is_Exception_Handler : Boolean := False;
                           begin
                              --  Regression: a fixed lookback window missed a
                              --  real exception handler once more than
                              --  Exception_Lookback when-branches preceded
                              --  the "when others =>" (e.g. one "when" per
                              --  distinct predefined exception). Scanning
                              --  backward with no fixed limit, stopping at
                              --  whichever of a bare "exception" keyword or a
                              --  "case ... is" appears FIRST, correctly
                              --  handles arbitrarily many preceding branches
                              --  and still distinguishes a real handler from
                              --  a case statement's default branch.
                              for J in reverse 1 .. I - 1 loop
                                 declare
                                    Norm_J : constant String :=
                                      Normalize_For_Match (Code_Portion (Lines.Element (J)));
                                 begin
                                    if Ada.Strings.Fixed.Index (Norm_J, "EXCEPTION") > 0 then
                                       Is_Exception_Handler := True;
                                       exit;
                                    elsif Ada.Strings.Fixed.Index (Norm_J, "CASE ") > 0 then
                                       exit;
                                    end if;
                                 end;
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
                                             Category => Rule_Category ("ADA002"),
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
                              Category    => Rule_Category ("ADA005"),
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
                              Category    => Rule_Category ("ADA006"),
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

   --  SEC001/SEC002-specific: a plain needle match on e.g. "PASSWORD :="
   --  almost never fires on real Ada, since a typed declaration reads
   --  "Password : constant String := ..." -- the type name sits between
   --  the identifier and ":=". This instead requires, on the same line:
   --  Keyword, then later ":=", then later a '"' (the assigned value is a
   --  string literal, not e.g. a function call reading a secret at
   --  runtime, which is exactly the safe pattern this rule should not flag).
   function Scan_Credential_Literal
     (Project_Root : String;
      Files        : String_List;
      Rule_Id      : String;
      Keyword      : String;
      Message      : String;
      Remediation  : String) return Finding_List
   is
      Result  : Finding_List;
      Norm_Kw : constant String := Normalize_For_Match (Keyword);
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
                        Line       : constant String := Lines.Element (I);
                        Norm_Line  : constant String :=
                          Normalize_For_Match (Code_Portion (Line));
                        Kw_Pos     : constant Natural :=
                          Ada.Strings.Fixed.Index (Norm_Line, Norm_Kw);
                        Assign_Pos : constant Natural :=
                          (if Kw_Pos = 0 then 0
                           else Ada.Strings.Fixed.Index
                                  (Norm_Line (Kw_Pos .. Norm_Line'Last), ":="));
                     begin
                        if Kw_Pos > 0 and then Assign_Pos > 0
                          and then not Is_Quoted (Norm_Line, Kw_Pos)
                          and then Ada.Strings.Fixed.Index
                                     (Norm_Line (Assign_Pos .. Norm_Line'Last), """") > 0
                        then
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
                                      (Rule_Id     => Rule_Id,
                                       Severity    => Error,
                                       Message     => Message,
                                       Loc         => Make_Location (Rel, I),
                                       Category    => Rule_Category (Rule_Id),
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
   end Scan_Credential_Literal;

   --  Word-boundary check: True if the Length-character substring starting
   --  at Pos in Line is not immediately adjacent to another identifier
   --  character (letter/digit/underscore) on either side -- so matching
   --  "SPAWN" doesn't also fire on "RESPAWN" or "SPAWNER".
   function Is_Word_Boundary_Match
     (Line : String; Pos : Positive; Length : Positive) return Boolean
   is
      function Is_Ident_Char (C : Character) return Boolean is
        (C in 'A' .. 'Z' | '0' .. '9' | '_');
      Before_Ok : constant Boolean :=
        Pos = Line'First or else not Is_Ident_Char (Line (Pos - 1));
      After_Pos : constant Natural := Pos + Length;
   begin
      return Before_Ok
        and then (After_Pos > Line'Last or else not Is_Ident_Char (Line (After_Pos)));
   end Is_Word_Boundary_Match;

   --  SEC004-specific: the plain "OS_LIB.SPAWN" needle never matches an
   --  unqualified call reachable via "use GNAT.OS_Lib;" (e.g. a bare
   --  "Spawn (...)"). If the file has such a use clause, a standalone
   --  "SPAWN" identifier (word-boundary, so "RESPAWN"/"SPAWNER" don't
   --  false-positive) is treated as a match too.
   function Scan_Os_Lib_Spawn
     (Project_Root : String; Files : String_List) return Finding_List
   is
      Result      : Finding_List;
      Message     : constant String :=
        "spawning an external process risks command injection if any " &
        "argument is built from untrusted input (CWE-78)";
      Remediation : constant String :=
        "validate/allowlist all arguments derived from external input, or " &
        "justify with a trailing ""-- fusa:unsafe <reason>"" comment";
   begin
      for Rel of Files loop
         declare
            Full : constant String := Fusa.Files.Join (Project_Root, Rel);
         begin
            if Fusa.Files.Exists (Full) then
               declare
                  Content        : constant String := Fusa.Files.Read_File (Full);
                  Lines          : constant String_List := Fusa.Files.Split_Lines (Content);
                  Has_Use_Clause : Boolean := False;
               begin
                  for Line of Lines loop
                     if Ada.Strings.Fixed.Index
                          (Normalize_For_Match (Code_Portion (Line)), "USE GNAT.OS_LIB") > 0
                     then
                        Has_Use_Clause := True;
                        exit;
                     end if;
                  end loop;

                  for I in 1 .. Natural (Lines.Length) loop
                     declare
                        Norm_Line : constant String :=
                          Normalize_For_Match (Code_Portion (Lines.Element (I)));
                        Qualified_Pos : constant Natural :=
                          Ada.Strings.Fixed.Index (Norm_Line, "OS_LIB.SPAWN");
                        Match_Pos     : Natural := Qualified_Pos;
                     begin
                        if Match_Pos = 0 and then Has_Use_Clause then
                           declare
                              P : Natural := Ada.Strings.Fixed.Index (Norm_Line, "SPAWN");
                           begin
                              while P > 0 loop
                                 if Is_Word_Boundary_Match (Norm_Line, P, 5) then
                                    Match_Pos := P;
                                    exit;
                                 end if;
                                 P := Ada.Strings.Fixed.Index
                                        (Norm_Line (P + 1 .. Norm_Line'Last), "SPAWN");
                              end loop;
                           end;
                        end if;

                        if Match_Pos > 0 and then not Is_Quoted (Norm_Line, Match_Pos) then
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
                                      (Rule_Id     => "SEC004",
                                       Severity    => Warning,
                                       Message     => Message,
                                       Loc         => Make_Location (Rel, I),
                                       Category    => Rule_Category ("SEC004"),
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
   end Scan_Os_Lib_Spawn;

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
          Require_No_Unsafe => False, Strip_Comments => False));

   ----------------------------------------------------------------------
   --  ADA008 -- unjustified compiler-diagnostic suppression
   ----------------------------------------------------------------------

   type Ada008_Rule is new Rule_Interface with null record;

   overriding function Id (R : Ada008_Rule) return String is ("ADA008");
   overriding function Description (R : Ada008_Rule) return String is
     ("pragma Warnings (Off, ...) -- plain or the GNATprove-scoped " &
      """(GNATprove, Off, ...)"" form -- used without a -- fusa:unsafe justification");
   overriding function Run
     (R : Ada008_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      --  The needle "pragma Warnings (Off" never matched the three-argument
      --  tool-scoped form "pragma Warnings (GNATprove, Off, ...)" that
      --  SPARK code commonly uses to silence gnatprove-specific warnings
      --  only -- the token right after "(" is "GNATprove," there, not
      --  "Off". Both forms are scanned for and combined; they are
      --  mutually exclusive substrings, so a line can never match both.
      Result : Finding_List :=
        Scan_Substring
          (Project_Root, Files, "ADA008", Warning, "pragma Warnings (Off",
           "pragma Warnings (Off) silences compiler diagnostics",
           "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or " &
           "fix the underlying warning",
           Require_No_Unsafe => True);
   begin
      for F of Scan_Substring
        (Project_Root, Files, "ADA008", Warning, "pragma Warnings (GNATprove, Off",
         "pragma Warnings (GNATprove, Off) silences gnatprove diagnostics",
         "justify with a trailing ""-- fusa:unsafe <reason>"" comment, or " &
         "fix the underlying warning",
         Require_No_Unsafe => True)
      loop
         Result.Append (F);
      end loop;
      return Result;
   end Run;

   ----------------------------------------------------------------------
   --  SEC001 -- possible hardcoded password
   ----------------------------------------------------------------------

   type Sec001_Rule is new Rule_Interface with null record;

   overriding function Id (R : Sec001_Rule) return String is ("SEC001");
   overriding function Description (R : Sec001_Rule) return String is
     ("identifier ending in ""password"" assigned a literal without -- fusa:unsafe");
   overriding function Run
     (R : Sec001_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Credential_Literal
         (Project_Root, Files, "SEC001", "PASSWORD",
          "possible hardcoded credential (CWE-798)",
          "load the credential from a secret store or environment variable at " &
          "runtime instead, or justify with a trailing " &
          """-- fusa:unsafe <reason>"" comment if this is test/fixture data"));

   ----------------------------------------------------------------------
   --  SEC002 -- possible hardcoded secret/API key
   ----------------------------------------------------------------------

   type Sec002_Rule is new Rule_Interface with null record;

   overriding function Id (R : Sec002_Rule) return String is ("SEC002");
   overriding function Description (R : Sec002_Rule) return String is
     ("identifier ending in ""secret""/""api_key"" assigned a literal without " &
      "-- fusa:unsafe");
   overriding function Run
     (R : Sec002_Rule; Project_Root : String; Files : String_List) return Finding_List
   is
      Result : Finding_List :=
        Scan_Credential_Literal
          (Project_Root, Files, "SEC002", "SECRET",
           "possible hardcoded credential (CWE-798)",
           "load the credential from a secret store or environment variable " &
           "at runtime instead, or justify with a trailing " &
           """-- fusa:unsafe <reason>"" comment if this is test/fixture data");
   begin
      for F of Scan_Credential_Literal
        (Project_Root, Files, "SEC002", "API_KEY",
         "possible hardcoded credential (CWE-798)",
         "load the credential from a secret store or environment variable " &
         "at runtime instead, or justify with a trailing " &
         """-- fusa:unsafe <reason>"" comment if this is test/fixture data")
      loop
         Result.Append (F);
      end loop;
      return Result;
   end Run;

   ----------------------------------------------------------------------
   --  SEC003 -- weak hash algorithm reference (MD5)
   ----------------------------------------------------------------------

   type Sec003_Rule is new Rule_Interface with null record;

   overriding function Id (R : Sec003_Rule) return String is ("SEC003");
   overriding function Description (R : Sec003_Rule) return String is
     ("GNAT.MD5 referenced without -- fusa:unsafe");
   overriding function Run
     (R : Sec003_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Substring
         (Project_Root, Files, "SEC003", Warning, "GNAT.MD5",
          "MD5 is a cryptographically broken hash (CWE-327)",
          "use SHA-256 or stronger for anything security-relevant, or justify " &
          "with a trailing ""-- fusa:unsafe <reason>"" comment if this is " &
          "non-cryptographic use (e.g. a checksum)",
          Require_No_Unsafe => True));

   ----------------------------------------------------------------------
   --  SEC004 -- external process spawn (command injection risk)
   ----------------------------------------------------------------------

   type Sec004_Rule is new Rule_Interface with null record;

   overriding function Id (R : Sec004_Rule) return String is ("SEC004");
   overriding function Description (R : Sec004_Rule) return String is
     ("GNAT.OS_Lib.Spawn (qualified or, after a ""use GNAT.OS_Lib;"", " &
      "unqualified) referenced without -- fusa:unsafe");
   overriding function Run
     (R : Sec004_Rule; Project_Root : String; Files : String_List) return Finding_List
   is (Scan_Os_Lib_Spawn (Project_Root, Files));

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
   S001 : aliased Sec001_Rule;
   S002 : aliased Sec002_Rule;
   S003 : aliased Sec003_Rule;
   S004 : aliased Sec004_Rule;

begin
   Register (R001'Access);
   Register (R002'Access);
   Register (R003'Access);
   Register (R004'Access);
   Register (R005'Access);
   Register (R006'Access);
   Register (R007'Access);
   Register (R008'Access);
   Register (S001'Access);
   Register (S002'Access);
   Register (S003'Access);
   Register (S004'Access);
end Fusa.Rules_Style;
