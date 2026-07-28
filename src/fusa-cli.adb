with Ada.Text_IO;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with Interfaces.C; use Interfaces.C;

with Fusa.Config;
with Fusa.Files;
with Fusa.Source_Scan;
with Fusa.Engine;
with Fusa.Annotations; use Fusa.Annotations;
with Fusa.Func_Scan;
with Fusa.Report;
with Fusa.Json.Writer;
with Fusa.Sha256;
with Fusa.Zip;

package body Fusa.Cli is

   function Trim_Img (N : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (N), Ada.Strings.Left));

   ----------------------------------------------------------------------
   --  Flag parsing
   ----------------------------------------------------------------------

   function Flag_Value
     (Args : String_List; Name : String; Default : String := "") return String
   is
   begin
      for I in 1 .. Natural (Args.Length) loop
         declare
            A : constant String := Args.Element (I);
         begin
            if A = Name and then I < Natural (Args.Length) then
               return Args.Element (I + 1);
            elsif A'Length >= Name'Length + 1
              and then A (A'First .. A'First + Name'Length - 1) = Name
              and then A (A'First + Name'Length) = '='
            then
               --  A'Length = Name'Length + 1 means "--flag=" with nothing
               --  after the '=' -- the slice below is then a legal null
               --  range, correctly yielding "".
               return A (A'First + Name'Length + 1 .. A'Last);
            end if;
         end;
      end loop;
      return Default;
   end Flag_Value;

   function Has_Flag (Args : String_List; Name : String) return Boolean is
   begin
      for A of Args loop
         if A = Name or else A = Name & "=true" then
            return True;
         end if;
      end loop;
      return False;
   end Has_Flag;

   function Dir_Of (Args : String_List) return String is
     (Flag_Value (Args, "--dir", "."));

   --  fusa:req REQ-021
   --  §3.2 SHOULD: projectRoot is reported resolved to an absolute path,
   --  even though --dir itself keeps accepting (and is used elsewhere as)
   --  a relative path for file I/O -- only the reported value changes.
   function Absolute_Path (Dir : String) return String is
     (Ada.Directories.Full_Name (Dir));

   function Is_TTY return Boolean is
      function C_Isatty (FD : Interfaces.C.int) return Interfaces.C.int;
      pragma Import (C, C_Isatty, "isatty");
   begin
      return C_Isatty (0) /= 0;
   end Is_TTY;

   procedure Emit (Args : String_List; Content : String) is
      Out_File : constant String := Flag_Value (Args, "--output", "");
   begin
      if Out_File'Length > 0 then
         Fusa.Files.Write_File (Out_File, Content & ASCII.LF);
      else
         Ada.Text_IO.Put_Line (Content);
      end if;
   end Emit;

   function Emit_Runtime_Error
     (Args : String_List; Kind, Code, Message : String) return Integer
   is
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format = "json" then
         declare
            W : Fusa.Json.Writer.Instance;
         begin
            W.Object_Start;
            Fusa.Report.Write_Header (W, Kind);
            W.Key ("error");
            W.Object_Start;
            W.Field ("code", Code);
            W.Field ("message", Message);
            W.Object_End;
            W.Object_End;
            Emit (Args, Fusa.Json.Writer.To_String (W));
         end;
      else
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "ada-FuSa: " & Message);
         declare
            Out_File : constant String := Flag_Value (Args, "--output", "");
         begin
            if Out_File'Length > 0 then
               Fusa.Files.Write_File (Out_File, "ada-FuSa: " & Message & ASCII.LF);
            end if;
         end;
      end if;
      return Exit_Runtime;
   end Emit_Runtime_Error;

   ----------------------------------------------------------------------
   --  version
   ----------------------------------------------------------------------

   --  fusa:req REQ-007
   function Cmd_Version (Args : String_List) return Integer is
   begin
      if Flag_Value (Args, "--format", "text") = "json" then
         declare
            W : Fusa.Json.Writer.Instance;
         begin
            W.Object_Start;
            W.Field ("tool", Fusa.Tool_Name);
            W.Field ("version", Fusa.Version);
            W.Field ("specVersion", Fusa.Spec_Version);
            W.Object_End;
            Ada.Text_IO.Put_Line (Fusa.Json.Writer.To_String (W));
         end;
      else
         Ada.Text_IO.Put_Line (Fusa.Tool_Name & " " & Fusa.Version);
      end if;
      return Exit_Ok;
   end Cmd_Version;

   ----------------------------------------------------------------------
   --  capabilities
   ----------------------------------------------------------------------

   --  fusa:req REQ-008
   function Cmd_Capabilities (Args : String_List) return Integer is
      W : Fusa.Json.Writer.Instance;
   begin
      W.Object_Start;
      Fusa.Report.Write_Header (W, "capabilities");
      W.Field ("specVersion", Fusa.Spec_Version);

      W.Key ("commands");
      W.Array_Start;
      W.Value ("version");
      W.Value ("capabilities");
      W.Value ("init");
      W.Value ("check");
      W.Value ("trace");
      W.Value ("qualify");
      W.Value ("release");
      W.Value ("audit-pack");
      W.Value ("report");
      W.Array_End;

      W.Key ("formats");
      W.Object_Start;
      W.Key ("version");      W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("capabilities"); W.Array_Start; W.Value ("json"); W.Array_End;
      W.Key ("init");         W.Array_Start; W.Value ("text"); W.Array_End;
      W.Key ("check");        W.Array_Start; W.Value ("text"); W.Value ("json"); W.Value ("sarif"); W.Value ("html"); W.Array_End;
      W.Key ("trace");        W.Array_Start; W.Value ("text"); W.Value ("json"); W.Value ("html"); W.Value ("md"); W.Array_End;
      W.Key ("qualify");      W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("release");      W.Array_Start; W.Value ("json"); W.Array_End;
      W.Key ("audit-pack");   W.Array_Start; W.Value ("json"); W.Array_End;
      W.Key ("report");       W.Array_Start; W.Value ("text"); W.Value ("json"); W.Value ("sarif"); W.Value ("html"); W.Value ("md"); W.Array_End;
      W.Object_End;

      W.Key ("standards");
      W.Array_Start;
      W.Array_End;

      W.Object_End;
      Emit (Args, Fusa.Json.Writer.To_String (W));
      return Exit_Ok;
   end Cmd_Capabilities;

   ----------------------------------------------------------------------
   --  init
   ----------------------------------------------------------------------

   --  fusa:req REQ-009
   function Cmd_Init (Args : String_List) return Integer is
      Dir   : constant String := Dir_Of (Args);
      Force : constant Boolean := Has_Flag (Args, "--force");
      Name     : Unbounded_String := To_Unbounded_String (Flag_Value (Args, "--name", ""));
      Standard : Unbounded_String := To_Unbounded_String (Flag_Value (Args, "--standard", ""));
      Asil     : constant String := Flag_Value (Args, "--asil", "");
      Sil      : constant String := Flag_Value (Args, "--sil", "");
      Dal      : constant String := Flag_Value (Args, "--dal", "");
      Pver     : constant String := Flag_Value (Args, "--project-version", "");
   begin
      --  fusa:req REQ-075
      --  section 1.2 MAY: an explicit one-shot rename of legacy config/
      --  requirements files to their canonical names -- distinct from the
      --  automatic legacy-fallback-with-warning Load/Load_Requirements
      --  already do transparently on every command.
      if Has_Flag (Args, "--migrate") then
         declare
            Config_Path : constant String := Fusa.Files.Join (Dir, Fusa.Config.Config_File);
            Reqs_Path   : constant String := Fusa.Files.Join (Dir, Fusa.Config.Reqs_File);
            Legacy_Cfg  : constant String :=
              Fusa.Files.Join (Dir, Fusa.Config.Legacy_Config_File);
            Legacy_Reqs : constant String :=
              Fusa.Files.Join (Dir, Fusa.Config.Legacy_Reqs_File);
            Found_Legacy : Boolean := False;
         begin
            if Fusa.Files.Exists (Legacy_Cfg) then
               Found_Legacy := True;
               if Force or else not Fusa.Files.Exists (Config_Path) then
                  declare
                     Cfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Dir);
                  begin
                     Fusa.Config.Save (Dir, Cfg);
                  end;
                  Ada.Directories.Delete_File (Legacy_Cfg);
                  Ada.Text_IO.Put_Line ("migrated " & Legacy_Cfg & " -> " & Config_Path);
               else
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: " & Config_Path & " already exists, leaving " &
                     Legacy_Cfg & " unchanged (use --force to overwrite)");
               end if;
            end if;
            if Fusa.Files.Exists (Legacy_Reqs) then
               Found_Legacy := True;
               if Force or else not Fusa.Files.Exists (Reqs_Path) then
                  declare
                     Dummy_Findings : Finding_List;
                     Reqs : constant Fusa.Config.Requirement_List :=
                       Fusa.Config.Load_Requirements (Dir, Dummy_Findings);
                  begin
                     Fusa.Config.Save_Requirements (Dir, Reqs);
                  end;
                  Ada.Directories.Delete_File (Legacy_Reqs);
                  Ada.Text_IO.Put_Line ("migrated " & Legacy_Reqs & " -> " & Reqs_Path);
               else
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: " & Reqs_Path & " already exists, leaving " &
                     Legacy_Reqs & " unchanged (use --force to overwrite)");
               end if;
            end if;
            if not Found_Legacy then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "ada-FuSa: init --migrate: no legacy " & Fusa.Config.Legacy_Config_File &
                  "/" & Fusa.Config.Legacy_Reqs_File & " found in " & Dir);
            end if;
         end;
         return Exit_Ok;
      end if;

      if Length (Name) = 0 then
         declare
            I : Positive := 1;
         begin
            while I <= Natural (Args.Length) loop
               declare
                  A : constant String := Args.Element (I);
               begin
                  if A = "--dir" or else A = "--name" or else A = "--standard"
                    or else A = "--asil" or else A = "--sil" or else A = "--dal"
                    or else A = "--project-version"
                  then
                     I := I + 2; --  skip the flag and its value
                  elsif A = "--force" then
                     I := I + 1; --  boolean flag, no value to skip
                  elsif A'Length > 0 and then A (A'First) /= '-' then
                     Name := To_Unbounded_String (A);
                     exit;
                  else
                     I := I + 1; --  unrecognised flag: skip it alone
                  end if;
               end;
            end loop;
         end;
      end if;

      if Length (Name) = 0 then
         if Is_TTY then
            Ada.Text_IO.Put ("Project name: ");
            Name := To_Unbounded_String (Ada.Text_IO.Get_Line);
         end if;
         if Length (Name) = 0 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: init requires --name (or a positional <name>) " &
               "when not run interactively");
            return Exit_Usage;
         end if;
      end if;

      if Length (Standard) = 0 then
         if Is_TTY then
            Ada.Text_IO.Put ("Standard [generic]: ");
            declare
               S : constant String := Ada.Text_IO.Get_Line;
            begin
               Standard := To_Unbounded_String (if S'Length = 0 then "generic" else S);
            end;
         else
            Standard := To_Unbounded_String ("generic");
         end if;
      end if;

      declare
         Config_Path : constant String := Fusa.Files.Join (Dir, Fusa.Config.Config_File);
         Reqs_Path   : constant String := Fusa.Files.Join (Dir, Fusa.Config.Reqs_File);
      begin
         if Force or else not Fusa.Files.Exists (Config_Path) then
            declare
               Cfg : Fusa.Config.Project_Config :=
                 Fusa.Config.Default_Config (To_String (Name));
            begin
               Cfg.Standard := Standard;
               Cfg.Asil := To_Unbounded_String (Asil);
               Cfg.Sil  := To_Unbounded_String (Sil);
               Cfg.Dal  := To_Unbounded_String (Dal);
               if Pver'Length > 0 then
                  Cfg.Version := To_Unbounded_String (Pver);
               end if;
               Fusa.Config.Save (Dir, Cfg);
            end;
            Ada.Text_IO.Put_Line ("created " & Config_Path);
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: " & Config_Path &
               " already exists, leaving unchanged (use --force to overwrite)");
         end if;

         if Force or else not Fusa.Files.Exists (Reqs_Path) then
            Fusa.Config.Save_Requirements (Dir, Fusa.Config.Requirement_Vectors.Empty_Vector);
            Ada.Text_IO.Put_Line ("created " & Reqs_Path);
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: " & Reqs_Path &
               " already exists, leaving unchanged (use --force to overwrite)");
         end if;
      end;
      return Exit_Ok;
   end Cmd_Init;

   ----------------------------------------------------------------------
   --  check
   ----------------------------------------------------------------------

   --  fusa:req REQ-010
   function Cmd_Check (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Strict : constant Boolean := Has_Flag (Args, "--strict");
   begin
      if Format /= "text" and then Format /= "json" and then Format /= "sarif"
        and then Format /= "html"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: check: unsupported --format '" & Format &
            "' (supported: text, json, sarif, html)");
         return Exit_Usage;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "check-report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "check-report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Effective_Strict : constant Boolean := Strict or else Cfg.Strict;
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Findings : Finding_List := Fusa.Engine.Run_All (Dir, Files);
            Dup_Findings : Finding_List;
            Reqs : constant Fusa.Config.Requirement_List :=
              Fusa.Config.Load_Requirements (Dir, Dup_Findings);
         begin
            for F of Dup_Findings loop
               Findings.Append (F);
            end loop;

            --  fusa:req REQ-072
            if Fusa.Config.Dispositions_Exist (Dir) then
               declare
                  Disps          : constant Fusa.Config.Disposition_List :=
                    Fusa.Config.Load_Dispositions (Dir);
                  Orphan_Findings : Finding_List;
               begin
                  Fusa.Config.Apply_Dispositions (Findings, Disps, Orphan_Findings);
                  for F of Orphan_Findings loop
                     Findings.Append (F);
                  end loop;
               end;
            end if;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "check-report");
                  Fusa.Report.Write_Report_Extension
                    (W, Absolute_Path (Dir), To_String (Cfg.Name),
                     To_String (Cfg.Standard), To_String (Cfg.Asil),
                     To_String (Cfg.Sil), To_String (Cfg.Dal));
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings);
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            elsif Format = "sarif" then
               Emit (Args, Fusa.Report.Render_Sarif (Findings));
            elsif Format = "html" then
               Emit (Args, Fusa.Report.Render_Html (Findings));
            else
               Emit (Args, Fusa.Report.Render_Text (Findings));
            end if;

            if Fusa.Report.Has_Gate_Failure (Findings, Effective_Strict) then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Check;

   ----------------------------------------------------------------------
   --  trace
   ----------------------------------------------------------------------

   --  fusa:req REQ-011
   function Cmd_Trace (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Gaps   : constant Boolean := Has_Flag (Args, "--gaps");
      Strict : constant Boolean := Has_Flag (Args, "--strict");
      Req_Cov_Str    : constant String := Flag_Value (Args, "--req-coverage", "");
      Sec_Tested_Str : constant String := Flag_Value (Args, "--sec-tested", "");
      Func_Cov_Str   : constant String := Flag_Value (Args, "--func-coverage", "");
   begin
      if Format /= "text" and then Format /= "json"
        and then Format /= "html" and then Format /= "md"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: trace: unsupported --format '" & Format &
            "' (supported: text, json, html, md)");
         return Exit_Usage;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "trace-matrix", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "trace-matrix", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Dup_Findings : Finding_List;
            Reqs  : constant Fusa.Config.Requirement_List :=
              Fusa.Config.Load_Requirements (Dir, Dup_Findings);
            Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Ann_Findings : Finding_List;
            Tags  : constant Fusa.Annotations.Tag_List :=
              Fusa.Annotations.Scan (Dir, Files, Ann_Findings);
            Total : constant Natural := Natural (Reqs.Length);

            --  fusa:req REQ-024
            Funcs : constant Fusa.Func_Scan.Func_List :=
              Fusa.Func_Scan.Scan_Public_Functions (Dir, Files);
            Func_Total, Func_Tagged_Count : Natural := 0;

            type Req_Status is record
               Traced, Tested, Sec_Tested : Boolean := False;
            end record;
            Statuses : array (1 .. Integer'Max (Total, 1)) of Req_Status;

            function Index_Of (Id : String) return Natural is
            begin
               for I in 1 .. Total loop
                  if To_String (Reqs.Element (I).Id) = Id then
                     return I;
                  end if;
               end loop;
               return 0;
            end Index_Of;

            Traced_Count, Tested_Count, Sec_Tested_Count : Natural := 0;
         begin
            for F of Dup_Findings loop
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "ada-FuSa: warning: " & To_String (F.Message));
            end loop;
            for F of Ann_Findings loop
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "ada-FuSa: warning: " & To_String (F.Message));
            end loop;

            for T of Tags loop
               declare
                  Idx : constant Natural := Index_Of (To_String (T.Requirement_Id));
               begin
                  if Idx > 0 then
                     Statuses (Idx).Traced := True;
                     if T.Kind = Fusa.Annotations.Test
                       or else T.Kind = Fusa.Annotations.Sec_Test
                     then
                        Statuses (Idx).Tested := True;
                     end if;
                     if T.Kind = Fusa.Annotations.Sec_Test then
                        Statuses (Idx).Sec_Tested := True;
                     end if;
                  end if;
               end;
            end loop;
            for I in 1 .. Total loop
               if Statuses (I).Traced then
                  Traced_Count := Traced_Count + 1;
               end if;
               if Statuses (I).Tested then
                  Tested_Count := Tested_Count + 1;
               end if;
               if Statuses (I).Sec_Tested then
                  Sec_Tested_Count := Sec_Tested_Count + 1;
               end if;
            end loop;

            Func_Total := Natural (Funcs.Length);
            for Fn of Funcs loop
               if Fn.Has_Tag then
                  Func_Tagged_Count := Func_Tagged_Count + 1;
               end if;
            end loop;

            declare
               Req_Cov_Pct    : constant Natural :=
                 (if Total = 0 then 100 else Traced_Count * 100 / Total);
               Sec_Tested_Pct : constant Natural :=
                 (if Total = 0 then 100 else Sec_Tested_Count * 100 / Total);
               Func_Cov_Pct   : constant Natural :=
                 (if Func_Total = 0 then 100
                  else Func_Tagged_Count * 100 / Func_Total);
               Req_Threshold  : Natural := 0;
               Sec_Threshold  : Natural := 0;
               Func_Threshold : Natural := 0;
               Gate_Fail      : Boolean := False;
            begin
               --  Each threshold is parsed (and, under --strict, defaulted
               --  to 100) independently of the other -- --strict must not
               --  silently drop the implicit 100% default for one axis
               --  just because the other axis got an explicit value.
               if Req_Cov_Str'Length > 0 then
                  begin
                     Req_Threshold := Natural'Value (Req_Cov_Str);
                  exception
                     when Constraint_Error =>
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: trace: --req-coverage must be a " &
                           "non-negative integer");
                        return Exit_Usage;
                  end;
               elsif Strict then
                  Req_Threshold := 100;
               end if;

               if Sec_Tested_Str'Length > 0 then
                  begin
                     Sec_Threshold := Natural'Value (Sec_Tested_Str);
                  exception
                     when Constraint_Error =>
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: trace: --sec-tested must be a " &
                           "non-negative integer");
                        return Exit_Usage;
                  end;
               elsif Strict then
                  Sec_Threshold := 100;
               end if;

               --  §1.4.1: --func-coverage is SHOULD/phased and NOT implied
               --  by --strict (unlike --req-coverage/--sec-tested) -- only
               --  an explicit --func-coverage N applies this gate.
               if Func_Cov_Str'Length > 0 then
                  begin
                     Func_Threshold := Natural'Value (Func_Cov_Str);
                  exception
                     when Constraint_Error =>
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: trace: --func-coverage must be a " &
                           "non-negative integer");
                        return Exit_Usage;
                  end;
               end if;

               if Req_Threshold > 0 and then Req_Cov_Pct < Req_Threshold then
                  Gate_Fail := True;
               end if;
               if Sec_Threshold > 0 and then Sec_Tested_Pct < Sec_Threshold then
                  Gate_Fail := True;
               end if;
               if Func_Threshold > 0 and then Func_Cov_Pct < Func_Threshold then
                  Gate_Fail := True;
               end if;

               if Format = "json" then
                  declare
                     W : Fusa.Json.Writer.Instance;
                  begin
                     W.Object_Start;
                     Fusa.Report.Write_Header (W, "trace-matrix");

                     W.Key ("requirements");
                     W.Array_Start;
                     for I in 1 .. Total loop
                        if not Gaps or else not Statuses (I).Tested then
                           declare
                              R : constant Fusa.Config.Requirement := Reqs.Element (I);
                           begin
                              W.Object_Start;
                              W.Field ("id", To_String (R.Id));
                              W.Field_If_Non_Blank ("title", To_String (R.Title));
                              W.Field_If_Non_Blank ("text", To_String (R.Text));
                              W.Field_If_Non_Blank ("standard", To_String (R.Standard));
                              W.Field_If_Non_Blank ("level", To_String (R.Level));
                              W.Field_If_Non_Blank ("asil", To_String (R.Asil));
                              W.Object_End;
                           end;
                        end if;
                     end loop;
                     W.Array_End;

                     W.Key ("tags");
                     W.Array_Start;
                     for T of Tags loop
                        declare
                           Idx     : constant Natural := Index_Of (To_String (T.Requirement_Id));
                           Include : Boolean := True;
                        begin
                           if Gaps then
                              Include := Idx > 0 and then not Statuses (Idx).Tested;
                           end if;
                           if Include then
                              W.Object_Start;
                              W.Field ("requirementId", To_String (T.Requirement_Id));
                              W.Field ("file", To_String (T.File));
                              W.Field ("line", T.Line);
                              W.Field ("kind",
                                (case T.Kind is
                                   when Fusa.Annotations.Impl     => "impl",
                                   when Fusa.Annotations.Test     => "test",
                                   when Fusa.Annotations.Sec_Test => "sec-test"));
                              W.Object_End;
                           end if;
                        end;
                     end loop;
                     W.Array_End;

                     W.Key ("coverage");
                     W.Object_Start;
                     W.Field ("totalRequirements", Total);
                     W.Field ("tracedRequirements", Traced_Count);
                     W.Field ("testedRequirements", Tested_Count);
                     W.Field ("secTestedRequirements", Sec_Tested_Count);
                     W.Field ("totalFunctions", Func_Total);
                     W.Field ("taggedFunctions", Func_Tagged_Count);
                     W.Object_End;

                     W.Object_End;
                     Emit (Args, Fusa.Json.Writer.To_String (W));
                  end;
               elsif Format = "html" or else Format = "md" then
                  declare
                     Is_Html : constant Boolean := Format = "html";
                     Buf     : Unbounded_String := Null_Unbounded_String;

                     function Status_Of (I : Positive) return String is
                       (if Statuses (I).Tested then "tested"
                        elsif Statuses (I).Traced then "traced"
                        else "gap");
                  begin
                     if Is_Html then
                        Append (Buf, "<!doctype html>" & ASCII.LF);
                        Append (Buf, "<html><head><meta charset=""utf-8"">" & ASCII.LF);
                        Append (Buf, "<title>" & Fusa.Tool_Name &
                                  " requirement traceability</title>" & ASCII.LF);
                        Append (Buf, "<style>" & ASCII.LF);
                        Append (Buf, "body{font-family:sans-serif;margin:2em}" & ASCII.LF);
                        Append (Buf, "table{border-collapse:collapse;width:100%}" & ASCII.LF);
                        Append (Buf, "th,td{border:1px solid #ccc;padding:4px 8px;" &
                                  "text-align:left}" & ASCII.LF);
                        Append (Buf, "th{background:#eee}" & ASCII.LF);
                        Append (Buf, "</style></head><body>" & ASCII.LF);
                        Append (Buf, "<h1>" & Fusa.Tool_Name &
                                  " requirement traceability</h1>" & ASCII.LF);
                        Append (Buf, "<p>requirements:" & Trim_Img (Total) &
                                  " traced:" & Trim_Img (Traced_Count) &
                                  " tested:" & Trim_Img (Tested_Count) &
                                  " sec-tested:" & Trim_Img (Sec_Tested_Count) & "<br>" &
                                  "functions:" & Trim_Img (Func_Total) &
                                  " tagged:" & Trim_Img (Func_Tagged_Count) & "</p>" & ASCII.LF);
                        Append (Buf, "<table><tr><th>Id</th><th>Title</th>" &
                                  "<th>Status</th></tr>" & ASCII.LF);
                     else
                        Append (Buf, "# " & Fusa.Tool_Name &
                                  " requirement traceability" & ASCII.LF & ASCII.LF);
                        Append (Buf, "requirements:" & Trim_Img (Total) &
                                  " traced:" & Trim_Img (Traced_Count) &
                                  " tested:" & Trim_Img (Tested_Count) &
                                  " sec-tested:" & Trim_Img (Sec_Tested_Count) & ASCII.LF &
                                  ASCII.LF);
                        Append (Buf, "functions:" & Trim_Img (Func_Total) &
                                  " tagged:" & Trim_Img (Func_Tagged_Count) & ASCII.LF &
                                  ASCII.LF);
                        Append (Buf, "| Id | Title | Status |" & ASCII.LF);
                        Append (Buf, "|---|---|---|" & ASCII.LF);
                     end if;

                     for I in 1 .. Total loop
                        if not Gaps or else not Statuses (I).Tested then
                           declare
                              R : constant Fusa.Config.Requirement := Reqs.Element (I);
                           begin
                              if Is_Html then
                                 Append (Buf, "<tr><td>" & To_String (R.Id) & "</td><td>" &
                                           To_String (R.Title) & "</td><td>" &
                                           Status_Of (I) & "</td></tr>" & ASCII.LF);
                              else
                                 Append (Buf, "| " & To_String (R.Id) & " | " &
                                           To_String (R.Title) & " | " & Status_Of (I) &
                                           " |" & ASCII.LF);
                              end if;
                           end;
                        end if;
                     end loop;

                     if Is_Html then
                        Append (Buf, "</table></body></html>");
                     end if;
                     Emit (Args, To_String (Buf));
                  end;
               else
                  declare
                     Buf : Unbounded_String := Null_Unbounded_String;
                  begin
                     Append (Buf, "requirements:" & Trim_Img (Total) &
                               " traced:" & Trim_Img (Traced_Count) &
                               " tested:" & Trim_Img (Tested_Count) &
                               " sec-tested:" & Trim_Img (Sec_Tested_Count) & ASCII.LF);
                     Append (Buf, "functions:" & Trim_Img (Func_Total) &
                               " tagged:" & Trim_Img (Func_Tagged_Count) & ASCII.LF);
                     for I in 1 .. Total loop
                        if not Gaps or else not Statuses (I).Tested then
                           Append (Buf, "  " & To_String (Reqs.Element (I).Id) &
                                     (if Statuses (I).Tested then " [tested]"
                                      elsif Statuses (I).Traced then " [traced]"
                                      else " [gap]") & ASCII.LF);
                        end if;
                     end loop;
                     Emit (Args, To_String (Buf));
                  end;
               end if;

               if Gate_Fail then
                  return Exit_Gate_Fail;
               end if;
               return Exit_Ok;
            end;
         end;
      end;
   end Cmd_Trace;

   ----------------------------------------------------------------------
   --  qualify
   ----------------------------------------------------------------------

   type Case_Result is record
      Name   : Unbounded_String;
      Result : Unbounded_String;
   end record;
   package Case_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Case_Result);

   --  fusa:req REQ-012
   function Cmd_Qualify (Args : String_List) return Integer is
      Dir      : constant String := Dir_Of (Args);
      Format   : constant String := Flag_Value (Args, "--format", "text");
      Out_Path : constant String := Flag_Value (Args, "--output", "");
      Effective_Out : constant String :=
        (if Out_Path'Length > 0 then Out_Path
         else Fusa.Files.Join (Dir, "qualify-report.json"));
      Tmp : constant String := Fusa.Files.Join (Dir, ".fusa-qualify-tmp");
      Cases : Case_Vectors.Vector;

      procedure Check_Rule (Rule_Id : String; Fixture : String) is
         File_Path : constant String := Fusa.Files.Join (Tmp, "fixture.adb");
      begin
         Fusa.Files.Write_File (File_Path, Fixture);
         declare
            Rel   : constant String := Fusa.Files.Relative_To (Dir, File_Path);
            Files : String_List;
         begin
            Files.Append (Rel);
            declare
               Findings : constant Finding_List := Fusa.Engine.Run_All (Dir, Files);
               Hit      : Boolean := False;
            begin
               for F of Findings loop
                  if To_String (F.Rule_Id) = Rule_Id then
                     Hit := True;
                  end if;
               end loop;
               Cases.Append
                 (Case_Result'(Name   => To_Unbounded_String ("rule-" & Rule_Id & "-known-answer"),
                               Result => To_Unbounded_String (if Hit then "PASS" else "FAIL")));
            end;
         end;
      end Check_Rule;
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: qualify: unsupported --format '" & Format & "'");
         return Exit_Usage;
      end if;

      --  Self-heal from a prior interrupted run (Ctrl-C, crash, disk full,
      --  etc. between Create_Path and the end-of-run Delete_Tree below)
      --  that left a stale fixture behind -- not just at the end.
      if Ada.Directories.Exists (Tmp) then
         Ada.Directories.Delete_Tree (Tmp);
      end if;
      Ada.Directories.Create_Path (Tmp);

      Check_Rule ("ADA001",
        "procedure P is" & ASCII.LF &
        "   pragma Suppress (All_Checks);" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA002",
        "procedure P is" & ASCII.LF & "begin" & ASCII.LF & "   null;" & ASCII.LF &
        "exception" & ASCII.LF & "   when others =>" & ASCII.LF &
        "      null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA003",
        "procedure P is" & ASCII.LF &
        "   function Conv is new Unchecked_Conversion (Integer, Float);" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA004",
        "procedure P is" & ASCII.LF &
        "   procedure Free is new Unchecked_Deallocation (Integer, Int_Access);" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA005",
        "procedure P is" & ASCII.LF & "begin" & ASCII.LF &
        "   null; -- " & (1 .. 90 => '-') & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA006",
        "procedure P is" & ASCII.LF & ASCII.HT & "begin" & ASCII.LF &
        "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA007",
        "procedure P is" & ASCII.LF & "begin" & ASCII.LF &
        "   null; -- TODO fix" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("ADA008",
        "pragma Warnings (Off, ""x"");" & ASCII.LF & "procedure P is" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);

      if Ada.Directories.Exists (Tmp) then
         Ada.Directories.Delete_Tree (Tmp);
      end if;

      --  section 6 MAY: sorting by name gives a single, unambiguous order
      --  that both the emitted results[] and the hash's canonicalization
      --  input share, so a verifier never has to guess whether to re-sort
      --  before re-hashing (simple insertion sort -- the case count is
      --  always small: one per starter rule plus qualify's own checks).
      for I in 2 .. Natural (Cases.Length) loop
         declare
            Key : constant Case_Result := Cases.Element (I);
            J   : Natural := I - 1;
         begin
            while J >= 1 and then Cases.Element (J).Name > Key.Name loop
               Cases.Replace_Element (J + 1, Cases.Element (J));
               J := J - 1;
            end loop;
            Cases.Replace_Element (J + 1, Key);
         end;
      end loop;

      declare
         Total, Passed, Failed : Natural := 0;
      begin
         for C of Cases loop
            Total := Total + 1;
            if To_String (C.Result) = "PASS" then
               Passed := Passed + 1;
            else
               Failed := Failed + 1;
            end if;
         end loop;

         --  fusa:req REQ-077
         --  section 6 MAY: hash = "sha256:" + hex(SHA-256(canonical)),
         --  where canonical is this document (minus the hash field itself,
         --  generatedAt blanked) serialised per RFC 8785 JCS: lexicographic
         --  keys, no insignificant whitespace. Hand-built rather than via a
         --  generic recursive canonicalizer, since qualify's document shape
         --  is fixed and every value is either a plain non-negative integer
         --  or an ASCII string -- both trivial to format per JCS/ECMAScript
         --  Number::toString without needing JCS's much harder general
         --  shortest-round-trip float formatting.
         declare
            Q : constant Character := '"';

            function Jcs_Escape (S : String) return String is
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for C of S loop
                  case C is
                     when '"'  => Append (Buf, '\' & '"');
                     when '\'  => Append (Buf, '\' & '\');
                     when Character'Val (8)  => Append (Buf, '\' & 'b');
                     when Character'Val (9)  => Append (Buf, '\' & 't');
                     when Character'Val (10) => Append (Buf, '\' & 'n');
                     when Character'Val (12) => Append (Buf, '\' & 'f');
                     when Character'Val (13) => Append (Buf, '\' & 'r');
                     when others =>
                        if Character'Pos (C) < 16#20# then
                           declare
                              Hex : constant String := "0123456789abcdef";
                              Hi  : constant Natural := Character'Pos (C) / 16;
                              Lo  : constant Natural := Character'Pos (C) mod 16;
                           begin
                              Append (Buf, '\' & 'u' & "00" &
                                        Hex (Hi + 1 .. Hi + 1) & Hex (Lo + 1 .. Lo + 1));
                           end;
                        else
                           Append (Buf, C);
                        end if;
                  end case;
               end loop;
               return To_String (Buf);
            end Jcs_Escape;

            function Jstr (S : String) return String is (Q & Jcs_Escape (S) & Q);

            Canon : Unbounded_String :=
              To_Unbounded_String ("{" & Q & "failed" & Q & ":" & Trim_Img (Failed));
            Hash_Value : Unbounded_String;
         begin
            Append (Canon, "," & Q & "generatedAt" & Q & ":" & Q & Q);
            Append (Canon, "," & Q & "kind" & Q & ":" & Jstr ("qualification"));
            Append (Canon, "," & Q & "language" & Q & ":" & Jstr ("ada"));
            Append (Canon, "," & Q & "passed" & Q & ":" & Trim_Img (Passed));
            Append (Canon, "," & Q & "results" & Q & ":[");
            declare
               First : Boolean := True;
            begin
               for C of Cases loop
                  if not First then
                     Append (Canon, ",");
                  end if;
                  First := False;
                  Append (Canon, "{" & Q & "name" & Q & ":" & Jstr (To_String (C.Name)) &
                            "," & Q & "result" & Q & ":" & Jstr (To_String (C.Result)) & "}");
               end loop;
            end;
            Append (Canon, "]");
            Append (Canon, "," & Q & "schemaVersion" & Q & ":" & Jstr (Fusa.Schema_Version));
            Append (Canon, "," & Q & "tool" & Q & ":" & Jstr (Fusa.Tool_Name));
            Append (Canon, "," & Q & "toolVersion" & Q & ":" & Jstr (Fusa.Version));
            Append (Canon, "," & Q & "total" & Q & ":" & Trim_Img (Total));
            Append (Canon, "}");
            Hash_Value :=
              To_Unbounded_String ("sha256:" & Fusa.Sha256.Hex_Digest (To_String (Canon)));

            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               Fusa.Report.Write_Header (W, "qualification");
               W.Field ("total", Total);
               W.Field ("passed", Passed);
               W.Field ("failed", Failed);
               W.Field ("hash", To_String (Hash_Value));
               W.Key ("results");
               W.Array_Start;
               for C of Cases loop
                  W.Object_Start;
                  W.Field ("name", To_String (C.Name));
                  W.Field ("result", To_String (C.Result));
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Object_End;
               Fusa.Files.Write_File (Effective_Out, Fusa.Json.Writer.To_String (W) & ASCII.LF);

               if Format = "json" and then Out_Path'Length = 0 then
                  Ada.Text_IO.Put_Line (Fusa.Json.Writer.To_String (W));
               end if;
            end;
         end;

         if Format /= "json" and then Out_Path'Length = 0 then
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for C of Cases loop
                  Append (Buf, To_String (C.Name) & ": " & To_String (C.Result) & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Total) & " total, " & Trim_Img (Passed) &
                         " passed, " & Trim_Img (Failed) & " failed");
               Ada.Text_IO.Put_Line (To_String (Buf));
            end;
         end if;

         if Failed > 0 then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Qualify;

   ----------------------------------------------------------------------
   --  release
   ----------------------------------------------------------------------

   function Cmd_Audit_Pack (Args : String_List) return Integer;

   --  fusa:req REQ-013
   function Cmd_Release (Args : String_List) return Integer is
      Dir        : constant String := Dir_Of (Args);
      Output_Dir : constant String := Flag_Value (Args, "--output-dir", Dir);
      Full       : constant Boolean := Has_Flag (Args, "--full");
      --  section 7 MAY: --spdx-version's mere presence (regardless of an
      --  explicit value) is what opts in to also emitting an SPDX
      --  document; its absence keeps the default sbom.json-only behaviour.
      Spdx_Requested : constant Boolean := Has_Flag (Args, "--spdx-version");
      Spdx_Version   : constant String := Flag_Value (Args, "--spdx-version", "2.3");
      Cfg        : Fusa.Config.Project_Config;
   begin
      if Spdx_Requested and then Spdx_Version /= "2.2" and then Spdx_Version /= "2.3"
        and then Spdx_Version /= "3.0.1"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: release: --spdx-version must be one of 2.2, 2.3, 3.0.1");
         return Exit_Usage;
      end if;
      if Spdx_Requested and then Spdx_Version = "3.0.1" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: release: --spdx-version 3.0.1 (JSON-LD graph model) is " &
            "not yet implemented -- only 2.2/2.3 are currently supported");
         return Exit_Usage;
      end if;

      begin
         Cfg := Fusa.Config.Load (Dir);
      exception
         when Fusa.Config.No_Config_Error =>
            return Emit_Runtime_Error (Args, "sbom", "no-config", "no .fusa.json found in " & Dir);
         when Fusa.Config.Invalid_Config_Error =>
            return Emit_Runtime_Error (Args, "sbom", "invalid-config", "invalid .fusa.json in " & Dir);
      end;

      if not Fusa.Files.Exists (Output_Dir) then
         Ada.Directories.Create_Path (Output_Dir);
      end if;

      declare
         W : Fusa.Json.Writer.Instance;
      begin
         W.Object_Start;
         Fusa.Report.Write_Header (W, "sbom");
         W.Field ("format", "x-FuSa SBOM v1");
         W.Field ("module",
           "github.com/SoundMatt/" & To_String (Cfg.Name) & "@" & To_String (Cfg.Version));
         W.Key ("components");
         W.Array_Start;
         W.Array_End;
         W.Object_End;
         Fusa.Files.Write_File
           (Fusa.Files.Join (Output_Dir, "sbom.json"), Fusa.Json.Writer.To_String (W) & ASCII.LF);
      end;
      Ada.Text_IO.Put_Line ("wrote " & Fusa.Files.Join (Output_Dir, "sbom.json"));

      --  fusa:req REQ-076
      if Spdx_Requested then
         declare
            Module    : constant String :=
              "github.com/SoundMatt/" & To_String (Cfg.Name) & "@" & To_String (Cfg.Version);
            Created   : constant String := Fusa.Report.Now_Rfc3339;
            --  A short deterministic-per-run suffix keeps the SPDX
            --  documentNamespace URI unique-enough per SPDX conventions,
            --  without depending on a random-number generator.
            Ns_Suffix : constant String :=
              Fusa.Sha256.Hex_Digest (Module & Created) (1 .. 8);
            Spdx_Path : constant String :=
              Fusa.Files.Join
                (Output_Dir, To_String (Cfg.Name) & "-" & To_String (Cfg.Version) & ".spdx.json");
            W4 : Fusa.Json.Writer.Instance;
         begin
            W4.Object_Start;
            W4.Field ("spdxVersion", "SPDX-" & Spdx_Version);
            W4.Field ("dataLicense", "CC0-1.0");
            W4.Field ("SPDXID", "SPDXRef-DOCUMENT");
            W4.Field ("name", To_String (Cfg.Name) & "-" & To_String (Cfg.Version));
            W4.Field ("documentNamespace",
              "https://github.com/SoundMatt/" & To_String (Cfg.Name) & "/spdx/" &
              To_String (Cfg.Version) & "-" & Ns_Suffix);
            W4.Key ("creationInfo");
            W4.Object_Start;
            W4.Field ("created", Created);
            W4.Key ("creators");
            W4.Array_Start;
            W4.Value ("Tool: " & Fusa.Tool_Name & "-" & Fusa.Version);
            W4.Array_End;
            W4.Object_End;
            W4.Key ("packages");
            W4.Array_Start;
            W4.Object_Start;
            W4.Field ("SPDXID", "SPDXRef-Package-" & To_String (Cfg.Name));
            W4.Field ("name", To_String (Cfg.Name));
            W4.Field ("versionInfo", To_String (Cfg.Version));
            W4.Field ("downloadLocation", "NOASSERTION");
            W4.Field ("licenseConcluded", "NOASSERTION");
            W4.Field ("licenseDeclared", "NOASSERTION");
            W4.Field ("copyrightText", "NOASSERTION");
            W4.Object_End;
            W4.Array_End;
            W4.Object_End;
            Fusa.Files.Write_File (Spdx_Path, Fusa.Json.Writer.To_String (W4) & ASCII.LF);
         end;
         Ada.Text_IO.Put_Line
           ("wrote " &
            Fusa.Files.Join
              (Output_Dir, To_String (Cfg.Name) & "-" & To_String (Cfg.Version) & ".spdx.json"));
      end if;

      if Full then
         declare
            W2 : Fusa.Json.Writer.Instance;
         begin
            W2.Object_Start;
            Fusa.Report.Write_Header (W2, "provenance");
            W2.Field ("buildType", "https://github.com/SoundMatt/ada-FuSa");
            W2.Object_End;
            Fusa.Files.Write_File
              (Fusa.Files.Join (Output_Dir, "provenance.json"),
               Fusa.Json.Writer.To_String (W2) & ASCII.LF);
         end;
         declare
            W3 : Fusa.Json.Writer.Instance;
         begin
            W3.Object_Start;
            Fusa.Report.Write_Header (W3, "artifact-manifest");
            W3.Key ("files");
            W3.Array_Start;
            W3.Array_End;
            W3.Object_End;
            Fusa.Files.Write_File
              (Fusa.Files.Join (Output_Dir, "artifact-manifest.json"),
               Fusa.Json.Writer.To_String (W3) & ASCII.LF);
         end;
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: skipping fmea (not yet implemented)");
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: skipping boundary (not yet implemented)");
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: skipping vuln (not yet implemented)");
         declare
            Rc : constant Integer := Cmd_Audit_Pack (Args);
         begin
            if Rc /= Exit_Ok then
               return Rc;
            end if;
         end;
      end if;
      return Exit_Ok;
   end Cmd_Release;

   ----------------------------------------------------------------------
   --  audit-pack
   ----------------------------------------------------------------------

   --  fusa:req REQ-014
   function Cmd_Audit_Pack (Args : String_List) return Integer is
      Dir      : constant String := Dir_Of (Args);
      Out_Path : constant String :=
        Flag_Value (Args, "--output", Fusa.Files.Join (Dir, "audit-pack.zip"));
      Entries  : Fusa.Zip.Entry_List;

      procedure Add_If_Exists (Name : String) is
         Full : constant String := Fusa.Files.Join (Dir, Name);
      begin
         if Fusa.Files.Exists (Full) and then not Fusa.Files.Is_Directory (Full) then
            declare
               Data : constant String := Fusa.Files.Read_File (Full);
            begin
               Entries.Append
                 (Fusa.Zip.Zip_Entry'(Name => To_Unbounded_String (Name),
                                      Data => To_Unbounded_String (Data)));
            end;
         end if;
      end Add_If_Exists;
   begin
      Add_If_Exists (Fusa.Config.Config_File);
      Add_If_Exists (Fusa.Config.Reqs_File);
      Add_If_Exists ("fusa-report.json");
      Add_If_Exists ("qualify-report.json");
      Add_If_Exists ("sbom.json");
      Add_If_Exists ("provenance.json");
      Add_If_Exists ("artifact-manifest.json");

      declare
         W : Fusa.Json.Writer.Instance;
      begin
         W.Object_Start;
         Fusa.Report.Write_Header (W, "audit-manifest");
         W.Key ("files");
         W.Array_Start;
         for E of Entries loop
            W.Object_Start;
            W.Field ("path", To_String (E.Name));
            W.Field ("size", Natural (Length (E.Data)));
            W.Field ("sha256", Fusa.Sha256.Hex_Digest (To_String (E.Data)));
            W.Object_End;
         end loop;
         W.Array_End;
         W.Object_End;
         Entries.Append
           (Fusa.Zip.Zip_Entry'(Name => To_Unbounded_String ("manifest.json"),
                                Data => To_Unbounded_String (Fusa.Json.Writer.To_String (W))));
      end;

      Fusa.Zip.Write_Zip (Out_Path, Entries);
      Ada.Text_IO.Put_Line ("wrote " & Out_Path);
      return Exit_Ok;
   end Cmd_Audit_Pack;

   ----------------------------------------------------------------------
   --  report
   ----------------------------------------------------------------------

   --  fusa:req REQ-015
   function Cmd_Report (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Has_Flag (Args, "--strict") then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: report: --strict is not a valid flag for report");
         return Exit_Usage;
      end if;
      if Format /= "text" and then Format /= "json" and then Format /= "sarif"
        and then Format /= "html" and then Format /= "md"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: report: unsupported --format '" & Format &
            "' (supported: text, json, sarif, html, md)");
         return Exit_Usage;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Findings : Finding_List := Fusa.Engine.Run_All (Dir, Files);
         begin
            --  fusa:req REQ-072
            if Fusa.Config.Dispositions_Exist (Dir) then
               declare
                  Disps          : constant Fusa.Config.Disposition_List :=
                    Fusa.Config.Load_Dispositions (Dir);
                  Orphan_Findings : Finding_List;
               begin
                  Fusa.Config.Apply_Dispositions (Findings, Disps, Orphan_Findings);
                  for F of Orphan_Findings loop
                     Findings.Append (F);
                  end loop;
               end;
            end if;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "report");
                  Fusa.Report.Write_Report_Extension
                    (W, Absolute_Path (Dir), To_String (Cfg.Name),
                     To_String (Cfg.Standard), To_String (Cfg.Asil),
                     To_String (Cfg.Sil), To_String (Cfg.Dal));
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings);
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            elsif Format = "sarif" then
               Emit (Args, Fusa.Report.Render_Sarif (Findings));
            elsif Format = "html" then
               Emit (Args, Fusa.Report.Render_Html (Findings));
            elsif Format = "md" then
               Emit (Args, Fusa.Report.Render_Md (Findings));
            else
               Emit (Args, Fusa.Report.Render_Text (Findings));
            end if;
         end;
      end;
      return Exit_Ok;
   end Cmd_Report;

   ----------------------------------------------------------------------
   --  Usage / dispatch
   ----------------------------------------------------------------------

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "usage: adafusa <command> [options]" & ASCII.LF &
        "commands: version capabilities init check trace qualify release audit-pack report");
   end Print_Usage;

   function Run (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "ada-FuSa: missing command");
         Print_Usage;
         return Exit_Usage;
      end if;

      declare
         Cmd  : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;

         if Cmd = "version" then
            return Cmd_Version (Rest);
         elsif Cmd = "capabilities" then
            return Cmd_Capabilities (Rest);
         elsif Cmd = "init" then
            return Cmd_Init (Rest);
         elsif Cmd = "check" then
            return Cmd_Check (Rest);
         elsif Cmd = "trace" then
            return Cmd_Trace (Rest);
         elsif Cmd = "qualify" then
            return Cmd_Qualify (Rest);
         elsif Cmd = "release" then
            return Cmd_Release (Rest);
         elsif Cmd = "audit-pack" then
            return Cmd_Audit_Pack (Rest);
         elsif Cmd = "report" then
            return Cmd_Report (Rest);
         elsif Cmd = "--help" or else Cmd = "-h" or else Cmd = "help" then
            Print_Usage;
            return Exit_Ok;
         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error, "ada-FuSa: unknown command '" & Cmd & "'");
            Print_Usage;
            return Exit_Usage;
         end if;
      end;
   end Run;

end Fusa.Cli;
