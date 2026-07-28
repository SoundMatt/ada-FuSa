--  Section 1.6.1 detection heuristics for the evidence content-quality
--  baseline (section 1.6): Rule A (placeholder text) and Rule B (blanket
--  qualitative fallback). Runs inside each artifact-producing command
--  (hara/fmea/tara/safety-case) over the content that command itself just
--  built or loaded, gating that command's own exit code via the same
--  section 4 Finding shape every other check uses.

package Fusa.Stub_Detect is

   --  Rule A (MUST): bracket-wrapped instructional text ("[Foo bar]") or
   --  a case-insensitive match against the deny-listed substrings
   --  "replace with" / "example hazard" / "TBD" / "lorem ipsum" /
   --  "fill in".
   --  fusa:req REQ-119
   function Is_Placeholder (Text : String) return Boolean;

   --  Appends a FUSA-STUB001 ERROR finding (category safety) when
   --  Is_Placeholder(Text) -- always-on, never attestation-suppressible
   --  (only a per-finding disposition can waive it).
   --  fusa:req REQ-119
   procedure Check_Placeholder
     (Findings   : in out Fusa.Finding_List;
      File       : String;
      Entry_Id   : String;
      Field_Name : String;
      Text       : String);

   --  Rule B (SHOULD): for an artifact with >= 10 Values, computes the
   --  distinct-value ratio (distinct count / total count) and, when it is
   --  below 0.1, appends a single FUSA-STUB002 WARNING finding (category
   --  safety) -- unless Suppressed (a fresh, independently-reviewed
   --  attestation per section 1.6.2), in which case nothing is appended
   --  at all, per that section's "MUST be suppressed" rule.
   --  fusa:req REQ-119
   procedure Check_Blanket_Fallback
     (Findings   : in out Fusa.Finding_List;
      File       : String;
      Field_Name : String;
      Values     : Fusa.String_List;
      Suppressed : Boolean);

   --  True when Findings contains an open (non-dispositioned) FUSA-STUB002
   --  finding -- used by each artifact command's `--require-attestation`
   --  (and `--strict`, which implies it) to escalate an unsuppressed
   --  Rule B WARNING to exit 1, per section 1.6.2.
   --  fusa:req REQ-120
   function Has_Unsuppressed_Rule_B
     (Findings : Fusa.Finding_List) return Boolean;

end Fusa.Stub_Detect;
