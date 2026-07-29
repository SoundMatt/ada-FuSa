with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Stub_Detect;
with Fusa.Attestation;
with Fusa.Json;
use type Fusa.Json.Value_Access;
with Fusa.Json.Writer;
with Test_Framework; use Test_Framework;

procedure Test_Stub_Detect is
begin
   --  fusa:test REQ-119
   Check (Fusa.Stub_Detect.Is_Placeholder ("[describe hazard]"),
          "bracket-wrapped instructional text is a placeholder");
   Check (Fusa.Stub_Detect.Is_Placeholder
            ("Example hazard -- replace with project-specific hazard"),
          "case-insensitive ""replace with"" is a placeholder");
   Check (Fusa.Stub_Detect.Is_Placeholder ("tbd"),
          "case-insensitive ""TBD"" is a placeholder");
   Check (Fusa.Stub_Detect.Is_Placeholder ("Lorem Ipsum dolor sit amet"),
          "case-insensitive ""lorem ipsum"" is a placeholder");
   Check (Fusa.Stub_Detect.Is_Placeholder ("please fill in the details"),
          "case-insensitive ""fill in"" is a placeholder");
   Check (not Fusa.Stub_Detect.Is_Placeholder
            ("brake actuator loses hydraulic pressure under load"),
          "genuine entry-specific text is not a placeholder");
   Check (not Fusa.Stub_Detect.Is_Placeholder (""),
          "an empty string is not a placeholder");
   Check (not Fusa.Stub_Detect.Is_Placeholder ("array index [3] out of range"),
          "a bracketed non-letter-led token (an index, not instructional "
          & "text) is not a placeholder");
   --  Regression: the canonical regex is \[[A-Za-z ][^\]]*\] -- the
   --  character right after '[' is a letter *or a space*, not letters
   --  only.
   Check (Fusa.Stub_Detect.Is_Placeholder ("[ describe hazard]"),
          "bracket-wrapped instructional text starting with a space "
          & "after '[' is still a placeholder, per the exact canonical "
          & "regex");
   --  Regression: buffer[i]-style single-token bracket usage IS flagged
   --  by the letter-led branch of the same canonical regex -- this is
   --  spec-intended (the spec explicitly accepts this class of false
   --  positive, to be resolved via disposition, not a narrower
   --  detector), not a bug to fix here.
   Check (Fusa.Stub_Detect.Is_Placeholder
            ("buffer[i] causes memory corruption"),
          "a letter-led bracketed token still matches the canonical "
          & "regex exactly as specified");

   --  fusa:test REQ-119
   declare
      Findings : Finding_List;
   begin
      Fusa.Stub_Detect.Check_Placeholder
        (Findings, "f.json", "E1", "description", "[describe hazard]");
      Check (Natural (Findings.Length) = 1
             and then To_String (Findings.First_Element.Rule_Id) = "FUSA-STUB001"
             and then Findings.First_Element.Severity = Error,
             "Check_Placeholder appends exactly one FUSA-STUB001 ERROR "
             & "finding for a placeholder value");
   end;
   declare
      Findings : Finding_List;
   begin
      Fusa.Stub_Detect.Check_Placeholder
        (Findings, "f.json", "E1", "description", "real content");
      Check (Natural (Findings.Length) = 0,
             "Check_Placeholder appends nothing for real content");
   end;

   --  fusa:test REQ-119
   declare
      Findings : Finding_List;
      Values   : String_List;
   begin
      for I in 1 .. 9 loop
         Values.Append ("same value");
      end loop;
      Fusa.Stub_Detect.Check_Blanket_Fallback
        (Findings, "f.json", "field", Values, False);
      Check (Natural (Findings.Length) = 0,
             "Check_Blanket_Fallback never fires below the 10-entry minimum, "
             & "even with zero variation");
   end;
   declare
      Findings : Finding_List;
      Values   : String_List;
   begin
      for I in 1 .. 10 loop
         Values.Append ("same value");
      end loop;
      Fusa.Stub_Detect.Check_Blanket_Fallback
        (Findings, "f.json", "field", Values, False);
      Check (Natural (Findings.Length) = 0,
             "Check_Blanket_Fallback does not fire exactly at a 0.1 ratio "
             & "(1/10) -- the threshold is strictly below 0.1");
   end;
   declare
      Findings : Finding_List;
      Values   : String_List;
   begin
      for I in 1 .. 11 loop
         Values.Append ("same value");
      end loop;
      Fusa.Stub_Detect.Check_Blanket_Fallback
        (Findings, "f.json", "field", Values, False);
      Check (Natural (Findings.Length) = 1
             and then To_String (Findings.First_Element.Rule_Id) = "FUSA-STUB002"
             and then Findings.First_Element.Severity = Warning,
             "Check_Blanket_Fallback fires a WARNING once the ratio drops "
             & "below 0.1 (1/11)");
   end;
   declare
      Findings : Finding_List;
      Values   : String_List;
   begin
      for I in 1 .. 11 loop
         Values.Append ("same value");
      end loop;
      Fusa.Stub_Detect.Check_Blanket_Fallback
        (Findings, "f.json", "field", Values, True);
      Check (Natural (Findings.Length) = 0,
             "Check_Blanket_Fallback is fully suppressed (not merely "
             & "dispositioned) when Suppressed is True");
   end;

   --  fusa:test REQ-120
   declare
      Findings : Finding_List;
   begin
      Check (not Fusa.Stub_Detect.Has_Unsuppressed_Rule_B (Findings),
             "Has_Unsuppressed_Rule_B is False for an empty finding list");
      Findings.Append
        (Make_Finding ("FUSA-STUB002", Warning, "w", Make_Location ("f.json")));
      Check (Fusa.Stub_Detect.Has_Unsuppressed_Rule_B (Findings),
             "Has_Unsuppressed_Rule_B is True once an open FUSA-STUB002 is present");
   end;
   declare
      Findings : Finding_List;
      F        : Finding :=
        Make_Finding ("FUSA-STUB002", Warning, "w", Make_Location ("f.json"));
   begin
      F.Disposition := Accepted;
      Findings.Append (F);
      Check (not Fusa.Stub_Detect.Has_Unsuppressed_Rule_B (Findings),
             "Has_Unsuppressed_Rule_B is False once the FUSA-STUB002 is "
             & "dispositioned Accepted");
   end;

   --  fusa:test REQ-120
   declare
      Absent : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Fusa.Json.Parse ("{}"));
   begin
      Check (not Absent.Present, "Parse: no attestation member -> Present = False");
   end;
   declare
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse
          (Fusa.Json.Parse ("{""attestation"":{""implementationAuthor"":""auto""}}"));
   begin
      Check (Att.Present and then To_String (Att.Status) = "heuristic",
             "Parse: a present attestation with no ""status"" fails safe to "
             & """heuristic""");
   end;
   declare
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse
          (Fusa.Json.Parse
             ("{""attestation"":{""status"":""reviewed""," &
              """implementationAuthor"":""auto""," &
              """independentReviewer"":""Jane"",""reviewedAt"":""t""," &
              """contentHash"":""sha256:abc""}}"));
   begin
      Check (Att.Present and then To_String (Att.Status) = "reviewed"
             and then To_String (Att.Independent_Reviewer) = "Jane"
             and then To_String (Att.Content_Hash) = "sha256:abc",
             "Parse: a fully-populated attestation round-trips every field");
   end;

   --  fusa:test REQ-120
   declare
      Root_A : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""b"":1,""a"":""x"",""generatedAt"":""T1""}");
      Root_B : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":""x"",""generatedAt"":""T2"",""b"":1}");
   begin
      Check (Fusa.Attestation.Canonical_Content_Hash (Root_A) =
               Fusa.Attestation.Canonical_Content_Hash (Root_B),
             "Canonical_Content_Hash is stable under member reordering and "
             & "ignores generatedAt (RFC 8785 JCS key sort, excluded key)");
   end;
   declare
      Root_A : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1}");
      Root_B : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":2}");
   begin
      Check (Fusa.Attestation.Canonical_Content_Hash (Root_A) /=
               Fusa.Attestation.Canonical_Content_Hash (Root_B),
             "Canonical_Content_Hash differs when substantive content differs");
   end;
   --  Regression: a number too large for Long_Long_Integer anywhere in the
   --  document (a stray extra digit, a fat-fingered value) used to raise
   --  an uncaught Constraint_Error, crashing the whole hash computation
   --  instead of degrading gracefully.
   declare
      Huge : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1e300}");
      Hash : constant String := Fusa.Attestation.Canonical_Content_Hash (Huge);
   begin
      Check (Hash'Length > 0,
             "Canonical_Content_Hash does not crash on a number too large "
             & "for Long_Long_Integer -- it degrades to a still-deterministic "
             & "fallback rather than raising Constraint_Error");
      Check (Fusa.Attestation.Canonical_Content_Hash (Huge) = Hash,
             "the fallback formatting is deterministic (same input -> "
             & "same hash)");
   end;
   declare
      With_Att : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1,""attestation"":{""status"":""reviewed""}}");
      Without_Att : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1}");
   begin
      Check (Fusa.Attestation.Canonical_Content_Hash (With_Att) =
               Fusa.Attestation.Canonical_Content_Hash (Without_Att),
             "Canonical_Content_Hash excludes the attestation object itself "
             & "from its own input (no self-reference)");
   end;

   --  fusa:test REQ-120
   declare
      Root : constant Fusa.Json.Value_Access := Fusa.Json.Parse ("{""a"":1}");
      Hash : constant String := Fusa.Attestation.Canonical_Content_Hash (Root);
      Fresh : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""attestation"":{""status"":""reviewed""," &
           """implementationAuthor"":""auto"",""independentReviewer"":""Jane""," &
           """contentHash"":""" & Hash & """}}");
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Fresh);
   begin
      Check (Fusa.Attestation.Is_Fresh_Reviewed (Att, Fresh),
             "Is_Fresh_Reviewed is True for a reviewed, independent, "
             & "hash-matching attestation");
   end;
   declare
      Root : constant Fusa.Json.Value_Access := Fusa.Json.Parse ("{""a"":1}");
      Hash : constant String := Fusa.Attestation.Canonical_Content_Hash (Root);
      Self_Attested : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""attestation"":{""status"":""reviewed""," &
           """implementationAuthor"":""auto"",""independentReviewer"":""auto""," &
           """contentHash"":""" & Hash & """}}");
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Self_Attested);
   begin
      Check (not Fusa.Attestation.Is_Fresh_Reviewed (Att, Self_Attested),
             "Is_Fresh_Reviewed downgrades a same-identity "
             & "(self-attested) ""reviewed"" claim to False");
   end;
   --  Regression: a naive string-equality self-attestation check is
   --  trivially bypassed by a trailing space or different casing on the
   --  same real identity.
   declare
      Root : constant Fusa.Json.Value_Access := Fusa.Json.Parse ("{""a"":1}");
      Hash : constant String := Fusa.Attestation.Canonical_Content_Hash (Root);
      Whitespace_Bypass : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""attestation"":{""status"":""reviewed""," &
           """implementationAuthor"":""Jane Doe""," &
           """independentReviewer"":""  JANE DOE  ""," &
           """contentHash"":""" & Hash & """}}");
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Whitespace_Bypass);
   begin
      Check (not Fusa.Attestation.Is_Fresh_Reviewed (Att, Whitespace_Bypass),
             "Is_Fresh_Reviewed treats a trailing-whitespace, "
             & "different-case independentReviewer as the same "
             & "self-attesting identity, not a genuine independent one");
   end;
   declare
      Stale : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse
          ("{""a"":1,""attestation"":{""status"":""reviewed""," &
           """implementationAuthor"":""auto"",""independentReviewer"":""Jane""," &
           """contentHash"":""sha256:not-the-real-hash""}}");
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Stale);
   begin
      Check (not Fusa.Attestation.Is_Fresh_Reviewed (Att, Stale),
             "Is_Fresh_Reviewed is False when contentHash does not match "
             & "the artifact's current content (stale)");
   end;
   declare
      Heuristic : constant Fusa.Json.Value_Access :=
        Fusa.Json.Parse ("{""a"":1}");
      Att : constant Fusa.Attestation.Info :=
        Fusa.Attestation.Parse (Heuristic);
   begin
      Check (not Fusa.Attestation.Is_Fresh_Reviewed (Att, Heuristic),
             "Is_Fresh_Reviewed is False when there is no attestation at all");
   end;

   --  fusa:test REQ-120
   declare
      W   : Fusa.Json.Writer.Instance;
      Att : Fusa.Attestation.Info;
   begin
      Att.Present := True;
      Att.Status := To_Unbounded_String ("reviewed");
      Att.Independent_Reviewer := To_Unbounded_String ("Jane");
      W.Object_Start;
      Fusa.Attestation.Write (W, Att);
      W.Object_End;
      declare
         Out_Text : constant String := Fusa.Json.Writer.To_String (W);
      begin
         Check (Ada.Strings.Unbounded.Index
                  (To_Unbounded_String (Out_Text), """attestation"":") > 0
                and then Ada.Strings.Unbounded.Index
                           (To_Unbounded_String (Out_Text),
                            """status"": ""reviewed""") > 0,
                "Write emits the attestation object when Present");
      end;
   end;
   declare
      W   : Fusa.Json.Writer.Instance;
      Att : Fusa.Attestation.Info;
   begin
      W.Object_Start;
      Fusa.Attestation.Write (W, Att);
      W.Object_End;
      Check (Ada.Strings.Unbounded.Index
               (To_Unbounded_String (Fusa.Json.Writer.To_String (W)),
                """attestation"":") = 0,
             "Write is a no-op when Att.Present is False");
   end;

end Test_Stub_Detect;
