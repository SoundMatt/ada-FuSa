--  Rendering helpers shared by every finding-emitting command (check,
--  report, and -- once implemented -- the standards gap-report commands).

with Fusa.Json.Writer;

package Fusa.Report is

   function Now_Rfc3339 return String;

   --  Writes the §3.1 common header fields into the currently-open object.
   procedure Write_Header (W : in out Fusa.Json.Writer.Instance; Kind : String);

   --  Writes the §3.2 report-document extension fields (projectRoot is
   --  MUST; project/standard/asil/sil/dal are SHOULD/MAY and each omitted
   --  when blank -- at most one of Asil/Sil/Dal is expected to be
   --  non-blank).
   procedure Write_Report_Extension
     (W : in out Fusa.Json.Writer.Instance;
      Project_Root, Project, Standard, Asil, Sil, Dal : String);

   procedure Write_Findings_Array
     (W : in out Fusa.Json.Writer.Instance; Findings : Finding_List);

   procedure Write_Summary
     (W : in out Fusa.Json.Writer.Instance; Findings : Finding_List);

   function Render_Text (Findings : Finding_List) return String;

   function Render_Sarif (Findings : Finding_List) return String;

   --  True if Findings contains an open ERROR (or open WARNING when
   --  Strict) finding. Disposition support is not implemented in v0.1, so
   --  every finding is open (spec §4.1: "if unimplemented, every finding
   --  is open").
   function Has_Gate_Failure
     (Findings : Finding_List; Strict : Boolean) return Boolean;

end Fusa.Report;
