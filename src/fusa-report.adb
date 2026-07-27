with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Fusa.Report is

   function Trim_Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   function Now_Rfc3339 return String is
      S : constant String :=
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock, Time_Zone => 0);
   begin
      --  S is "YYYY-MM-DD HH:MM:SS" (19 chars) -> "YYYY-MM-DDTHH:MM:SSZ"
      return S (S'First .. S'First + 9) & "T" & S (S'First + 11 .. S'Last) & "Z";
   end Now_Rfc3339;

   procedure Write_Header (W : in out Fusa.Json.Writer.Instance; Kind : String) is
   begin
      W.Field ("schemaVersion", Fusa.Spec_Version);
      W.Field ("kind", Kind);
      W.Field ("tool", Fusa.Tool_Name);
      W.Field ("toolVersion", Fusa.Version);
      W.Field ("language", "ada");
      W.Field ("generatedAt", Now_Rfc3339);
   end Write_Header;

   procedure Write_Report_Extension
     (W : in out Fusa.Json.Writer.Instance;
      Project_Root, Project, Standard, Asil, Sil, Dal : String)
   is
   begin
      W.Field ("projectRoot", Project_Root);
      W.Field_If_Non_Blank ("project", Project);
      W.Field_If_Non_Blank ("standard", Standard);
      W.Field_If_Non_Blank ("asil", Asil);
      W.Field_If_Non_Blank ("sil", Sil);
      W.Field_If_Non_Blank ("dal", Dal);
   end Write_Report_Extension;

   procedure Write_Findings_Array
     (W : in out Fusa.Json.Writer.Instance; Findings : Finding_List)
   is
   begin
      W.Key ("findings");
      W.Array_Start;
      for F of Findings loop
         W.Object_Start;
         W.Field ("ruleId", To_String (F.Rule_Id));
         W.Field ("severity", Image (F.Severity));
         W.Field ("message", To_String (F.Message));
         W.Key ("location");
         W.Object_Start;
         W.Field ("file", To_String (F.Loc.File));
         if F.Loc.Line > 0 then
            W.Field ("line", F.Loc.Line);
         end if;
         if F.Loc.Column > 0 then
            W.Field ("column", F.Loc.Column);
         end if;
         if F.Loc.End_Line > 0 then
            W.Field ("endLine", F.Loc.End_Line);
         end if;
         if F.Loc.End_Column > 0 then
            W.Field ("endColumn", F.Loc.End_Column);
         end if;
         W.Object_End;
         W.Field ("category", Image (F.Category));
         W.Field_If_Non_Blank ("standard", To_String (F.Standard));
         W.Field_If_Non_Blank ("clause", To_String (F.Clause));
         W.Field ("remediation", To_String (F.Remediation));
         if F.Disposition /= Open then
            W.Field ("disposition", Image (F.Disposition));
         end if;
         W.Field ("fingerprint", To_String (F.Fingerprint));
         W.Object_End;
      end loop;
      W.Array_End;
   end Write_Findings_Array;

   procedure Write_Summary
     (W : in out Fusa.Json.Writer.Instance; Findings : Finding_List)
   is
      Errors, Warnings, Infos : Natural := 0;
   begin
      for F of Findings loop
         case F.Severity is
            when Error   => Errors   := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => Infos    := Infos + 1;
         end case;
      end loop;
      W.Key ("summary");
      W.Object_Start;
      W.Field ("total", Natural (Findings.Length));
      W.Field ("errors", Errors);
      W.Field ("warnings", Warnings);
      W.Field ("infos", Infos);
      W.Object_End;
   end Write_Summary;

   function Render_Text (Findings : Finding_List) return String is
      Buf : Unbounded_String := Null_Unbounded_String;
      Errors, Warnings, Infos : Natural := 0;
   begin
      if Findings.Is_Empty then
         return "No findings.";
      end if;
      for F of Findings loop
         case F.Severity is
            when Error   => Errors   := Errors + 1;
            when Warning => Warnings := Warnings + 1;
            when Info    => Infos    := Infos + 1;
         end case;
         Append (Buf, "[" & Image (F.Severity) & "] " & To_String (F.Rule_Id) &
                   " " & To_String (F.Loc.File));
         if F.Loc.Line > 0 then
            Append (Buf, ":" & Trim_Img (F.Loc.Line));
         end if;
         Append (Buf, " " & To_String (F.Message) & ASCII.LF);
      end loop;
      Append (Buf, Trim_Img (Natural (Findings.Length)) & " findings (" &
                Trim_Img (Errors) & " errors, " & Trim_Img (Warnings) &
                " warnings, " & Trim_Img (Infos) & " infos)");
      return To_String (Buf);
   end Render_Text;

   function Render_Sarif (Findings : Finding_List) return String is
      W          : Fusa.Json.Writer.Instance;
      Seen_Rules : String_List;
   begin
      W.Object_Start;
      W.Field ("version", "2.1.0");
      W.Field ("$schema",
        "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json");
      W.Key ("runs");
      W.Array_Start;
      W.Object_Start;
      W.Key ("tool");
      W.Object_Start;
      W.Key ("driver");
      W.Object_Start;
      W.Field ("name", Fusa.Tool_Name);
      W.Field ("informationUri", "https://github.com/SoundMatt/ada-FuSa");
      W.Field ("version", Fusa.Version);
      W.Key ("rules");
      W.Array_Start;
      for F of Findings loop
         declare
            Rid     : constant String := To_String (F.Rule_Id);
            Already : Boolean := False;
         begin
            for S of Seen_Rules loop
               if S = Rid then
                  Already := True;
                  exit;
               end if;
            end loop;
            if not Already then
               Seen_Rules.Append (Rid);
               W.Object_Start;
               W.Field ("id", Rid);
               W.Key ("shortDescription");
               W.Object_Start;
               W.Field ("text", To_String (F.Message));
               W.Object_End;
               W.Object_End;
            end if;
         end;
      end loop;
      W.Array_End;
      W.Object_End;
      W.Object_End;
      W.Key ("results");
      W.Array_Start;
      for F of Findings loop
         W.Object_Start;
         W.Field ("ruleId", To_String (F.Rule_Id));
         W.Field ("level",
           (case F.Severity is
              when Error   => "error",
              when Warning => "warning",
              when Info    => "note"));
         W.Key ("message");
         W.Object_Start;
         W.Field ("text", To_String (F.Message));
         W.Object_End;
         W.Key ("locations");
         W.Array_Start;
         W.Object_Start;
         W.Key ("physicalLocation");
         W.Object_Start;
         W.Key ("artifactLocation");
         W.Object_Start;
         W.Field ("uri", To_String (F.Loc.File));
         W.Object_End;
         if F.Loc.Line > 0 then
            W.Key ("region");
            W.Object_Start;
            W.Field ("startLine", F.Loc.Line);
            if F.Loc.Column > 0 then
               W.Field ("startColumn", F.Loc.Column);
            end if;
            if F.Loc.End_Line > 0 then
               W.Field ("endLine", F.Loc.End_Line);
            end if;
            if F.Loc.End_Column > 0 then
               W.Field ("endColumn", F.Loc.End_Column);
            end if;
            W.Object_End;
         end if;
         W.Object_End;
         W.Object_End;
         W.Array_End;
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      W.Array_End;
      W.Object_End;
      return Fusa.Json.Writer.To_String (W);
   end Render_Sarif;

   function Has_Gate_Failure
     (Findings : Finding_List; Strict : Boolean) return Boolean
   is
   begin
      for F of Findings loop
         if F.Disposition = Open then
            if F.Severity = Error then
               return True;
            end if;
            if Strict and then F.Severity = Warning then
               return True;
            end if;
         end if;
      end loop;
      return False;
   end Has_Gate_Failure;

end Fusa.Report;
