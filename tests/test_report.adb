with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Fusa; use Fusa;
with Fusa.Report;
with Fusa.Json;
use type Fusa.Json.Value_Access;
with Fusa.Json.Writer;
with Test_Framework; use Test_Framework;

procedure Test_Report is
begin
   Check (Fusa.Report.Now_Rfc3339'Length = 20, "RFC3339 timestamp is 20 characters");
   Check (Fusa.Report.Now_Rfc3339 (11) = 'T', "RFC3339 timestamp has 'T' at position 11");
   Check (Fusa.Report.Now_Rfc3339 (20) = 'Z', "RFC3339 timestamp ends with 'Z'");

   Check (Fusa.Report.Render_Text (Finding_Vectors.Empty_Vector) = "No findings.",
          "Render_Text reports 'No findings.' for an empty list");

   declare
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "e1", Make_Location ("a.adb", 1)));
      Findings.Append
        (Make_Finding ("ADA002", Warning, "w1", Make_Location ("b.adb")));
      Findings.Append
        (Make_Finding ("ADA007", Info, "i1", Make_Location ("c.adb")));

      declare
         Text : constant String := Fusa.Report.Render_Text (Findings);
      begin
         Check (Text'Length > 0, "Render_Text produces non-empty output for findings");
      end;
   end;

   declare
      Error_Only : Finding_List;
      Warn_Only  : Finding_List;
   begin
      Error_Only.Append
        (Make_Finding ("ADA001", Error, "e", Make_Location ("a.adb")));
      Check (Fusa.Report.Has_Gate_Failure (Error_Only, False),
             "an ERROR finding gates even without --strict");
      Check (Fusa.Report.Has_Gate_Failure (Error_Only, True),
             "an ERROR finding gates with --strict too");

      Warn_Only.Append
        (Make_Finding ("ADA002", Warning, "w", Make_Location ("a.adb")));
      Check (not Fusa.Report.Has_Gate_Failure (Warn_Only, False),
             "a WARNING-only list does not gate without --strict");
      Check (Fusa.Report.Has_Gate_Failure (Warn_Only, True),
             "a WARNING-only list gates under --strict");
   end;

   --  SARIF: valid structure, correct severity mapping.
   declare
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "e", Make_Location ("a.adb", 3, 2, 3, 5)));
      Findings.Append
        (Make_Finding ("ADA007", Info, "i", Make_Location ("b.adb")));

      declare
         Sarif : constant String := Fusa.Report.Render_Sarif (Findings);
         V     : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Sarif);
      begin
         Check (Fusa.Json.Get_String (V, "version") = "2.1.0", "SARIF version is 2.1.0");
         Check (Fusa.Json.Is_Array (Fusa.Json.Get_Array (V, "runs")),
                "SARIF has a runs array");

         --  fusa:test REQ-022
         declare
            Run     : constant Fusa.Json.Value_Access :=
              Fusa.Json.Array_Item (Fusa.Json.Get_Array (V, "runs"), 1);
            Result  : constant Fusa.Json.Value_Access :=
              Fusa.Json.Array_Item (Fusa.Json.Get_Array (Run, "results"), 1);
            Props   : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Member (Result, "properties");
         begin
            Check (Props /= null and then Fusa.Json.Has_Key (Props, "category"),
                   "SARIF result carries a properties.category (spec section 2.9)");
         end;
      end;
   end;

   --  fusa:test REQ-073
   --  fusa:test REQ-074
   Check (Fusa.Report.Render_Html (Finding_Vectors.Empty_Vector)'Length > 0,
          "Render_Html produces non-empty output for an empty findings list");
   Check (Fusa.Report.Render_Md (Finding_Vectors.Empty_Vector)'Length > 0,
          "Render_Md produces non-empty output for an empty findings list");

   declare
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "a <b> & ""c"" message",
                       Make_Location ("a.adb", 3)));
      Findings.Append
        (Make_Finding ("ADA002", Warning, "a | pipe in the message",
                       Make_Location ("b.adb")));

      declare
         Html : constant String := Fusa.Report.Render_Html (Findings);
      begin
         Check (Ada.Strings.Fixed.Index (Html, "<!doctype html>") = 1,
                "Render_Html starts with a doctype declaration");
         Check (Ada.Strings.Fixed.Index (Html, "ADA001") > 0
                and then Ada.Strings.Fixed.Index (Html, "ADA002") > 0,
                "Render_Html includes every finding's rule id");
         Check (Ada.Strings.Fixed.Index (Html, "a &lt;b&gt; &amp; &quot;c&quot; message") > 0,
                "Render_Html HTML-escapes <, >, &, and """" in the message");
      end;

      declare
         Md : constant String := Fusa.Report.Render_Md (Findings);
      begin
         Check (Ada.Strings.Fixed.Index (Md, "# " & Fusa.Tool_Name) = 1,
                "Render_Md starts with a level-1 heading");
         Check (Ada.Strings.Fixed.Index (Md, "| ERROR | ADA001") > 0,
                "Render_Md includes a table row for each finding");
         Check (Ada.Strings.Fixed.Index (Md, "a \| pipe in the message") > 0,
                "Render_Md escapes a literal '|' in the message so it doesn't "
                & "split the GFM table");
      end;
   end;

   --  Header + report-extension + findings + summary composition.
   declare
      W        : Fusa.Json.Writer.Instance;
      Findings : Finding_List;
   begin
      Findings.Append
        (Make_Finding ("ADA001", Error, "e", Make_Location ("a.adb")));
      W.Object_Start;
      --  fusa:test REQ-003
      Fusa.Report.Write_Header (W, "check-report");
      Fusa.Report.Write_Report_Extension (W, "/root", "proj", "iso26262", "ASIL-B", "", "");
      Fusa.Report.Write_Findings_Array (W, Findings);
      Fusa.Report.Write_Summary (W, Findings);
      W.Object_End;

      declare
         V : constant Fusa.Json.Value_Access :=
           Fusa.Json.Parse (Fusa.Json.Writer.To_String (W));
      begin
         Check (Fusa.Json.Get_String (V, "kind") = "check-report", "kind field is check-report");
         Check (Fusa.Json.Get_String (V, "projectRoot") = "/root", "projectRoot round-trips");
         Check (Fusa.Json.Get_String (V, "asil") = "ASIL-B", "asil round-trips, sil/dal omitted");
         Check (not Fusa.Json.Has_Key (V, "sil"),
                "blank sil is omitted rather than emitted as an empty string");
         Check (Fusa.Json.Is_Object (Fusa.Json.Get_Member (V, "summary")),
                "summary object is present");
      end;
   end;
end Test_Report;
