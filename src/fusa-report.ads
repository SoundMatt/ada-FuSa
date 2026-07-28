--  Rendering helpers shared by every finding-emitting command (check,
--  report, and -- once implemented -- the standards gap-report commands).

with Fusa.Json.Writer;

package Fusa.Report is

   --  fusa:req REQ-063
   function Now_Rfc3339 return String;

   --  Writes the §3.1 common header fields into the currently-open object.
   --  fusa:req REQ-064
   procedure Write_Header (W : in out Fusa.Json.Writer.Instance; Kind : String);

   --  Writes the §3.2 report-document extension fields (projectRoot is
   --  MUST; project/standard/asil/sil/dal are SHOULD/MAY and each omitted
   --  when blank -- at most one of Asil/Sil/Dal is expected to be
   --  non-blank).
   --  fusa:req REQ-065
   procedure Write_Report_Extension
     (W : in out Fusa.Json.Writer.Instance;
      Project_Root, Project, Standard, Asil, Sil, Dal : String);

   --  fusa:req REQ-066
   procedure Write_Findings_Array
     (W : in out Fusa.Json.Writer.Instance; Findings : Finding_List);

   --  Key defaults to "summary", the shape every command except the
   --  standards gap-report commands uses. Gap-report documents reserve
   --  "summary" for the canonical objectives tally (§9.3) and pass a
   --  different Key for this general findings tally so the two don't
   --  collide under the same object.
   --  fusa:req REQ-067
   procedure Write_Summary
     (W        : in out Fusa.Json.Writer.Instance;
      Findings : Finding_List;
      Key      : String := "summary");

   --  fusa:req REQ-068
   function Render_Text (Findings : Finding_List) return String;

   --  fusa:req REQ-022
   function Render_Sarif (Findings : Finding_List) return String;

   --  A self-contained HTML page with a findings table, suitable for
   --  sharing outside a terminal (e.g. as a CI artifact opened in a
   --  browser).
   --  fusa:req REQ-073
   function Render_Html (Findings : Finding_List) return String;

   --  A findings table in GitHub-Flavored Markdown, embeddable in a PR
   --  description or project docs.
   --  fusa:req REQ-074
   function Render_Md (Findings : Finding_List) return String;

   --  True if Findings contains an open ERROR (or open WARNING when
   --  Strict) finding, per section 4.1's disposition/gate rules (an
   --  "accepted"/"deferred" waiver suppresses the gate; "rejected" does
   --  not).
   --  fusa:req REQ-069
   function Has_Gate_Failure
     (Findings : Finding_List; Strict : Boolean) return Boolean;

end Fusa.Report;
