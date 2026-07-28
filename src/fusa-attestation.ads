--  Section 1.6.2 attestation: an artifact-level assertion that a named,
--  independent human reviewed an evidence artifact's qualitative content,
--  used to suppress Rule B (FUSA-STUB002) without a tool ever having to
--  judge whether the content itself is "good" -- it only checks that the
--  assertion is well-formed, independent, and still matches the content
--  it was made against.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa.Json;
with Fusa.Json.Writer;

package Fusa.Attestation is

   type Info is record
      Present                : Boolean := False;
      Status                 : Unbounded_String;  --  "heuristic" | "reviewed"
      Implementation_Author  : Unbounded_String;
      Independent_Reviewer   : Unbounded_String;
      Reviewed_At            : Unbounded_String;
      Content_Hash           : Unbounded_String;   --  as read, "sha256:..."
   end record;

   --  Parses Root's "attestation" member, if any. An absent/malformed
   --  "status" reads as "heuristic" (fail-safe per section 1.6.2).
   --  fusa:req REQ-120
   function Parse (Root : Fusa.Json.Value_Access) return Info;

   --  RFC 8785 JCS canonical serialisation of Root's substantive content
   --  (every top-level member except "attestation" and "generatedAt"),
   --  hashed as "sha256:" & hex(SHA-256(canonical)). Object members are
   --  emitted in lexicographic key order with no insignificant
   --  whitespace, matching qualify's own section 6 hash convention.
   --  Assumes every JSON number in Root is integral (true of every
   --  artifact this applies to -- severities, counts, ratios are never
   --  emitted as fractional in this tool's own writers).
   --  fusa:req REQ-120
   function Canonical_Content_Hash
     (Root : Fusa.Json.Value_Access) return String;

   --  True only when Att is present, status = "reviewed",
   --  independentReviewer is non-blank and differs from
   --  implementationAuthor, and contentHash matches Root's current
   --  Canonical_Content_Hash. Any other case (missing, self-attested,
   --  stale) fails safe to False -- section 1.6.2's "downgrade to
   --  heuristic" rule.
   --  fusa:req REQ-120
   function Is_Fresh_Reviewed
     (Att : Info; Root : Fusa.Json.Value_Access) return Boolean;

   --  Writes the "attestation" key/object if Att.Present; a no-op
   --  otherwise. Used both to pass an input file's attestation through to
   --  its own JSON rendering, and (for sas, which has no input file) to
   --  carry a prior run's attestation forward onto a freshly-generated
   --  document per section 1.6.2's carry-forward MUST.
   --  fusa:req REQ-120
   procedure Write (W : in out Fusa.Json.Writer.Instance; Att : Info);

end Fusa.Attestation;
