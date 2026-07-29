with Ada.Text_IO;
with Ada.Strings.Fixed;
with Fusa.Files;
with Fusa.Json;      use Fusa.Json;
with Fusa.Json.Writer;

package body Fusa.Config is

   function Trim_Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

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
            --  A file-scoped entry (no "line") matches only within that
            --  file, at any line; a file+line-scoped entry matches only
            --  that exact location. Regression: this used to be
            --  "E.Line = 0 or else (...)", which short-circuited to
            --  True for ANY finding once Line was omitted, without ever
            --  consulting E.File -- silently broadening a file-scoped
            --  waiver into a project-wide one and defeating the gate for
            --  every other file.
            if E.Line = 0 then
               return E.File = F.Loc.File;
            else
               return E.File = F.Loc.File and then E.Line = F.Loc.Line;
            end if;
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

   --  ISO 26262-3:2018 Table 4 -- Determination of ASIL, indexed by
   --  S (1..3), E (1..4), C (1..3). This is the published, standard
   --  determination table, not project-specific interpretation.
   type Asil_Rank is (Qm, A_Rank, B_Rank, C_Rank, D_Rank);
   type Asil_Table_Type is array (1 .. 3, 1 .. 4, 1 .. 3) of Asil_Rank;
   Asil_Table : constant Asil_Table_Type :=
     (1 => --  S1
        (1 => (Qm, Qm, Qm),
         2 => (Qm, Qm, Qm),
         3 => (Qm, Qm, A_Rank),
         4 => (Qm, A_Rank, B_Rank)),
      2 => --  S2
        (1 => (Qm, Qm, Qm),
         2 => (Qm, Qm, A_Rank),
         3 => (Qm, A_Rank, B_Rank),
         4 => (A_Rank, B_Rank, C_Rank)),
      3 => --  S3
        (1 => (Qm, Qm, A_Rank),
         2 => (Qm, A_Rank, B_Rank),
         3 => (A_Rank, B_Rank, C_Rank),
         4 => (B_Rank, C_Rank, D_Rank)));

   function Determine_Asil
     (Severity, Exposure, Controllability : String) return String
   is
      function Parse_Code (S : String; Prefix : Character; Max : Positive) return Natural is
      begin
         if S'Length = 2 and then S (S'First) = Prefix
           and then S (S'First + 1) in '0' .. '9'
         then
            declare
               V : constant Natural :=
                 Character'Pos (S (S'First + 1)) - Character'Pos ('0');
            begin
               if V <= Max then
                  return V;
               end if;
            end;
         end if;
         return 0;
      end Parse_Code;

      S_Val : constant Natural := Parse_Code (Severity, 'S', 3);
      E_Val : constant Natural := Parse_Code (Exposure, 'E', 4);
      C_Val : constant Natural := Parse_Code (Controllability, 'C', 3);
   begin
      if S_Val in 1 .. 3 and then E_Val in 1 .. 4 and then C_Val in 1 .. 3 then
         case Asil_Table (S_Val, E_Val, C_Val) is
            when Qm     => return "QM";
            when A_Rank => return "ASIL-A";
            when B_Rank => return "ASIL-B";
            when C_Rank => return "ASIL-C";
            when D_Rank => return "ASIL-D";
         end case;
      end if;
      return "";
   end Determine_Asil;

   function Load_Hara
     (Project_Root : String;
      Findings     : in out Finding_List) return Hara_Document
   is
      Result : Hara_Document;
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

         Result.Project    := To_Unbounded_String (Fusa.Json.Get_String (Root, "project"));
         Result.Standard   := To_Unbounded_String (Fusa.Json.Get_String (Root, "standard"));
         Result.Created_At := To_Unbounded_String (Fusa.Json.Get_String (Root, "createdAt"));

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "operationalSituations");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  Desc : constant String := Fusa.Json.Get_String (Item, "description");
                  OS   : Operational_Situation;
               begin
                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "HARA001",
                           Severity    => Error,
                           Message     =>
                             "operational situation at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Hara_File,
                           Loc         => Make_Location (Hara_File),
                           Category    => Fusa.Safety,
                           Remediation =>
                             "give this operational situation a non-empty string ""id"""));
                  else
                     OS.Id          := To_Unbounded_String (Id);
                     OS.Description := To_Unbounded_String (Desc);
                     if Desc'Length = 0 then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "HARA002",
                              Severity    => Warning,
                              Message     =>
                                "operational situation """ & Id &
                                """ is missing description in " & Hara_File,
                              Loc         => Make_Location (Hara_File),
                              Category    => Fusa.Safety,
                              Remediation => "describe this operational situation"));
                     end if;
                     Result.Operational_Situations.Append (OS);
                  end if;
               end;
            end loop;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "hazards");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  H    : Hazard;
               begin
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
                     H.Id          := To_Unbounded_String (Id);
                     H.Description := To_Unbounded_String (Fusa.Json.Get_String (Item, "description"));
                     H.Source      := To_Unbounded_String (Fusa.Json.Get_String (Item, "source"));

                     declare
                        Sits : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "situations");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Sits) loop
                           H.Situations.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Sits, J)));
                        end loop;
                     end;
                     declare
                        Sgs : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "safetyGoals");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Sgs) loop
                           H.Safety_Goals.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (Sgs, J)));
                        end loop;
                     end;

                     declare
                        Risk_Obj : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Member (Item, "risk");
                        Sev      : constant String := Fusa.Json.Get_String (Risk_Obj, "severity");
                        Exp      : constant String := Fusa.Json.Get_String (Risk_Obj, "exposure");
                        Ctl      : constant String :=
                          Fusa.Json.Get_String (Risk_Obj, "controllability");
                        Derived  : constant String := Determine_Asil (Sev, Exp, Ctl);
                     begin
                        H.Risk.Severity        := To_Unbounded_String (Sev);
                        H.Risk.Exposure        := To_Unbounded_String (Exp);
                        H.Risk.Controllability := To_Unbounded_String (Ctl);
                        H.Risk.Asil            := To_Unbounded_String (Derived);
                        if Derived'Length = 0 then
                           Findings.Append
                             (Make_Finding
                                (Rule_Id     => "HARA003",
                                 Severity    => Warning,
                                 Message     =>
                                   "hazard """ & Id & """ has an unrecognised severity/" &
                                   "exposure/controllability code (expected S1-S3/E1-E4/" &
                                   "C1-C3) in " & Hara_File,
                                 Loc         => Make_Location (Hara_File),
                                 Category    => Fusa.Safety,
                                 Remediation =>
                                   "use standard ISO 26262-3 severity/exposure/" &
                                   "controllability codes"));
                        end if;
                     end;

                     if Length (H.Description) = 0 or else H.Situations.Is_Empty
                       or else H.Safety_Goals.Is_Empty
                     then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "HARA002",
                              Severity    => Warning,
                              Message     =>
                                "hazard """ & Id & """ is missing one or more of " &
                                "description/situations/safetyGoals in " & Hara_File,
                              Loc         => Make_Location (Hara_File),
                              Category    => Fusa.Safety,
                              Remediation =>
                                "fill in all required fields for a complete ISO 26262-3 " &
                                "hazard entry"));
                     end if;

                     Result.Hazards.Append (H);
                  end if;
               end;
            end loop;
         end;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "safetyGoals");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  SG   : Safety_Goal;
               begin
                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "HARA001",
                           Severity    => Error,
                           Message     =>
                             "safety goal at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Hara_File,
                           Loc         => Make_Location (Hara_File),
                           Category    => Fusa.Safety,
                           Remediation => "give this safety goal a non-empty string ""id"""));
                  else
                     SG.Id          := To_Unbounded_String (Id);
                     SG.Description := To_Unbounded_String (Fusa.Json.Get_String (Item, "description"));
                     SG.Asil        := To_Unbounded_String (Fusa.Json.Get_String (Item, "asil"));
                     SG.Safe_State  := To_Unbounded_String (Fusa.Json.Get_String (Item, "safeState"));
                     declare
                        Hz : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Item, "hazards");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Hz) loop
                           SG.Hazards.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Hz, J)));
                        end loop;
                     end;
                     declare
                        Fr : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "fssrRefs");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Fr) loop
                           SG.Fssr_Refs.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Fr, J)));
                        end loop;
                     end;

                     if Length (SG.Description) = 0 or else Length (SG.Asil) = 0 then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "HARA002",
                              Severity    => Warning,
                              Message     =>
                                "safety goal """ & Id &
                                """ is missing one or more of description/asil in " & Hara_File,
                              Loc         => Make_Location (Hara_File),
                              Category    => Fusa.Safety,
                              Remediation =>
                                "fill in all required fields for a complete safety goal"));
                     end if;
                     if SG.Fssr_Refs.Is_Empty then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "HARA004",
                              Severity    => Warning,
                              Message     =>
                                "safety goal """ & Id & """ has no fssrRefs -- a safety " &
                                "goal with no decomposing requirement cannot be traced " &
                                "(ISO 26262-8 Clause 6) in " & Hara_File,
                              Loc         => Make_Location (Hara_File),
                              Category    => Fusa.Requirement,
                              Remediation =>
                                "add at least one fssrRefs entry linking a functional " &
                                "safety requirement"));
                     end if;

                     Result.Safety_Goals.Append (SG);
                  end if;
               end;
            end loop;
         end;
      end;

      --  Referential integrity across the id cross-references, plus
      --  fssrRefs resolution into .fusa-reqs.json (section 1.2.5 MUST).
      declare
         function Situation_Exists (Id : String) return Boolean is
           (for some OS of Result.Operational_Situations => To_String (OS.Id) = Id);
         function Hazard_Id_Exists (Id : String) return Boolean is
           (for some H of Result.Hazards => To_String (H.Id) = Id);
         function Safety_Goal_Exists (Id : String) return Boolean is
           (for some SG of Result.Safety_Goals => To_String (SG.Id) = Id);

         Req_Findings : Finding_List;
         Reqs         : constant Requirement_List := Load_Requirements (Project_Root, Req_Findings);

         function Req_Exists (Id : String) return Boolean is
           (for some R of Reqs => To_String (R.Id) = Id);
      begin
         for H of Result.Hazards loop
            for S of H.Situations loop
               if not Situation_Exists (S) then
                  Result.Dangling_References := Result.Dangling_References + 1;
                  Findings.Append
                    (Make_Finding
                       (Rule_Id     => "HARA005",
                        Severity    => Warning,
                        Message     =>
                          "hazard """ & To_String (H.Id) & """ references situation """ &
                          S & """, which does not exist in " & Hara_File,
                        Loc         => Make_Location (Hara_File),
                        Category    => Fusa.Safety,
                        Remediation => "add the missing operational situation, or fix the reference"));
               end if;
            end loop;
            for SG of H.Safety_Goals loop
               if not Safety_Goal_Exists (SG) then
                  Result.Dangling_References := Result.Dangling_References + 1;
                  Findings.Append
                    (Make_Finding
                       (Rule_Id     => "HARA005",
                        Severity    => Warning,
                        Message     =>
                          "hazard """ & To_String (H.Id) & """ references safety goal """ &
                          SG & """, which does not exist in " & Hara_File,
                        Loc         => Make_Location (Hara_File),
                        Category    => Fusa.Safety,
                        Remediation => "add the missing safety goal, or fix the reference"));
               end if;
            end loop;
         end loop;
         for SG of Result.Safety_Goals loop
            for H of SG.Hazards loop
               if not Hazard_Id_Exists (H) then
                  Result.Dangling_References := Result.Dangling_References + 1;
                  Findings.Append
                    (Make_Finding
                       (Rule_Id     => "HARA005",
                        Severity    => Warning,
                        Message     =>
                          "safety goal """ & To_String (SG.Id) & """ references hazard """ &
                          H & """, which does not exist in " & Hara_File,
                        Loc         => Make_Location (Hara_File),
                        Category    => Fusa.Safety,
                        Remediation => "add the missing hazard, or fix the reference"));
               end if;
            end loop;
            for R of SG.Fssr_Refs loop
               if not Req_Exists (R) then
                  Result.Dangling_References := Result.Dangling_References + 1;
                  Findings.Append
                    (Make_Finding
                       (Rule_Id     => "HARA006",
                        Severity    => Warning,
                        Message     =>
                          "safety goal """ & To_String (SG.Id) & """ references " &
                          "requirement """ & R & """, which does not exist in " & Reqs_File,
                        Loc         => Make_Location (Hara_File),
                        Category    => Fusa.Requirement,
                        Remediation =>
                          "add the requirement to " & Reqs_File & ", or fix the reference"));
               end if;
            end loop;
         end loop;
      end;

      return Result;
   end Load_Hara;

   procedure Scaffold_Hara (Project_Root : String; Standard : String; Project : String := "") is
   begin
      if not Hara_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Hara_File), "{" & ASCII.LF &
              "  ""project"": """ & Project & """," & ASCII.LF &
              "  ""standard"": """ & Standard & """," & ASCII.LF &
              "  ""operationalSituations"": []," & ASCII.LF &
              "  ""hazards"": []," & ASCII.LF &
              "  ""safetyGoals"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Hara;

   ----------------------------------------------------------------------
   --  .fusa-tara.json
   ----------------------------------------------------------------------

   function Tara_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Tara_File)));

   function Determine_Tara_Risk
     (Attack_Feasibility : String; Impact : Sfop_Impact) return String
   is
      --  Two DISTINCT closed enums (section 9.2, v1.14.1) -- deliberately
      --  not the same scale, since they answer different questions
      --  (likelihood vs. damage). Impact_Rank's "Unknown" is a sentinel
      --  for "not one of the four recognised values", ranked below
      --  Negligible so an unrecognised axis never wins Consider's
      --  highest-of-four comparison against a real one.
      type Impact_Rank is (Unknown, Negligible, Moderate, Major, Critical);
      type Feasibility_Rank is (Unrecognised, Very_Low, Low, Medium, High);
      type Risk_Level is (R_Low, R_Medium, R_High, R_Critical);

      function Impact_Of (S : String) return Impact_Rank is
        (if S = "negligible" then Negligible
         elsif S = "moderate" then Moderate
         elsif S = "major"    then Major
         elsif S = "critical" then Critical
         else Unknown);

      function Feasibility_Of (S : String) return Feasibility_Rank is
        (if S = "very-low" then Very_Low
         elsif S = "low"    then Low
         elsif S = "medium" then Medium
         elsif S = "high"   then High
         else Unrecognised);

      --  The x-FuSa family's own canonical feasibility x impact -> risk
      --  table (section 9.2, v1.14.1) -- ISO/SAE 21434 leaves risk
      --  determination organization-defined, so this is not a claimed
      --  external standard table the way ISO 26262-3 Table 4 is for
      --  ASIL, just the family's shared convention.
      Table : constant array
        (Impact_Rank range Negligible .. Critical,
         Feasibility_Rank range Very_Low .. High) of Risk_Level :=
        (Negligible => (Very_Low => R_Low,    Low => R_Low,    Medium => R_Low,      High => R_Low),
         Moderate   => (Very_Low => R_Low,    Low => R_Low,    Medium => R_Medium,   High => R_Medium),
         Major      => (Very_Low => R_Medium, Low => R_Medium, Medium => R_High,     High => R_High),
         Critical   => (Very_Low => R_Medium, Low => R_High,   Medium => R_Critical, High => R_Critical));

      Raw_Feas : constant Feasibility_Rank := Feasibility_Of (Attack_Feasibility);
      --  Regression (fusa#100): "risk" is a closed enum (critical|high|
      --  medium|low, section 9.2) -- "" is not a member of it, and a
      --  consumer mapping risk against that enum has no defined
      --  behaviour for an empty string (unlike an *unrecognised* value,
      --  which section 4's fail-safe convention explicitly covers).
      --  When attackFeasibility or every one of the four impact axes
      --  fails to parse (TARA004 already flags this as its own WARNING
      --  finding -- nothing is silently swept under the rug), this
      --  function used to return "" outright. It now fails safe to the
      --  most conservative (worst-case) rank for whichever axis/axes
      --  didn't resolve, so risk is always a genuine, real enum value --
      --  never underestimating risk on bad input, consistent with a
      --  safety tool's fail-safe posture.
      Feas  : constant Feasibility_Rank :=
        (if Raw_Feas = Unrecognised then High else Raw_Feas);
      Worst : Impact_Rank := Unknown;

      procedure Consider (S : String) is
         R : constant Impact_Rank := Impact_Of (S);
      begin
         if Impact_Rank'Pos (R) > Impact_Rank'Pos (Worst) then
            Worst := R;
         end if;
      end Consider;
   begin
      Consider (To_String (Impact.Safety));
      Consider (To_String (Impact.Financial));
      Consider (To_String (Impact.Operational));
      Consider (To_String (Impact.Privacy));
      if Worst = Unknown then
         Worst := Critical;
      end if;
      case Table (Worst, Feas) is
         when R_Low      => return "low";
         when R_Medium   => return "medium";
         when R_High     => return "high";
         when R_Critical => return "critical";
      end case;
   end Determine_Tara_Risk;

   function Load_Tara
     (Project_Root : String;
      Findings     : in out Finding_List) return Tara_Document
   is
      Result : Tara_Document;
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

         Result.Asset_Inventory_Method :=
           To_Unbounded_String (Fusa.Json.Get_String (Root, "assetInventoryMethod"));
         if Fusa.Json.Has_Key (Root, "assetsInProject") then
            declare
               V : constant Fusa.Json.Value_Access := Fusa.Json.Get_Member (Root, "assetsInProject");
            begin
               if V /= null and then V.Kind = Fusa.Json.Json_Number and then V.Num_Val >= 0.0 then
                  Result.Assets_In_Project       := Natural (V.Num_Val);
                  Result.Assets_In_Project_Given := True;
               end if;
            end;
         end if;

         declare
            Items : constant Fusa.Json.Value_Access :=
              Fusa.Json.Get_Array (Root, "threats");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Items, I);
                  Id     : constant String := Fusa.Json.Get_String (Item, "id");
                  Asset  : constant String := Fusa.Json.Get_String (Item, "asset");
                  Threat_Desc : constant String := Fusa.Json.Get_String (Item, "threat");
                  T      : Threat;
               begin
                  if Id'Length = 0 or else Asset'Length = 0 or else Threat_Desc'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "TARA001",
                           Severity    => Error,
                           Message     =>
                             "threat at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id/asset/threat in " &
                             Tara_File,
                           Loc         => Make_Location (Tara_File),
                           Category    => Fusa.Security,
                           Remediation =>
                             "give this threat a non-empty ""id"", ""asset"", and ""threat"""));
                  else
                     T.Id            := To_Unbounded_String (Id);
                     T.Asset         := To_Unbounded_String (Asset);
                     T.Description   := To_Unbounded_String (Threat_Desc);
                     T.Cwe           := To_Unbounded_String (Fusa.Json.Get_String (Item, "cwe"));
                     T.Attack_Vector :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "attackVector"));
                     T.Attack_Feasibility :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "attackFeasibility"));
                     T.Treatment     :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "treatment"));
                     T.Cyber_Rule_Id :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "cyberRuleId"));

                     declare
                        Impact_Obj : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Member (Item, "impact");
                     begin
                        T.Impact.Safety      :=
                          To_Unbounded_String (Fusa.Json.Get_String (Impact_Obj, "safety"));
                        T.Impact.Financial   :=
                          To_Unbounded_String (Fusa.Json.Get_String (Impact_Obj, "financial"));
                        T.Impact.Operational :=
                          To_Unbounded_String (Fusa.Json.Get_String (Impact_Obj, "operational"));
                        T.Impact.Privacy     :=
                          To_Unbounded_String (Fusa.Json.Get_String (Impact_Obj, "privacy"));
                     end;

                     declare
                        Loc_Obj : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Member (Item, "location");
                     begin
                        if Loc_Obj /= null then
                           T.Location.Present := True;
                           T.Location.File    :=
                             To_Unbounded_String (Fusa.Json.Get_String (Loc_Obj, "file"));
                           declare
                              Line_V : constant Fusa.Json.Value_Access :=
                                Fusa.Json.Get_Member (Loc_Obj, "line");
                           begin
                              if Line_V /= null and then Line_V.Kind = Fusa.Json.Json_Number
                                and then Line_V.Num_Val >= 0.0
                              then
                                 T.Location.Line := Natural (Line_V.Num_Val);
                              end if;
                           end;
                        end if;
                     end;

                     declare
                        Mits : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "mitigations");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Mits) loop
                           T.Mitigations.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (Mits, J)));
                        end loop;
                     end;

                     declare
                        function Valid_Feasibility (S : String) return Boolean is
                          (S = "high" or else S = "medium" or else S = "low"
                           or else S = "very-low");
                        function Valid_Impact (S : String) return Boolean is
                          (S = "critical" or else S = "major" or else S = "moderate"
                           or else S = "negligible");
                        --  Only flags a NON-blank-but-wrong value, not a blank one --
                        --  a blank axis is already separately caught by the
                        --  general TARA002 missing-required-field check below,
                        --  so this stays specific to "someone typed the wrong
                        --  vocabulary" (e.g. "medium" instead of "moderate").
                        function Invalid_Nonblank_Impact (S : String) return Boolean is
                          (S'Length > 0 and then not Valid_Impact (S));

                        Feas_Str : constant String := To_String (T.Attack_Feasibility);
                        Has_Invalid_Impact : constant Boolean :=
                          Invalid_Nonblank_Impact (To_String (T.Impact.Safety))
                          or else Invalid_Nonblank_Impact (To_String (T.Impact.Financial))
                          or else Invalid_Nonblank_Impact (To_String (T.Impact.Operational))
                          or else Invalid_Nonblank_Impact (To_String (T.Impact.Privacy));
                        Derived : constant String :=
                          Determine_Tara_Risk (Feas_Str, T.Impact);
                     begin
                        T.Risk := To_Unbounded_String (Derived);
                        --  section 9.2 (v1.14.1): impact.* and attackFeasibility
                        --  are two DISTINCT closed enums -- validated and
                        --  reported separately so a bad value in one doesn't
                        --  mask a bad value in the other.
                        if Feas_Str'Length > 0
                          and then not Valid_Feasibility (Feas_Str)
                        then
                           Findings.Append
                             (Make_Finding
                                (Rule_Id     => "TARA003",
                                 Severity    => Warning,
                                 Message     =>
                                   "threat """ & Id & """ has an unrecognised " &
                                   "attackFeasibility (expected high|medium|low|" &
                                   "very-low) in " & Tara_File,
                                 Loc         => Make_Location (Tara_File),
                                 Category    => Fusa.Security,
                                 Remediation =>
                                   "use one of high, medium, low, very-low for " &
                                   "attackFeasibility"));
                        end if;
                        if Has_Invalid_Impact then
                           Findings.Append
                             (Make_Finding
                                (Rule_Id     => "TARA004",
                                 Severity    => Warning,
                                 Message     =>
                                   "threat """ & Id & """ has an unrecognised impact " &
                                   "value (expected critical|major|moderate|" &
                                   "negligible on each of safety/financial/" &
                                   "operational/privacy) in " & Tara_File,
                                 Loc         => Make_Location (Tara_File),
                                 Category    => Fusa.Security,
                                 Remediation =>
                                   "use one of critical, major, moderate, negligible " &
                                   "for each SFOP impact axis"));
                        end if;
                     end;

                     if Length (T.Attack_Vector) = 0
                       or else Length (T.Impact.Safety) = 0
                       or else Length (T.Impact.Financial) = 0
                       or else Length (T.Impact.Operational) = 0
                       or else Length (T.Impact.Privacy) = 0
                       or else Length (T.Treatment) = 0
                     then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "TARA002",
                              Severity    => Warning,
                              Message     =>
                                "threat """ & Id & """ is missing one or more of " &
                                "attackVector/impact/treatment in " & Tara_File,
                              Loc         => Make_Location (Tara_File),
                              Category    => Fusa.Security,
                              Remediation =>
                                "fill in all required fields for a complete ISO 21434 " &
                                "ch.15 threat entry"));
                     end if;

                     Result.Threats.Append (T);
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

   ----------------------------------------------------------------------
   --  .fusa-<standard>-objectives.json
   ----------------------------------------------------------------------

   function Gap_Objectives_File (Standard_Id : String) return String is
     (".fusa-" & Standard_Id & "-objectives.json");

   function Gap_Objectives_Exist (Project_Root, Standard_Id : String) return Boolean is
     (Fusa.Files.Exists
        (Fusa.Files.Join (Project_Root, Gap_Objectives_File (Standard_Id))));

   function Load_Gap_Objectives
     (Project_Root, Standard_Id : String;
      Findings                  : in out Finding_List) return Gap_Objective_List
   is
      Result : Gap_Objective_List;
      Path   : constant String :=
        Fusa.Files.Join (Project_Root, Gap_Objectives_File (Standard_Id));
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
              Fusa.Json.Get_Array (Root, "objectives");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item   : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id     : constant String := Fusa.Json.Get_String (Item, "id");
                  Status : constant String := Fusa.Json.Get_String (Item, "status", "gap");
                  O      : Gap_Objective;
               begin
                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "GAP001",
                           Severity    => Error,
                           Message     =>
                             "objective at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " &
                             Gap_Objectives_File (Standard_Id),
                           Loc         => Make_Location (Gap_Objectives_File (Standard_Id)),
                           Category    => Fusa.Requirement,
                           Remediation => "give this objective a non-empty string ""id"""));
                  else
                     O.Id     := To_Unbounded_String (Id);
                     O.Title  := To_Unbounded_String (Fusa.Json.Get_String (Item, "title"));
                     O.Clause := To_Unbounded_String (Fusa.Json.Get_String (Item, "clause"));
                     if Status /= "satisfied" and then Status /= "partial"
                       and then Status /= "gap"
                     then
                        --  §9.3: "a consumer MUST map any unrecognised
                        --  status to gap (fail-safe)" -- O.Status must
                        --  actually be normalised, not just warned about,
                        --  or the gap-report summary's
                        --  satisfied+partial+gaps=total invariant breaks
                        --  for every malformed-but-loadable objectives
                        --  file (an unrecognised status matched none of
                        --  the three tally branches).
                        O.Status := To_Unbounded_String ("gap");
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "GAP002",
                              Severity    => Warning,
                              Message     =>
                                "objective """ & Id & """ has status """ & Status &
                                """, expected satisfied|partial|gap, in " &
                                Gap_Objectives_File (Standard_Id),
                              Loc         => Make_Location (Gap_Objectives_File (Standard_Id)),
                              Category    => Fusa.Requirement,
                              Remediation =>
                                "set status to one of satisfied, partial, or gap"));
                     else
                        O.Status := To_Unbounded_String (Status);
                     end if;
                     declare
                        Ev : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "evidence");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Ev) loop
                           O.Evidence.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Ev, J)));
                        end loop;
                     end;
                     declare
                        Fd : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "findings");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Fd) loop
                           O.Findings.Append (Fusa.Json.As_String (Fusa.Json.Array_Item (Fd, J)));
                        end loop;
                     end;
                     Result.Append (O);
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Gap_Objectives;

   procedure Scaffold_Gap_Objectives
     (Project_Root, Standard_Id : String; Starter : Gap_Objective_List)
   is
      W : Fusa.Json.Writer.Instance;
   begin
      if Gap_Objectives_Exist (Project_Root, Standard_Id) then
         return;
      end if;
      W.Object_Start;
      W.Key ("objectives");
      W.Array_Start;
      for O of Starter loop
         W.Object_Start;
         W.Field ("id", To_String (O.Id));
         W.Field_If_Non_Blank ("title", To_String (O.Title));
         W.Field_If_Non_Blank ("clause", To_String (O.Clause));
         W.Field ("status", To_String (O.Status));
         W.Key ("evidence");
         W.Array_Start;
         for E of O.Evidence loop
            W.Value (E);
         end loop;
         W.Array_End;
         W.Key ("findings");
         W.Array_Start;
         for F of O.Findings loop
            W.Value (F);
         end loop;
         W.Array_End;
         W.Object_End;
      end loop;
      W.Array_End;
      W.Object_End;
      Fusa.Files.Write_File
        (Fusa.Files.Join (Project_Root, Gap_Objectives_File (Standard_Id)),
         Fusa.Json.Writer.To_String (W) & ASCII.LF);
   end Scaffold_Gap_Objectives;

   ----------------------------------------------------------------------
   --  .fusa-fmea.json
   ----------------------------------------------------------------------

   function Fmea_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Fmea_File)));

   --  Returns 0 (invalid/absent) unless Key holds a JSON number that is a
   --  whole number in 1 .. 10.
   function Get_Rating (Item : Fusa.Json.Value_Access; Key : String) return Natural is
      M : constant Fusa.Json.Value_Access := Fusa.Json.Get_Member (Item, Key);
   begin
      if M = null or else M.Kind /= Fusa.Json.Json_Number then
         return 0;
      end if;
      if M.Num_Val < 1.0 or else M.Num_Val > 10.0
        or else M.Num_Val /= Long_Float'Truncation (M.Num_Val)
      then
         return 0;
      end if;
      return Natural (M.Num_Val);
   end Get_Rating;

   function Load_Fmea
     (Project_Root : String; Findings : in out Finding_List) return Fmea_Document
   is
      Result       : Fmea_Document;
      Path         : constant String := Fusa.Files.Join (Project_Root, Fmea_File);
      Any_Rated    : Boolean := False;
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

         if Fusa.Json.Has_Key (Root, "componentsInProject") then
            declare
               V : constant Fusa.Json.Value_Access :=
                 Fusa.Json.Get_Member (Root, "componentsInProject");
            begin
               if V /= null and then V.Kind = Fusa.Json.Json_Number and then V.Num_Val >= 0.0 then
                  Result.Components_In_Project       := Natural (V.Num_Val);
                  Result.Components_In_Project_Given := True;
               end if;
            end;
         end if;

         declare
            Items : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Root, "entries");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  E    : Fmea_Entry;
               begin
                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "FMEA001",
                           Severity    => Error,
                           Message     =>
                             "FMEA entry at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Fmea_File,
                           Loc         => Make_Location (Fmea_File),
                           Category    => Fusa.Safety,
                           Remediation => "give this entry a non-empty string ""id"""));
                  else
                     E.Id           := To_Unbounded_String (Id);
                     E.Item         := To_Unbounded_String (Fusa.Json.Get_String (Item, "item"));
                     E.File         := To_Unbounded_String (Fusa.Json.Get_String (Item, "file"));
                     E.Failure_Mode :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "failureMode"));
                     E.Effect       := To_Unbounded_String (Fusa.Json.Get_String (Item, "effect"));
                     E.Cause        := To_Unbounded_String (Fusa.Json.Get_String (Item, "cause"));
                     E.Action_Priority :=
                       To_Unbounded_String (Fusa.Json.Get_String (Item, "actionPriority"));
                     declare
                        Mits : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "mitigations");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Mits) loop
                           E.Mitigations.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (Mits, J)));
                        end loop;
                     end;
                     declare
                        Reqs : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "requirementIds");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (Reqs) loop
                           E.Requirement_Ids.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (Reqs, J)));
                        end loop;
                     end;
                     E.Severity     := Get_Rating (Item, "severity");
                     E.Occurrence   := Get_Rating (Item, "occurrence");
                     E.Detection    := Get_Rating (Item, "detection");
                     if E.Occurrence > 0 or else E.Detection > 0 then
                        Any_Rated := True;
                     end if;

                     --  Regression (fusa#100): section 9.2 marks only
                     --  "severity" MUST -- "occurrence"/"detection" are
                     --  each MAY. This used to also fire FMEA002 whenever
                     --  either was absent (defaulted to 0), which meant
                     --  every spec-conformant entry that supplies only
                     --  severity got a spurious validation warning.
                     if E.Severity = 0 then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "FMEA002",
                              Severity    => Warning,
                              Message     =>
                                "FMEA entry """ & Id & """ has a missing/invalid severity " &
                                "rating (must be a whole number 1..10) in " & Fmea_File,
                              Loc         => Make_Location (Fmea_File),
                              Category    => Fusa.Safety,
                              Remediation => "set severity to a whole number 1..10"));
                     end if;

                     if Length (E.Item) = 0 or else Length (E.File) = 0
                       or else Length (E.Failure_Mode) = 0 or else Length (E.Effect) = 0
                     then
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "FMEA004",
                              Severity    => Warning,
                              Message     =>
                                "FMEA entry """ & Id & """ is missing one or more of " &
                                "item/file/failureMode/effect in " & Fmea_File,
                              Loc         => Make_Location (Fmea_File),
                              Category    => Fusa.Safety,
                              Remediation =>
                                "fill in all required fields for a complete FMEA entry"));
                     end if;

                     declare
                        Explicit_Rpn : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Member (Item, "rpn");
                        Computed     : constant Natural :=
                          E.Severity * E.Occurrence * E.Detection;
                     begin
                        if Explicit_Rpn /= null
                          and then Explicit_Rpn.Kind = Fusa.Json.Json_Number
                        then
                           E.Rpn := Natural (Explicit_Rpn.Num_Val);
                           if E.Severity > 0 and then E.Occurrence > 0 and then E.Detection > 0
                             and then E.Rpn /= Computed
                           then
                              Findings.Append
                                (Make_Finding
                                   (Rule_Id     => "FMEA003",
                                    Severity    => Warning,
                                    Message     =>
                                      "FMEA entry """ & Id & """'s explicit rpn (" &
                                      Trim_Img (E.Rpn) &
                                      ") does not match severity*occurrence*detection (" &
                                      Trim_Img (Computed) & ") in " & Fmea_File,
                                    Loc         => Make_Location (Fmea_File),
                                    Category    => Fusa.Safety,
                                    Remediation =>
                                      "recompute rpn as severity*occurrence*detection, or " &
                                      "correct whichever rating is wrong"));
                           end if;
                        else
                           E.Rpn := Computed;
                        end if;
                     end;

                     Result.Entries.Append (E);
                  end if;
               end;
            end loop;
         end;
      end;
      --  section 9.2: ratingScale is MUST whenever occurrence/detection
      --  are emitted -- this tool has exactly one rating scale in use.
      if Any_Rated then
         Result.Rating_Scale := To_Unbounded_String ("aiag-vda-2019");
      end if;
      return Result;
   end Load_Fmea;

   procedure Scaffold_Fmea (Project_Root : String) is
   begin
      if not Fmea_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Fmea_File), "{" & ASCII.LF &
              "  ""entries"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Fmea;

   ----------------------------------------------------------------------
   --  .fusa-safety-case.json
   ----------------------------------------------------------------------

   function Safety_Case_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Safety_Case_File)));

   function Load_Safety_Case
     (Project_Root : String;
      Findings     : in out Finding_List;
      Root_Goal    : out Unbounded_String) return Gsn_Node_List
   is
      Result : Gsn_Node_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Safety_Case_File);
   begin
      Root_Goal := Null_Unbounded_String;
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

         Root_Goal := To_Unbounded_String (Fusa.Json.Get_String (Root, "rootGoal"));

         declare
            Items : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Root, "nodes");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Items) loop
               declare
                  Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
                  Id   : constant String := Fusa.Json.Get_String (Item, "id");
                  Kind : constant String := Fusa.Json.Get_String (Item, "type");
                  N    : Gsn_Node;
               begin
                  if Id'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "GSN001",
                           Severity    => Error,
                           Message     =>
                             "GSN node at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string id in " & Safety_Case_File,
                           Loc         => Make_Location (Safety_Case_File),
                           Category    => Fusa.Safety,
                           Remediation => "give this node a non-empty string ""id"""));
                  else
                     N.Id       := To_Unbounded_String (Id);
                     N.Text     := To_Unbounded_String
                       (Fusa.Json.Get_String (Item, "text"));
                     N.Evidence := To_Unbounded_String
                       (Fusa.Json.Get_String (Item, "evidence"));
                     if Kind = "goal" or else Kind = "strategy" or else Kind = "context"
                       or else Kind = "solution" or else Kind = "assumption"
                       or else Kind = "justification"
                     then
                        N.Kind := To_Unbounded_String (Kind);
                     else
                        Findings.Append
                          (Make_Finding
                             (Rule_Id     => "GSN002",
                              Severity    => Warning,
                              Message     =>
                                "GSN node """ & Id & """ has an unrecognised or missing " &
                                """type"" (expected goal/strategy/context/solution/" &
                                "assumption/justification) in " & Safety_Case_File,
                              Loc         => Make_Location (Safety_Case_File),
                              Category    => Fusa.Safety,
                              Remediation =>
                                "set type to one of goal, strategy, context, solution, " &
                                "assumption, justification"));
                     end if;
                     declare
                        SB : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "supportedBy");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (SB) loop
                           N.Supported_By.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (SB, J)));
                        end loop;
                     end;
                     declare
                        IC : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Item, "inContextOf");
                     begin
                        for J in 1 .. Fusa.Json.Array_Length (IC) loop
                           N.In_Context_Of.Append
                             (Fusa.Json.As_String (Fusa.Json.Array_Item (IC, J)));
                        end loop;
                     end;
                     Result.Append (N);
                  end if;
               end;
            end loop;
         end;
      end;

      --  Second pass: every supportedBy/inContextOf reference must resolve
      --  to a real node id -- a dangling reference is a genuinely broken
      --  argument, not just an incomplete field.
      declare
         procedure Check_Refs (N : Gsn_Node; Refs : String_List) is
         begin
            for Ref of Refs loop
               declare
                  Resolved : Boolean := False;
               begin
                  for Other of Result loop
                     if To_String (Other.Id) = Ref then
                        Resolved := True;
                        exit;
                     end if;
                  end loop;
                  if not Resolved then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "GSN003",
                           Severity    => Error,
                           Message     =>
                             "GSN node """ & To_String (N.Id) & """ references """ & Ref &
                             """, which does not resolve to any node id in " &
                             Safety_Case_File,
                           Loc         => Make_Location (Safety_Case_File),
                           Category    => Fusa.Safety,
                           Remediation =>
                             "fix the dangling reference, or add the missing node"));
                  end if;
               end;
            end loop;
         end Check_Refs;
      begin
         for N of Result loop
            Check_Refs (N, N.Supported_By);
            Check_Refs (N, N.In_Context_Of);
         end loop;
      end;

      --  Third pass: a solution node's evidence is a claim about the
      --  project's actual artifacts -- a claim naming a file the project
      --  doesn't contain is worse than an honestly missing solution (§9.2).
      for N of Result loop
         if To_String (N.Kind) = "solution"
           and then Length (N.Evidence) > 0
         then
            if not Fusa.Files.Exists
              (Fusa.Files.Join (Project_Root, To_String (N.Evidence)))
            then
               Findings.Append
                 (Make_Finding
                    (Rule_Id     => "GSN004",
                     Severity    => Warning,
                     Message     =>
                       "solution node """ & To_String (N.Id) &
                       """ claims evidence """ & To_String (N.Evidence) &
                       """, which does not exist in the project",
                     Loc         => Make_Location (Safety_Case_File),
                     Category    => Fusa.Safety,
                     Remediation =>
                       "point evidence at a real artifact this tool " &
                       "produced, or remove the claim"));
            end if;
         end if;
      end loop;

      return Result;
   end Load_Safety_Case;

   function Safety_Case_Completeness
     (Nodes : Gsn_Node_List) return Gsn_Completeness
   is
      Result : Gsn_Completeness;

      function Find (Id : String) return Gsn_Node is
         Empty : Gsn_Node;
      begin
         for N of Nodes loop
            if To_String (N.Id) = Id then
               return N;
            end if;
         end loop;
         return Empty;
      end Find;

      function Reaches_Evidence
        (Id : String; Visited : String_List) return Boolean
      is
      begin
         for V of Visited loop
            if V = Id then
               return False;
            end if;
         end loop;
         declare
            N        : constant Gsn_Node := Find (Id);
            Visited2 : String_List := Visited;
         begin
            if Length (N.Id) = 0 then
               return False;
            end if;
            if To_String (N.Kind) = "solution"
              and then Length (N.Evidence) > 0
            then
               return True;
            end if;
            Visited2.Append (Id);
            for Child of N.Supported_By loop
               if Reaches_Evidence (Child, Visited2) then
                  return True;
               end if;
            end loop;
            return False;
         end;
      end Reaches_Evidence;

      Empty_Visited : String_List;
   begin
      for N of Nodes loop
         if To_String (N.Kind) = "goal" then
            Result.Total_Goals := Result.Total_Goals + 1;
            if N.Supported_By.Is_Empty then
               Result.Undeveloped := Result.Undeveloped + 1;
            elsif Reaches_Evidence (To_String (N.Id), Empty_Visited) then
               Result.Goals_With_Evidence := Result.Goals_With_Evidence + 1;
            end if;
         end if;
      end loop;
      return Result;
   end Safety_Case_Completeness;

   procedure Scaffold_Safety_Case (Project_Root : String) is
   begin
      if not Safety_Case_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Safety_Case_File), "{" & ASCII.LF &
              "  ""rootGoal"": ""G1""," & ASCII.LF &
              "  ""nodes"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Safety_Case;

   ----------------------------------------------------------------------
   --  .fusa-verify.json
   ----------------------------------------------------------------------

   function Verify_Exists (Project_Root : String) return Boolean is
     (Fusa.Files.Exists (Fusa.Files.Join (Project_Root, Verify_File)));

   function Load_Verify
     (Project_Root : String;
      Findings     : in out Finding_List;
      Passed, Failed : out Natural) return Verify_Suite_List
   is
      Result : Verify_Suite_List;
      Path   : constant String := Fusa.Files.Join (Project_Root, Verify_File);
   begin
      Passed := 0;
      Failed := 0;
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
            Suite_Items : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Root, "suites");
         begin
            for I in 1 .. Fusa.Json.Array_Length (Suite_Items) loop
               declare
                  Suite_Item : constant Fusa.Json.Value_Access :=
                    Fusa.Json.Array_Item (Suite_Items, I);
                  Suite_Name : constant String := Fusa.Json.Get_String (Suite_Item, "name");
               begin
                  if Suite_Name'Length = 0 then
                     Findings.Append
                       (Make_Finding
                          (Rule_Id     => "VERIFY001",
                           Severity    => Error,
                           Message     =>
                             "suite at index" & Integer'Image (I) &
                             " has a missing, empty, or non-string name in " & Verify_File,
                           Loc         => Make_Location (Verify_File),
                           Category    => Fusa.Requirement,
                           Remediation => "give this suite a non-empty string ""name"""));
                  else
                     declare
                        Suite      : Verify_Suite;
                        Test_Items : constant Fusa.Json.Value_Access :=
                          Fusa.Json.Get_Array (Suite_Item, "tests");
                     begin
                        Suite.Name := To_Unbounded_String (Suite_Name);
                        for J in 1 .. Fusa.Json.Array_Length (Test_Items) loop
                           declare
                              Test_Item : constant Fusa.Json.Value_Access :=
                                Fusa.Json.Array_Item (Test_Items, J);
                              Test_Name : constant String :=
                                Fusa.Json.Get_String (Test_Item, "name");
                              Test_Res  : constant String :=
                                Fusa.Json.Get_String (Test_Item, "result");
                           begin
                              if Test_Name'Length = 0 then
                                 Findings.Append
                                   (Make_Finding
                                      (Rule_Id     => "VERIFY002",
                                       Severity    => Error,
                                       Message     =>
                                         "test at index" & Integer'Image (J) & " in suite """ &
                                         Suite_Name & """ has a missing, empty, or non-string " &
                                         "name in " & Verify_File,
                                       Loc         => Make_Location (Verify_File),
                                       Category    => Fusa.Requirement,
                                       Remediation =>
                                         "give this test a non-empty string ""name"""));
                              else
                                 declare
                                    T : Verify_Test;
                                 begin
                                    T.Name := To_Unbounded_String (Test_Name);
                                    if Test_Res = "PASS" or else Test_Res = "FAIL"
                                      or else Test_Res = "SKIP" or else Test_Res = "ERROR"
                                    then
                                       T.Result := To_Unbounded_String (Test_Res);
                                       if Test_Res = "PASS" then
                                          Passed := Passed + 1;
                                       elsif Test_Res = "FAIL" then
                                          Failed := Failed + 1;
                                       end if;
                                    else
                                       Findings.Append
                                         (Make_Finding
                                            (Rule_Id     => "VERIFY003",
                                             Severity    => Warning,
                                             Message     =>
                                               "test """ & Test_Name & """ in suite """ &
                                               Suite_Name & """ has a missing or unrecognised " &
                                               """result"" (expected PASS/FAIL/SKIP/ERROR) in " &
                                               Verify_File,
                                             Loc         => Make_Location (Verify_File),
                                             Category    => Fusa.Requirement,
                                             Remediation =>
                                               "set result to one of PASS, FAIL, SKIP, ERROR"));
                                    end if;
                                    Suite.Tests.Append (T);
                                 end;
                              end if;
                           end;
                        end loop;
                        Result.Append (Suite);
                     end;
                  end if;
               end;
            end loop;
         end;
      end;
      return Result;
   end Load_Verify;

   procedure Scaffold_Verify (Project_Root : String) is
   begin
      if not Verify_Exists (Project_Root) then
         Fusa.Files.Write_File
           (Fusa.Files.Join (Project_Root, Verify_File), "{" & ASCII.LF &
              "  ""suites"": []" & ASCII.LF & "}" & ASCII.LF);
      end if;
   end Scaffold_Verify;

end Fusa.Config;
