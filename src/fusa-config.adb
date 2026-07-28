with Ada.Text_IO;
with Fusa.Files;
with Fusa.Json;      use Fusa.Json;
with Fusa.Json.Writer;

package body Fusa.Config is

   ----------------------------------------------------------------------
   --  .fusa.json
   ----------------------------------------------------------------------

   function Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Config_File))
      or else Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Legacy_Config_File)));

   function Default_Config (Name : String) return Project_Config is
      Cfg : Project_Config;
   begin
      Cfg.Name := To_Unbounded_String (Name);
      return Cfg;
   end Default_Config;

   function Load (Project_Root : String) return Project_Config is
      Canonical : constant String := Fusa.Files.Join (Project_Root, Config_File);
      Legacy    : constant String := Fusa.Files.Join (Project_Root, Legacy_Config_File);
      Path      : Unbounded_String;
   begin
      if Fusa.Files.Exists (Canonical) then
         Path := To_Unbounded_String (Canonical);
      elsif Fusa.Files.Exists (Legacy) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: warning: using legacy config file name '" &
            Legacy_Config_File & "' -- rename to '" & Config_File & "'");
         Path := To_Unbounded_String (Legacy);
      else
         raise No_Config_Error with "no configuration file found: " & Canonical;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (To_String (Path));
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with
                 "parse error in " & To_String (Path);
         end;

         if not Fusa.Json.Is_Object (Root) then
            raise Invalid_Config_Error with
              "root of " & To_String (Path) & " must be a JSON object";
         end if;

         declare
            Cfg  : Project_Config;
            Proj : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Member (Root, "project");
         begin
            --  Legacy flat `"project": "name"` string form (MUST accept,
            --  normalise on next Save).
            if Proj /= null and then Proj.Kind = Fusa.Json.Json_String then
               Cfg.Name    := Proj.Str_Val;
               Cfg.Version := To_Unbounded_String ("0.1.0");
            elsif Fusa.Json.Is_Object (Proj) then
               Cfg.Name    := To_Unbounded_String (Fusa.Json.Get_String (Proj, "name"));
               Cfg.Version :=
                 To_Unbounded_String (Fusa.Json.Get_String (Proj, "version", "0.1.0"));
            elsif Proj /= null then
               --  Present, but neither the legacy string form nor the
               --  nested object form -- distinguish this from "absent" so
               --  the error doesn't misleadingly say "missing".
               raise Invalid_Config_Error with
                 "'project' must be a string or an object in " & To_String (Path);
            end if;

            Cfg.Standard :=
              To_Unbounded_String (Fusa.Json.Get_String (Root, "standard", "generic"));
            Cfg.Asil   := To_Unbounded_String (Fusa.Json.Get_String (Root, "asil"));
            Cfg.Sil    := To_Unbounded_String (Fusa.Json.Get_String (Root, "sil"));
            Cfg.Dal    := To_Unbounded_String (Fusa.Json.Get_String (Root, "dal"));
            Cfg.Strict := Fusa.Json.Get_Bool (Root, "strict", False);

            declare
               Sd : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Get_Array (Root, "sourceDirs");
            begin
               for I in 1 .. Fusa.Json.Array_Length (Sd) loop
                  Cfg.Source_Dirs.Append
                    (Fusa.Json.As_String (Fusa.Json.Array_Item (Sd, I)));
               end loop;
            end;
            declare
               Ex : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Get_Array (Root, "excludePatterns");
            begin
               for I in 1 .. Fusa.Json.Array_Length (Ex) loop
                  Cfg.Exclude_Patterns.Append
                    (Fusa.Json.As_String (Fusa.Json.Array_Item (Ex, I)));
               end loop;
            end;

            if Length (Cfg.Name) = 0 then
               raise Invalid_Config_Error with
                 "missing required field 'project.name' in " & To_String (Path);
            end if;

            return Cfg;
         end;
      end;
   end Load;

   procedure Save (Project_Root : String; Cfg : Project_Config) is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Field ("configVersion", Config_File_Version);
      W.Key ("project");
      W.Object_Start;
      W.Field ("name", To_String (Cfg.Name));
      W.Field ("version", To_String (Cfg.Version));
      W.Object_End;
      W.Field ("standard", To_String (Cfg.Standard));
      W.Field_If_Non_Blank ("asil", To_String (Cfg.Asil));
      W.Field_If_Non_Blank ("sil", To_String (Cfg.Sil));
      W.Field_If_Non_Blank ("dal", To_String (Cfg.Dal));
      if not Cfg.Source_Dirs.Is_Empty then
         W.Key ("sourceDirs");
         W.Array_Start;
         for D of Cfg.Source_Dirs loop
            W.Value (D);
         end loop;
         W.Array_End;
      end if;
      if not Cfg.Exclude_Patterns.Is_Empty then
         W.Key ("excludePatterns");
         W.Array_Start;
         for P of Cfg.Exclude_Patterns loop
            W.Value (P);
         end loop;
         W.Array_End;
      end if;
      if Cfg.Strict then
         W.Field ("strict", True);
      end if;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Config_File),
         Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Save;

   ----------------------------------------------------------------------
   --  .fusa-reqs.json
   ----------------------------------------------------------------------

   function Requirements_Exist (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Reqs_File))
      or else Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Legacy_Reqs_File)));

   function Load_Requirements
     (Project_Root : String;
      Findings     : in out Finding_List) return Requirement_List
   is
      Result    : Requirement_List;
      Canonical : constant String := Fusa.Files.Join (Project_Root, Reqs_File);
      Legacy    : constant String := Fusa.Files.Join (Project_Root, Legacy_Reqs_File);
      Path      : Unbounded_String;
   begin
      if Fusa.Files.Exists (Canonical) then
         Path := To_Unbounded_String (Canonical);
      elsif Fusa.Files.Exists (Legacy) then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: warning: using legacy requirements file name '" &
            Legacy_Reqs_File & "' -- rename to '" & Reqs_File & "'");
         Path := To_Unbounded_String (Legacy);
      else
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (To_String (Path));
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with
                 "parse error in " & To_String (Path);
         end;

         declare
            Reqs : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "requirements");
            Seen : String_List;
            Rel  : constant String :=
              Fusa.Files.Relative_To (Project_Root, To_String (Path));
         begin
            for I in 1 .. Fusa.Json.Array_Length (Reqs) loop
               declare
                  Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Reqs, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  R    : Requirement;
                  Dup  : Boolean := False;
               begin
                  if Id'Length > 0 then
                     for S of Seen loop
                        if S = Id then
                           Dup := True;
                           exit;
                        end if;
                     end loop;

                     if Dup then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "REQ001",
                              Severity    => Error,
                              Message     =>
                                "duplicate requirement id """ & Id & """ in " &
                                Reqs_File,
                              Loc         => Make_Location (Rel),
                              Category    => Fusa.Requirement,
                              Remediation =>
                                "remove or rename the duplicate requirement id"));
                     else
                        Seen.Append (Id);
                        R.Id       := To_Unbounded_String (Id);
                        R.Title    := To_Unbounded_String (Fusa.Json.Get_String (Item, "title"));
                        R.Text     := To_Unbounded_String (Fusa.Json.Get_String (Item, "text"));
                        R.Standard := To_Unbounded_String (Fusa.Json.Get_String (Item, "standard"));
                        R.Level    := To_Unbounded_String (Fusa.Json.Get_String (Item, "level"));
                        R.Asil     := To_Unbounded_String (Fusa.Json.Get_String (Item, "asil"));
                        R.Parent   := To_Unbounded_String (Fusa.Json.Get_String (Item, "parent"));
                        Result.Append (R);
                     end if;
                  else
                     --  A missing/empty/non-string id is just as much a
                     --  spec violation as a duplicate id (both are MUST
                     --  "id" requirements per §1.2) -- it must not vanish
                     --  silently with zero diagnostic output.
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "REQ002",
                           Severity    => Error,
                           Message     =>
                             "requirement at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " &
                             Reqs_File,
                           Loc         => Make_Location (Rel),
                           Category    => Fusa.Requirement,
                           Remediation =>
                             "give this requirement a non-empty string ""id"""));
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Requirements;

   procedure Save_Requirements (Project_Root : String; Reqs : Requirement_List) is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Key ("requirements");
      W.Array_Start;
      for R of Reqs loop
         W.Object_Start;
         W.Field ("id", To_String (R.Id));
         W.Field_If_Non_Blank ("title", To_String (R.Title));
         W.Field_If_Non_Blank ("text", To_String (R.Text));
         W.Field_If_Non_Blank ("standard", To_String (R.Standard));
         W.Field_If_Non_Blank ("level", To_String (R.Level));
         W.Field_If_Non_Blank ("asil", To_String (R.Asil));
         W.Field_If_Non_Blank ("parent", To_String (R.Parent));
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Reqs_File),
         Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Save_Requirements;

   ----------------------------------------------------------------------
   --  .fusa-dispositions.json
   ----------------------------------------------------------------------

   function Dispositions_Exist (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Dispositions_File)));

   function Parse_Status (S : String) return Disposition_Kind is
     (if S = "accepted" then Accepted
      elsif S = "deferred" then Deferred
      elsif S = "rejected" then Rejected
      else Open); --  missing/unrecognised: never applied (see Apply_Dispositions)

   function Load_Dispositions (Project_Root : String) return Disposition_List is
      Result : Disposition_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Dispositions_File);
   begin
      if not Fusa.Files.Exists (Path) then
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with "parse error in " & Path;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "dispositions");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Items, I);
                  Line_Val : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Get_Member (Item, "line");
                  E : Disposition_Entry;
               begin
                  E.Fingerprint := To_Unbounded_String (Fusa.Json.Get_String (Item, "fingerprint"));
                  E.Rule_Id     := To_Unbounded_String (Fusa.Json.Get_String (Item, "ruleId"));
                  E.File        := To_Unbounded_String (Fusa.Json.Get_String (Item, "file"));
                  if Line_Val /= null and then Line_Val.Kind = Fusa.Json.Json_Number
                    and then Line_Val.Num_Val >= 0.0
                  then
                     E.Line := Natural (Line_Val.Num_Val);
                  end if;
                  E.Status  := Parse_Status (Fusa.Json.Get_String (Item, "status"));
                  E.Note    := To_Unbounded_String (Fusa.Json.Get_String (Item, "note"));
                  E.By      := To_Unbounded_String (Fusa.Json.Get_String (Item, "by"));
                  E.At_Time := To_Unbounded_String (Fusa.Json.Get_String (Item, "at"));
                  Result.Append (E);
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Dispositions;

   procedure Apply_Dispositions
     (Findings        : in out Finding_List;
      Disps           : Disposition_List;
      Orphan_Findings : in out Finding_List)
   is
      Used : array (1 .. Integer'Max (Natural (Disps.Length), 1)) of Boolean :=
        (others => False);

      function Matches (E : Disposition_Entry; F : Finding) return Boolean is
      begin
         if E.Status = Open then
            return False; --  missing/unrecognised status: never matches
         end if;
         if Length (E.Fingerprint) > 0 and then Length (F.Fingerprint) > 0 then
            return E.Fingerprint = F.Fingerprint;
         end if;
         if Length (E.Rule_Id) = 0 or else E.Rule_Id /= F.Rule_Id then
            return False;
         end if;
         if Length (E.File) > 0 then
            return E.Line = 0
              or else (E.File = F.Loc.File and then E.Line = F.Loc.Line);
         end if;
         --  Rule-level fallback: ruleId only, no file/line -- matches
         --  every finding for that rule project-wide.
         return True;
      end Matches;
   begin
      for I in 1 .. Natural (Findings.Length) loop
         declare
            F : Finding := Findings.Element (I);
         begin
            --  Fingerprint matches take precedence over the fallback keys
            --  (section 4.1 MUST), so scan for one before falling back.
            for Pass in 1 .. 2 loop
               for J in 1 .. Natural (Disps.Length) loop
                  declare
                     E : constant Disposition_Entry := Disps.Element (J);
                     Is_Fp_Match : constant Boolean :=
                       Length (E.Fingerprint) > 0 and then Length (F.Fingerprint) > 0
                       and then E.Fingerprint = F.Fingerprint;
                  begin
                     if (Pass = 1 and then Is_Fp_Match)
                       or else (Pass = 2 and then not Is_Fp_Match and then Matches (E, F))
                     then
                        F.Disposition := E.Status;
                        Used (J) := True;
                        Findings.Replace_Element (I, F);
                        goto Matched;
                     end if;
                  end;
               end loop;
            end loop;
            <<Matched>>
            null;
         end;
      end loop;

      for J in 1 .. Natural (Disps.Length) loop
         declare
            E : constant Disposition_Entry := Disps.Element (J);
         begin
            if not Used (J) and then (E.Status = Accepted or else E.Status = Deferred) then
               Orphan_Findings.Append
                 (Make_Finding
                    (Rule_Id     => "DISP001",
                     Severity    => Warning,
                     Message     =>
                       "orphaned " & Image (E.Status) & " disposition matches no "
                       & "current finding: " &
                       (if Length (E.Fingerprint) > 0
                        then To_String (E.Fingerprint)
                        else To_String (E.Rule_Id)),
                     Loc         => Make_Location
                       (File => (if Length (E.File) > 0 then To_String (E.File)
                                 else Dispositions_File),
                        Line => E.Line),
                     Category    => Config_Category,
                     Remediation =>
                       "remove the stale disposition entry, or update its "
                       & "match key if the finding moved"));
            end if;
         end;
      end loop;
   end Apply_Dispositions;

   ----------------------------------------------------------------------
   --  .fusa-hara.json
   ----------------------------------------------------------------------

   function Hara_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Hara_File)));

   function Load_Hara
     (Project_Root : String;
      Findings     : in out Finding_List) return Hazard_List
   is
      Result : Hazard_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Hara_File);
   begin
      if not Fusa.Files.Exists (Path) then
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with "parse error in " & Path;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "hazards");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  H    : Hazard;
               begin
                  H.Id              := To_Unbounded_String (Id);
                  H.Description     := To_Unbounded_String (Fusa.Json.Get_String (Item, "hazard"));
                  H.Severity        := To_Unbounded_String (Fusa.Json.Get_String (Item, "severity"));
                  H.Exposure        := To_Unbounded_String (Fusa.Json.Get_String (Item, "exposure"));
                  H.Controllability :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "controllability"));
                  H.Asil            := To_Unbounded_String (Fusa.Json.Get_String (Item, "asil"));
                  H.Safety_Goal     :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "safetyGoal"));

                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "HARA001",
                           Severity    => Error,
                           Message     =>
                             "hazard at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Hara_File,
                           Loc         => Make_Location (Hara_File),
                           Category    => Fusa.Safety,
                           Remediation => "give this hazard a non-empty string ""id"""));
                  else
                     if Length (H.Description) = 0 or else Length (H.Severity) = 0
                       or else Length (H.Exposure) = 0 or else Length (H.Controllability) = 0
                       or else Length (H.Asil) = 0 or else Length (H.Safety_Goal) = 0
                     then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "HARA002",
                              Severity    => Warning,
                              Message     =>
                                "hazard """ & Id & """ is missing one or more of hazard/" &
                                "severity/exposure/controllability/asil/safetyGoal in " &
                                Hara_File,
                              Loc         => Make_Location (Hara_File),
                              Category    => Fusa.Safety,
                              Remediation =>
                                "fill in all fields for a complete ISO 26262-3 hazard entry"));
                     end if;
                     Result.Append (H);
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Hara;

   procedure Scaffold_Hara (Project_Root : String) is
   begin
      if not Hara_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Hara_File), "{" & ASCII.LF &
              "  ""hazards"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Hara;

   ----------------------------------------------------------------------
   --  .fusa-tara.json
   ----------------------------------------------------------------------

   function Tara_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Tara_File)));

   function Load_Tara
     (Project_Root : String;
      Findings     : in out Finding_List) return Threat_List
   is
      Result : Threat_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Tara_File);
   begin
      if not Fusa.Files.Exists (Path) then
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with "parse error in " & Path;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "threats");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  T    : Threat;
               begin
                  T.Id            := To_Unbounded_String (Id);
                  T.Asset         := To_Unbounded_String (Fusa.Json.Get_String (Item, "asset"));
                  T.Description   := To_Unbounded_String (Fusa.Json.Get_String (Item, "threat"));
                  T.Attack_Vector :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "attackVector"));
                  T.Impact        := To_Unbounded_String (Fusa.Json.Get_String (Item, "impact"));
                  T.Likelihood    :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "likelihood"));
                  T.Risk          := To_Unbounded_String (Fusa.Json.Get_String (Item, "risk"));
                  T.Treatment     :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "treatment"));
                  declare
                     Mits : constant Fusa.Json.Value_Access :=
                       Fusa.Json.Get_Array (Item, "mitigations");
                  begin
                     for J in 1 .. Fusa.Json.Array_Length (Mits) loop
                        T.Mitigations.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Mits, J)));
                     end loop;
                  end;

                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "TARA001",
                           Severity    => Error,
                           Message     =>
                             "threat at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Tara_File,
                           Loc         => Make_Location (Tara_File),
                           Category    => Fusa.Security,
                           Remediation => "give this threat a non-empty string ""id"""));
                  else
                     if Length (T.Asset) = 0 or else Length (T.Description) = 0
                       or else Length (T.Attack_Vector) = 0 or else Length (T.Impact) = 0
                       or else Length (T.Likelihood) = 0 or else Length (T.Risk) = 0
                       or else Length (T.Treatment) = 0
                     then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "TARA002",
                              Severity    => Warning,
                              Message     =>
                                "threat """ & Id & """ is missing one or more of asset/" &
                                "threat/attackVector/impact/likelihood/risk/treatment in " &
                                Tara_File,
                              Loc         => Make_Location (Tara_File),
                              Category    => Fusa.Security,
                              Remediation =>
                                "fill in all fields for a complete ISO 21434 ch.9 threat entry"));
                     end if;
                     Result.Append (T);
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Tara;

   procedure Scaffold_Tara (Project_Root : String) is
   begin
      if not Tara_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Tara_File), "{" & ASCII.LF &
              "  ""threats"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Tara;

   ----------------------------------------------------------------------
   --  .fusa-dispositions.json (write side, for `disposition add`)
   ----------------------------------------------------------------------

   procedure Save_Dispositions (Project_Root : String; Disps : Disposition_List) is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Key ("dispositions");
      W.Array_Start;
      for E of Disps loop
         W.Object_Start;
         W.Field_If_Non_Blank ("fingerprint", To_String (E.Fingerprint));
         W.Field_If_Non_Blank ("ruleId", To_String (E.Rule_Id));
         W.Field_If_Non_Blank ("file", To_String (E.File));
         if E.Line > 0 then
            W.Field ("line", E.Line);
         end if;
         W.Field ("status", Image (E.Status));
         W.Field_If_Non_Blank ("note", To_String (E.Note));
         W.Field_If_Non_Blank ("by", To_String (E.By));
         W.Field_If_Non_Blank ("at", To_String (E.At_Time));
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Dispositions_File),
         Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Save_Dispositions;

   ----------------------------------------------------------------------
   --  .fusa-pr.json
   ----------------------------------------------------------------------

   function Pr_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Pr_File)));

   function Load_Pr (Project_Root : String) return Problem_Report_List is
      Result : Problem_Report_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Pr_File);
   begin
      if not Fusa.Files.Exists (Path) then
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with "parse error in " & Path;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "reports");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  P    : Problem_Report;
               begin
                  P.Id         := To_Unbounded_String (Fusa.Json.Get_String (Item, "id"));
                  P.Title      := To_Unbounded_String (Fusa.Json.Get_String (Item, "title"));
                  P.Severity   := To_Unbounded_String (Fusa.Json.Get_String (Item, "severity"));
                  P.Status     :=
                    To_Unbounded_String (Fusa.Json.Get_String (Item, "status", "open"));
                  P.Resolution := To_Unbounded_String (Fusa.Json.Get_String (Item, "resolution"));
                  P.Opened_At  := To_Unbounded_String (Fusa.Json.Get_String (Item, "openedAt"));
                  P.Closed_At  := To_Unbounded_String (Fusa.Json.Get_String (Item, "closedAt"));
                  if Length (P.Id) > 0 then
                     Result.Append (P);
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Pr;

   procedure Save_Pr (Project_Root : String; Reports : Problem_Report_List) is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Key ("reports");
      W.Array_Start;
      for P of Reports loop
         W.Object_Start;
         W.Field ("id", To_String (P.Id));
         W.Field ("title", To_String (P.Title));
         W.Field_If_Non_Blank ("severity", To_String (P.Severity));
         W.Field ("status", To_String (P.Status));
         W.Field_If_Non_Blank ("resolution", To_String (P.Resolution));
         W.Field_If_Non_Blank ("openedAt", To_String (P.Opened_At));
         W.Field_If_Non_Blank ("closedAt", To_String (P.Closed_At));
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Pr_File), Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Save_Pr;

   ----------------------------------------------------------------------
   --  .fusa-metrics.json
   ----------------------------------------------------------------------

   function Get_Natural
     (V : Fusa.Json.Value_Access; Key : String; Default : Natural := 0) return Natural
   is
      M : constant Fusa.Json.Value_Access := Fusa.Json.Get_Member (V, Key);
   begin
      if M = null or else M.Kind /= Fusa.Json.Json_Number or else M.Num_Val < 0.0 then
         return Default;
      end if;
      return Natural (M.Num_Val);
   end Get_Natural;

   function Load_Metrics (Project_Root : String) return Metric_Snapshot_List is
      Result : Metric_Snapshot_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Metrics_File);
   begin
      if not Fusa.Files.Exists (Path) then
         return Result;
      end if;

      declare
         Content : constant String := Fusa.Files.Read_File (Path);
         Root    : Fusa.Json.Value_Access;
      begin
         begin
            Root := Fusa.Json.Parse (Content);
         exception
            when Fusa.Json.Json_Error =>
               raise Invalid_Config_Error with "parse error in " & Path;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "snapshots");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  S    : Metric_Snapshot;
               begin
                  S.At_Time         := To_Unbounded_String (Fusa.Json.Get_String (Item, "at"));
                  S.Total_Reqs      := Get_Natural (Item, "totalRequirements");
                  S.Check_Errors    := Get_Natural (Item, "checkErrors");
                  S.Check_Warnings  := Get_Natural (Item, "checkWarnings");
                  S.Check_Infos     := Get_Natural (Item, "checkInfos");
                  S.Comp_Violations := Get_Natural (Item, "compViolations");
                  Result.Append (S);
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Metrics;

   procedure Save_Metrics (Project_Root : String; Snapshots : Metric_Snapshot_List) is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      W.Key ("snapshots");
      W.Array_Start;
      for S of Snapshots loop
         W.Object_Start;
         W.Field ("at", To_String (S.At_Time));
         W.Field ("totalRequirements", S.Total_Reqs);
         W.Field ("checkErrors", S.Check_Errors);
         W.Field ("checkWarnings", S.Check_Warnings);
         W.Field ("checkInfos", S.Check_Infos);
         W.Field ("compViolations", S.Comp_Violations);
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Metrics_File), Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Save_Metrics;

end Fusa.Config;
