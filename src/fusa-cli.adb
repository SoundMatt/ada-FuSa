with Ada.Text_IO;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings;

with Fusa.Config;
with Fusa.Files;
with Fusa.Source_Scan;
with Fusa.Engine;
with Fusa.Annotations; use Fusa.Annotations;
with Fusa.Func_Scan;
with Fusa.Comp;
with Fusa.Badge;
with Fusa.Deps;
with Fusa.Analyze;
with Fusa.Rules_Lint;
with Fusa.Fix;
with Fusa.Report;
with Fusa.Json.Writer;
with Fusa.Sha256;
with Fusa.Hmac;
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
      W.Value ("comp");
      W.Value ("hara");
      W.Value ("tara");
      W.Value ("vuln");
      W.Value ("req");
      W.Value ("disposition");
      W.Value ("pr");
      W.Value ("metrics");
      W.Value ("sign");
      W.Value ("hooks");
      W.Value ("do178");
      W.Value ("iso26262");
      W.Value ("iso21434");
      W.Value ("iec61508");
      W.Value ("iec62443");
      W.Value ("unece");
      W.Value ("slsa");
      W.Value ("verify");
      W.Value ("diff");
      W.Value ("badge");
      W.Value ("boundary");
      W.Value ("impact");
      W.Value ("coupling");
      W.Value ("fmea");
      W.Value ("safety-case");
      W.Value ("cyber");
      W.Value ("sci");
      W.Value ("analyze");
      W.Value ("lint");
      W.Value ("sas");
      W.Value ("template");
      W.Value ("fix");
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
      W.Key ("comp");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("hara");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("tara");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("vuln");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("req");          W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("disposition");  W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("pr");           W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("metrics");      W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("sign");         W.Array_Start; W.Value ("text"); W.Array_End;
      W.Key ("hooks");        W.Array_Start; W.Value ("text"); W.Array_End;
      W.Key ("do178");        W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("iso26262");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("iso21434");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("iec61508");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("iec62443");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("unece");        W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("slsa");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("verify");       W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("diff");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("badge");        W.Array_Start; W.Value ("svg"); W.Array_End;
      W.Key ("boundary");     W.Array_Start; W.Value ("dot"); W.Value ("mermaid"); W.Array_End;
      W.Key ("impact");       W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("coupling");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("fmea");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Value ("csv"); W.Array_End;
      W.Key ("safety-case");  W.Array_Start; W.Value ("text"); W.Value ("json"); W.Value ("md"); W.Value ("mermaid"); W.Array_End;
      W.Key ("cyber");        W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("sci");          W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("analyze");      W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("lint");         W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("sas");          W.Array_Start; W.Value ("json"); W.Value ("md"); W.Array_End;
      W.Key ("template");     W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Key ("fix");          W.Array_Start; W.Value ("text"); W.Value ("json"); W.Array_End;
      W.Object_End;

      W.Key ("standards");
      W.Array_Start;
      W.Value ("do178c");
      W.Value ("iso26262");
      W.Value ("iso21434");
      W.Value ("iec61508");
      W.Value ("iec62443-4-1");
      W.Value ("unece-r155");
      W.Value ("slsa");
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
            --  section 9.1 MUST: "standard" is a required value exactly
            --  like "project.name" -- if it's missing and stdin is not a
            --  TTY (CI), init MUST exit 2 rather than prompt or write a
            --  placeholder config. Regression: this used to silently
            --  default to "generic" instead, writing a .fusa.json whose
            --  standard the caller never actually chose.
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: init requires --standard when not run interactively");
            return Exit_Usage;
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
            --  .fusa.json's "strict" only used to be honoured by check/
            --  cyber -- --req-coverage/--sec-tested's implicit 100%
            --  default under --strict must also trigger from a
            --  project-wide strict config, not just the CLI flag.
            Effective_Strict : constant Boolean := Strict or else Cfg.Strict;
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
               elsif Effective_Strict then
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
               elsif Effective_Strict then
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
                     --  §3.2: trace is a report document and MUST carry
                     --  projectRoot (+ SHOULD/MAY project/standard/asil/
                     --  sil/dal) -- this was missing entirely.
                     Fusa.Report.Write_Report_Extension
                       (W, Absolute_Path (Dir), To_String (Cfg.Name),
                        To_String (Cfg.Standard), To_String (Cfg.Asil),
                        To_String (Cfg.Sil), To_String (Cfg.Dal));

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
            "ada-FuSa: qualify: unsupported --format '" & Format &
            "' (supported: text, json)");
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
      --  fusa:test REQ-078
      Check_Rule ("SEC001",
        "procedure P is" & ASCII.LF &
        "   Password : constant String := ""hunter2"";" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("SEC002",
        "procedure P is" & ASCII.LF &
        "   Secret : constant String := ""x"";" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("SEC003",
        "with GNAT.MD5;" & ASCII.LF & "procedure P is" & ASCII.LF &
        "begin" & ASCII.LF & "   null;" & ASCII.LF & "end P;" & ASCII.LF);
      Check_Rule ("SEC004",
        "with GNAT.OS_Lib;" & ASCII.LF & "procedure P is" & ASCII.LF &
        "begin" & ASCII.LF &
        "   GNAT.OS_Lib.Spawn (""ls"", (1 .. 0 => <>));" & ASCII.LF &
        "end P;" & ASCII.LF);

      --  fusa:test REQ-079
      --  FUSA001-004 check Project_Root itself (LICENSE/README/*.gpr/
      --  .github/workflows), not the single-file fixture Check_Rule
      --  writes, so they can't be triggered the same way the
      --  content-scanning rules above are. Regression: this used to run
      --  them against Dir -- the project actually being qualified -- and
      --  call it a PASS only if none of them fired. That makes the
      --  "known answer" whatever markers Dir happens to have, which is
      --  backwards for a self-test (a freshly-init'd project with no
      --  LICENSE yet would report FUSA00x as FAILED, even though the
      --  rule is working exactly as designed) and gives no positive-
      --  detection coverage at all. Tmp is guaranteed to hold nothing
      --  but the scratch fixture.adb the loop above just wrote (it was
      --  freshly emptied and recreated at the top of this command), so
      --  using it as Project_Root gives a real, Dir-independent known
      --  answer: every one of FUSA001-004 MUST fire against it.
      declare
         Empty_Files : String_List;
         Findings    : constant Finding_List := Fusa.Engine.Run_All (Tmp, Empty_Files);

         procedure Check_Fusa_Rule (Rule_Id : String) is
            Hit : Boolean := False;
         begin
            for F of Findings loop
               if To_String (F.Rule_Id) = Rule_Id then
                  Hit := True;
               end if;
            end loop;
            Cases.Append
              (Case_Result'
                 (Name   => To_Unbounded_String ("rule-" & Rule_Id & "-known-answer"),
                  Result => To_Unbounded_String (if Hit then "PASS" else "FAIL")));
         end Check_Fusa_Rule;
      begin
         Check_Fusa_Rule ("FUSA001");
         Check_Fusa_Rule ("FUSA002");
         Check_Fusa_Rule ("FUSA003");
         Check_Fusa_Rule ("FUSA004");
      end;

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
               --  §3.2: qualify is a report document and MUST carry
               --  projectRoot -- this was missing entirely. qualify itself
               --  never requires a .fusa.json (it tests the tool's own
               --  rule engine, not the qualified project's compliance), so
               --  the SHOULD/MAY project/standard/asil/sil/dal fields are
               --  filled in on a best-effort basis and simply omitted
               --  (Write_Report_Extension already does this for blanks)
               --  when no config is present or it fails to load.
               declare
                  Proj_Name, Proj_Standard, Proj_Asil, Proj_Sil, Proj_Dal :
                    Unbounded_String := Null_Unbounded_String;
               begin
                  begin
                     declare
                        Qcfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Dir);
                     begin
                        Proj_Name     := Qcfg.Name;
                        Proj_Standard := Qcfg.Standard;
                        Proj_Asil     := Qcfg.Asil;
                        Proj_Sil      := Qcfg.Sil;
                        Proj_Dal      := Qcfg.Dal;
                     end;
                  exception
                     when Fusa.Config.No_Config_Error | Fusa.Config.Invalid_Config_Error =>
                        null;
                  end;
                  Fusa.Report.Write_Report_Extension
                    (W, Absolute_Path (Dir), To_String (Proj_Name),
                     To_String (Proj_Standard), To_String (Proj_Asil),
                     To_String (Proj_Sil), To_String (Proj_Dal));
               end;
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
   function Cmd_Vuln (Args : String_List) return Integer;
   function Cmd_Fmea (Args : String_List) return Integer;
   function Cmd_Boundary (Args : String_List) return Integer;

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
         declare
            Fmea_Args : String_List;
            Fmea_Rc   : Integer;
            pragma Unreferenced (Fmea_Rc);
         begin
            Fmea_Args.Append ("--dir");
            Fmea_Args.Append (Dir);
            Fmea_Args.Append ("--format");
            Fmea_Args.Append ("json");
            Fmea_Args.Append ("--output");
            Fmea_Args.Append (Fusa.Files.Join (Output_Dir, "fmea.json"));
            --  fmea and boundary are fully implemented commands (Cmd_Fmea,
            --  Cmd_Boundary) -- regression: this used to unconditionally
            --  print "not yet implemented" and skip both, which was false
            --  by the time either command shipped. fmea's own
            --  scaffold-on-first-run behaviour (a missing .fusa-fmea.json
            --  produces a template, not a report, and exits 0) does not
            --  abort the rest of --full's evidence pipeline, matching
            --  vuln's already-skip-don't-abort behaviour below.
            Fmea_Rc := Cmd_Fmea (Fmea_Args);
         end;
         declare
            Boundary_Args : String_List;
            Boundary_Rc   : Integer;
            pragma Unreferenced (Boundary_Rc);
         begin
            Boundary_Args.Append ("--dir");
            Boundary_Args.Append (Dir);
            Boundary_Args.Append ("--output");
            Boundary_Args.Append (Fusa.Files.Join (Output_Dir, "boundary.dot"));
            Boundary_Rc := Cmd_Boundary (Boundary_Args);
         end;
         declare
            Vuln_Args : String_List;
            Vuln_Rc   : Integer;
            pragma Unreferenced (Vuln_Rc);
         begin
            Vuln_Args.Append ("--dir");
            Vuln_Args.Append (Dir);
            Vuln_Args.Append ("--format");
            Vuln_Args.Append ("json");
            Vuln_Args.Append ("--output");
            Vuln_Args.Append (Fusa.Files.Join (Output_Dir, "vuln.json"));
            --  vuln's own severity-based gate (currently always Exit_Ok,
            --  since no vulnerability database is integrated -- see
            --  Cmd_Vuln) does not abort the rest of --full's evidence
            --  pipeline, matching fmea/boundary's already-skip-don't-abort
            --  behaviour above.
            Vuln_Rc := Cmd_Vuln (Vuln_Args);
         end;
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
      --  Regression: this used to be a fixed 7-file allowlist that missed
      --  most of the tool's own evidence artifacts (comp-report.json,
      --  vuln.json, badge.svg, boundary.dot/.mermaid, fmea.json/.csv,
      --  safety-case.*, sas.json/.md, and the SPDX document) -- silently
      --  shipping an "audit pack" that omitted evidence the project
      --  actually has, despite audit-pack's own README description
      --  promising "all existing evidence artifacts, bundled". Add_If_Exists
      --  already treats a missing file as "nothing to bundle", so this is
      --  every evidence artifact filename documented in README's Evidence
      --  Artifacts table -- listing one that doesn't exist for a given
      --  project is a no-op, not an error.
      Add_If_Exists (Fusa.Config.Config_File);
      Add_If_Exists (Fusa.Config.Reqs_File);
      Add_If_Exists ("fusa-report.json");
      Add_If_Exists ("qualify-report.json");
      Add_If_Exists ("sbom.json");
      Add_If_Exists ("provenance.json");
      Add_If_Exists ("artifact-manifest.json");
      Add_If_Exists ("comp-report.json");
      Add_If_Exists ("vuln.json");
      Add_If_Exists ("badge.svg");
      Add_If_Exists ("boundary.dot");
      Add_If_Exists ("boundary.mermaid");
      Add_If_Exists ("fmea.json");
      Add_If_Exists ("fmea.csv");
      Add_If_Exists ("safety-case.json");
      Add_If_Exists ("safety-case.md");
      Add_If_Exists ("safety-case.mermaid");
      Add_If_Exists ("sas.json");
      Add_If_Exists ("sas.md");

      --  The SPDX document's filename is <name>-<version>.spdx.json --
      --  variable, so it can't be a Name literal like the others above.
      --  Best-effort: if .fusa.json is missing or invalid, there is
      --  nothing to bundle here (and Config_File's own Add_If_Exists call
      --  above already surfaced that absence), so silently skip rather
      --  than failing the whole audit-pack over it.
      begin
         declare
            Cfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Dir);
         begin
            Add_If_Exists
              (To_String (Cfg.Name) & "-" & To_String (Cfg.Version) & ".spdx.json");
         end;
      exception
         when Fusa.Config.No_Config_Error | Fusa.Config.Invalid_Config_Error =>
            null;
      end;

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
   --  comp
   ----------------------------------------------------------------------

   --  fusa:req REQ-081
   function Cmd_Comp (Args : String_List) return Integer is
      Dir           : constant String := Dir_Of (Args);
      Format        : constant String := Flag_Value (Args, "--format", "text");
      Threshold_Str : constant String := Flag_Value (Args, "--threshold", "");
      Dal           : constant String := Flag_Value (Args, "--dal", "");
      Dal_Given     : constant Boolean := Has_Flag (Args, "--dal");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: comp: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if Dal_Given and then Dal /= "DAL-A" and then Dal /= "DAL-B"
        and then Dal /= "DAL-C" and then Dal /= "DAL-D"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: comp: --dal must be one of DAL-A, DAL-B, DAL-C, DAL-D");
         return Exit_Usage;
      end if;

      declare
         --  §9.2: A<=4, B<=10 (default), C<=15, D<=20; --dal overrides an
         --  explicit --threshold when both are given.
         Threshold : Natural := 10;
      begin
         if Dal_Given then
            Threshold :=
              (if Dal = "DAL-A" then 4
               elsif Dal = "DAL-B" then 10
               elsif Dal = "DAL-C" then 15
               else 20);
         elsif Threshold_Str'Length > 0 then
            begin
               Threshold := Natural'Value (Threshold_Str);
            exception
               when Constraint_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: comp: --threshold must be a non-negative integer");
                  return Exit_Usage;
            end;
         end if;

         if Threshold = 0 then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: comp: --threshold must be at least 1");
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
                    (Args, "comp-report", "no-config", "no .fusa.json found in " & Dir);
               when Fusa.Config.Invalid_Config_Error =>
                  return Emit_Runtime_Error
                    (Args, "comp-report", "invalid-config", "invalid .fusa.json in " & Dir);
            end;

            declare
               Files      : constant String_List :=
                 Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
               Results    : constant Fusa.Comp.Comp_Result_List :=
                 Fusa.Comp.Analyze (Dir, Files, Threshold);
               Violations : Natural := 0;
            begin
               for R of Results loop
                  if R.Exceeds_Threshold then
                     Violations := Violations + 1;
                  end if;
               end loop;

               if Format = "json" then
                  declare
                     W : Fusa.Json.Writer.Instance;
                  begin
                     W.Object_Start;
                     Fusa.Report.Write_Header (W, "comp-report");
                     W.Field ("threshold", Threshold);
                     if Dal_Given then
                        W.Field ("dal", Dal);
                     end if;
                     W.Field ("totalFunctions", Natural (Results.Length));
                     W.Field ("violations", Violations);
                     W.Key ("results");
                     W.Array_Start;
                     for R of Results loop
                        W.Object_Start;
                        W.Field ("file", To_String (R.File));
                        W.Field ("line", R.Line);
                        W.Field ("name", To_String (R.Name));
                        W.Field ("complexity", R.Complexity);
                        W.Field ("exceedsThreshold", R.Exceeds_Threshold);
                        W.Object_End;
                     end loop;
                     W.Array_End;
                     W.Object_End;
                     Emit (Args, Fusa.Json.Writer.To_String (W));
                  end;
               else
                  declare
                     Buf : Unbounded_String := Null_Unbounded_String;
                  begin
                     for R of Results loop
                        Append (Buf, To_String (R.File) & ":" & Trim_Img (R.Line) & " " &
                                  To_String (R.Name) & " complexity=" & Trim_Img (R.Complexity) &
                                  (if R.Exceeds_Threshold then " [EXCEEDS]" else "") & ASCII.LF);
                     end loop;
                     Append (Buf, Trim_Img (Natural (Results.Length)) & " functions, " &
                               Trim_Img (Violations) & " exceeding threshold " &
                               Trim_Img (Threshold));
                     Emit (Args, To_String (Buf));
                  end;
               end if;

               if Violations > 0 then
                  return Exit_Gate_Fail;
               end if;
               return Exit_Ok;
            end;
         end;
      end;
   end Cmd_Comp;

   ----------------------------------------------------------------------
   --  hara
   ----------------------------------------------------------------------

   --  fusa:req REQ-084
   function Cmd_Hara (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Init   : constant Boolean := Has_Flag (Args, "--init");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: hara: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Hara_Exists (Dir) then
         if not Init then
            --  section 1.2.5 MUST: a hara run with --format json on an
            --  absent file (with no --init/scaffold flag) MUST exit
            --  non-zero rather than silently report zero hazards as if
            --  the analysis were complete.
            return Emit_Runtime_Error
              (Args, "hara-report", "no-config",
               "no " & Fusa.Config.Hara_File & " found in " & Dir &
               " (pass --init to scaffold one)");
         end if;
         declare
            Standard_Hint : Unbounded_String := Null_Unbounded_String;
         begin
            begin
               declare
                  Hcfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Dir);
               begin
                  Standard_Hint := Hcfg.Standard;
               end;
            exception
               when Fusa.Config.No_Config_Error | Fusa.Config.Invalid_Config_Error =>
                  null;
            end;
            Fusa.Config.Scaffold_Hara (Dir, To_String (Standard_Hint));
         end;
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Hara_File) &
              " (template) -- fill in your hazards and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings : Finding_List;
         Doc      : constant Fusa.Config.Hara_Document := Fusa.Config.Load_Hara (Dir, Findings);
         Hazards_With_Asil, Hazards_With_Sg, Sg_With_Fssr : Natural := 0;
      begin
         for H of Doc.Hazards loop
            if Length (H.Risk.Asil) > 0 then
               Hazards_With_Asil := Hazards_With_Asil + 1;
            end if;
            if not H.Safety_Goals.Is_Empty then
               Hazards_With_Sg := Hazards_With_Sg + 1;
            end if;
         end loop;
         for SG of Doc.Safety_Goals loop
            if not SG.Fssr_Refs.Is_Empty then
               Sg_With_Fssr := Sg_With_Fssr + 1;
            end if;
         end loop;

         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               --  §1.2.5/§9.2: kind is "hara-report", not the bare
               --  command name. The JSON output shares the input file's
               --  operationalSituations/hazards/safetyGoals shape
               --  verbatim (per section 9.2), plus a draft "completeness"
               --  block and the usual validation findings/summary
               --  extension.
               Fusa.Report.Write_Header (W, "hara-report");
               W.Key ("operationalSituations");
               W.Array_Start;
               for OS of Doc.Operational_Situations loop
                  W.Object_Start;
                  W.Field ("id", To_String (OS.Id));
                  W.Field ("description", To_String (OS.Description));
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Key ("hazards");
               W.Array_Start;
               for H of Doc.Hazards loop
                  W.Object_Start;
                  W.Field ("id", To_String (H.Id));
                  W.Field ("description", To_String (H.Description));
                  W.Field_If_Non_Blank ("source", To_String (H.Source));
                  W.Key ("situations");
                  W.Array_Start;
                  for S of H.Situations loop
                     W.Value (S);
                  end loop;
                  W.Array_End;
                  W.Key ("risk");
                  W.Object_Start;
                  W.Field ("severity", To_String (H.Risk.Severity));
                  W.Field ("exposure", To_String (H.Risk.Exposure));
                  W.Field ("controllability", To_String (H.Risk.Controllability));
                  W.Field ("asil", To_String (H.Risk.Asil));
                  W.Object_End;
                  W.Key ("safetyGoals");
                  W.Array_Start;
                  for SG of H.Safety_Goals loop
                     W.Value (SG);
                  end loop;
                  W.Array_End;
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Key ("safetyGoals");
               W.Array_Start;
               for SG of Doc.Safety_Goals loop
                  W.Object_Start;
                  W.Field ("id", To_String (SG.Id));
                  W.Field ("description", To_String (SG.Description));
                  W.Key ("hazards");
                  W.Array_Start;
                  for H of SG.Hazards loop
                     W.Value (H);
                  end loop;
                  W.Array_End;
                  W.Field ("asil", To_String (SG.Asil));
                  W.Field_If_Non_Blank ("safeState", To_String (SG.Safe_State));
                  W.Key ("fssrRefs");
                  W.Array_Start;
                  for R of SG.Fssr_Refs loop
                     W.Value (R);
                  end loop;
                  W.Array_End;
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Key ("completeness");
               W.Object_Start;
               W.Field ("totalHazards", Natural (Doc.Hazards.Length));
               W.Field ("hazardsWithAsil", Hazards_With_Asil);
               W.Field ("hazardsWithSafetyGoal", Hazards_With_Sg);
               W.Field ("safetyGoalsWithFssrRefs", Sg_With_Fssr);
               W.Field ("danglingReferences", Doc.Dangling_References);
               W.Object_End;
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings);
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         else
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for H of Doc.Hazards loop
                  Append (Buf, To_String (H.Id) & ": " & To_String (H.Description) &
                            " (ASIL " & To_String (H.Risk.Asil) & ")" & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Natural (Doc.Hazards.Length)) & " hazards, " &
                         Trim_Img (Natural (Doc.Safety_Goals.Length)) & " safety goals, " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings");
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Hara;

   ----------------------------------------------------------------------
   --  tara
   ----------------------------------------------------------------------

   --  fusa:req REQ-085
   function Cmd_Tara (Args : String_List) return Integer is
      Dir       : constant String := Dir_Of (Args);
      Format    : constant String := Flag_Value (Args, "--format", "text");
      Init      : constant Boolean := Has_Flag (Args, "--init");
      Min_Cov_Str : constant String := Flag_Value (Args, "--min-coverage", "");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: tara: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Tara_Exists (Dir) then
         if not Init then
            --  Same MUST as hara (section 1.2.5, applied consistently to
            --  its structural sibling): a missing input file must not be
            --  silently reported as a complete, empty analysis.
            return Emit_Runtime_Error
              (Args, "tara-report", "no-config",
               "no " & Fusa.Config.Tara_File & " found in " & Dir &
               " (pass --init to scaffold one)");
         end if;
         Fusa.Config.Scaffold_Tara (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Tara_File) &
              " (template) -- fill in your threats and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings : Finding_List;
         Doc      : constant Fusa.Config.Tara_Document := Fusa.Config.Load_Tara (Dir, Findings);

         --  summary.assetsAnalyzed: the number of distinct assets actually
         --  covered, not the raw threat count (the same asset can have
         --  several threats).
         function Count_Distinct_Assets return Natural is
            Seen  : String_List;
            Count : Natural := 0;
         begin
            for T of Doc.Threats loop
               declare
                  A     : constant String := To_String (T.Asset);
                  Found : Boolean := False;
               begin
                  for S of Seen loop
                     if S = A then
                        Found := True;
                        exit;
                     end if;
                  end loop;
                  if not Found then
                     Seen.Append (A);
                     Count := Count + 1;
                  end if;
               end;
            end loop;
            return Count;
         end Count_Distinct_Assets;

         Assets_Analyzed  : constant Natural := Count_Distinct_Assets;
         Assets_In_Project : constant Natural :=
           (if Doc.Assets_In_Project_Given then Doc.Assets_In_Project else Assets_Analyzed);
         Coverage_Pct     : constant Natural :=
           (if Assets_In_Project = 0 then 100
            else Assets_Analyzed * 100 / Assets_In_Project);
         Min_Coverage     : Natural := 0;
         Gate_Fail        : Boolean := False;
      begin
         if Min_Cov_Str'Length > 0 then
            begin
               Min_Coverage := Natural'Value (Min_Cov_Str);
            exception
               when Constraint_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: tara: --min-coverage must be a non-negative integer");
                  return Exit_Usage;
            end;
         end if;
         if Min_Coverage > 0 and then Coverage_Pct < Min_Coverage then
            Gate_Fail := True;
         end if;

         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               --  §1.2.5/§9.2: kind is "tara-report", not the bare
               --  command name. "summary" is the canonical coverage
               --  block (section 9.2), NOT the generic errors/warnings/
               --  infos tally every other JSON report uses -- that tally
               --  goes under "findingsSummary" instead (same collision
               --  gap-report had, fixed the same way).
               Fusa.Report.Write_Header (W, "tara-report");
               W.Key ("threats");
               W.Array_Start;
               for T of Doc.Threats loop
                  W.Object_Start;
                  W.Field ("id", To_String (T.Id));
                  W.Field ("asset", To_String (T.Asset));
                  W.Field ("threat", To_String (T.Description));
                  W.Field_If_Non_Blank ("cwe", To_String (T.Cwe));
                  W.Field ("attackVector", To_String (T.Attack_Vector));
                  W.Field ("attackFeasibility", To_String (T.Attack_Feasibility));
                  W.Key ("impact");
                  W.Object_Start;
                  W.Field ("safety", To_String (T.Impact.Safety));
                  W.Field ("financial", To_String (T.Impact.Financial));
                  W.Field ("operational", To_String (T.Impact.Operational));
                  W.Field ("privacy", To_String (T.Impact.Privacy));
                  W.Object_End;
                  W.Field ("risk", To_String (T.Risk));
                  W.Field ("treatment", To_String (T.Treatment));
                  W.Key ("mitigations");
                  W.Array_Start;
                  for M of T.Mitigations loop
                     W.Value (M);
                  end loop;
                  W.Array_End;
                  if T.Location.Present then
                     W.Key ("location");
                     W.Object_Start;
                     W.Field ("file", To_String (T.Location.File));
                     if T.Location.Line > 0 then
                        W.Field ("line", T.Location.Line);
                     end if;
                     W.Object_End;
                  end if;
                  W.Field_If_Non_Blank ("cyberRuleId", To_String (T.Cyber_Rule_Id));
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Key ("summary");
               W.Object_Start;
               W.Field ("assetsAnalyzed", Assets_Analyzed);
               W.Field ("assetsInProject", Assets_In_Project);
               W.Field ("coveragePct", Coverage_Pct);
               W.Field_If_Non_Blank
                 ("assetInventoryMethod", To_String (Doc.Asset_Inventory_Method));
               W.Object_End;
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings, "findingsSummary");
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         else
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for T of Doc.Threats loop
                  Append (Buf, To_String (T.Id) & ": " & To_String (T.Description) &
                            " (risk " & To_String (T.Risk) & ")" & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Natural (Doc.Threats.Length)) & " threats, " &
                         Trim_Img (Assets_Analyzed) & "/" & Trim_Img (Assets_In_Project) &
                         " assets analyzed (" & Trim_Img (Coverage_Pct) & "%), " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings");
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Gate_Fail or else Fusa.Report.Has_Gate_Failure (Findings, False) then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Tara;

   ----------------------------------------------------------------------
   --  vuln
   ----------------------------------------------------------------------

   --  fusa:req REQ-086
   function Cmd_Vuln (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: vuln: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      declare
         Findings : Finding_List;
      begin
         --  No vulnerability database is integrated (see README) -- this
         --  always reports a clean scan. Only a project with an Alire
         --  manifest even has third-party dependencies worth considering;
         --  ada-FuSa's own zero-dependency build always reports 0 findings.
         if Fusa.Files.Exists (Fusa.Files.Join (Dir, "alire.toml")) then
            Findings.Append
              (Make_Finding
                 (Rule_Id     => "VULN001",
                  Severity    => Info,
                  Message     =>
                    "alire.toml found, but no vulnerability database is " &
                    "integrated -- this scan cannot detect real CVEs",
                  Loc         => Make_Location ("alire.toml"),
                  Category    => Fusa.Supply_Chain,
                  Remediation =>
                    "cross-check dependencies against a CVE database " &
                    "manually until issue #28's follow-up lands"));
         end if;

         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               Fusa.Report.Write_Header (W, "vuln");
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings);
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         else
            Emit (Args, Fusa.Report.Render_Text (Findings));
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Vuln;

   ----------------------------------------------------------------------
   --  req
   ----------------------------------------------------------------------

   --  fusa:req REQ-090
   function Cmd_Req (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: req: missing subcommand (list|add)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;
         if Verb = "list" then
            declare
               Dir    : constant String := Dir_Of (Rest);
               Format : constant String := Flag_Value (Rest, "--format", "text");
               Dup    : Finding_List;
               Reqs   : constant Fusa.Config.Requirement_List :=
                 Fusa.Config.Load_Requirements (Dir, Dup);
            begin
               if Format /= "text" and then Format /= "json" then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: req list: unsupported --format '" & Format &
                     "' (supported: text, json)");
                  return Exit_Usage;
               end if;
               if Format = "json" then
                  declare
                     W : Fusa.Json.Writer.Instance;
                  begin
                     W.Object_Start;
                     Fusa.Report.Write_Header (W, "req-list");
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
                     Emit (Rest, Fusa.Json.Writer.To_String (W));
                  end;
               else
                  declare
                     Buf : Unbounded_String := Null_Unbounded_String;
                  begin
                     for R of Reqs loop
                        Append (Buf, To_String (R.Id) & ": " & To_String (R.Title) & ASCII.LF);
                     end loop;
                     Append (Buf, Trim_Img (Natural (Reqs.Length)) & " requirements");
                     Emit (Rest, To_String (Buf));
                  end;
               end if;
            end;
            return Exit_Ok;

         elsif Verb = "add" then
            declare
               Dir       : constant String := Dir_Of (Rest);
               Id, Title : Unbounded_String := Null_Unbounded_String;
            begin
               declare
                  I : Positive := 1;
               begin
                  while I <= Natural (Rest.Length) loop
                     declare
                        A : constant String := Rest.Element (I);
                     begin
                        if A = "--dir" or else A = "--text" or else A = "--standard"
                          or else A = "--level" or else A = "--asil" or else A = "--parent"
                        then
                           I := I + 2;
                        elsif A'Length > 0 and then A (A'First) /= '-' then
                           if Length (Id) = 0 then
                              Id := To_Unbounded_String (A);
                           elsif Length (Title) = 0 then
                              Title := To_Unbounded_String (A);
                           end if;
                           I := I + 1;
                        else
                           I := I + 1;
                        end if;
                     end;
                  end loop;
               end;

               if Length (Id) = 0 or else Length (Title) = 0 then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error, "ada-FuSa: req add: requires <id> <title>");
                  return Exit_Usage;
               end if;

               declare
                  Dup  : Finding_List;
                  Reqs : Fusa.Config.Requirement_List := Fusa.Config.Load_Requirements (Dir, Dup);
               begin
                  for R of Reqs loop
                     if To_String (R.Id) = To_String (Id) then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: req add: id """ & To_String (Id) & """ already exists");
                        return Exit_Usage;
                     end if;
                  end loop;

                  declare
                     New_Req : Fusa.Config.Requirement;
                  begin
                     New_Req.Id       := Id;
                     New_Req.Title    := Title;
                     New_Req.Text     := To_Unbounded_String (Flag_Value (Rest, "--text", ""));
                     New_Req.Standard := To_Unbounded_String (Flag_Value (Rest, "--standard", ""));
                     New_Req.Level    := To_Unbounded_String (Flag_Value (Rest, "--level", ""));
                     New_Req.Asil     := To_Unbounded_String (Flag_Value (Rest, "--asil", ""));
                     New_Req.Parent   := To_Unbounded_String (Flag_Value (Rest, "--parent", ""));
                     Reqs.Append (New_Req);
                  end;
                  Fusa.Config.Save_Requirements (Dir, Reqs);
                  Ada.Text_IO.Put_Line
                    ("added " & To_String (Id) & " to " &
                       Fusa.Files.Join (Dir, Fusa.Config.Reqs_File));
               end;
            end;
            return Exit_Ok;

         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: req: unknown subcommand '" & Verb & "' (expected list|add)");
            return Exit_Usage;
         end if;
      end;
   end Cmd_Req;

   ----------------------------------------------------------------------
   --  disposition
   ----------------------------------------------------------------------

   --  fusa:req REQ-091
   function Cmd_Disposition (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: disposition: missing subcommand (list|add)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;
         if Verb = "list" then
            declare
               Dir    : constant String := Dir_Of (Rest);
               Format : constant String := Flag_Value (Rest, "--format", "text");
               Disps  : constant Fusa.Config.Disposition_List :=
                 Fusa.Config.Load_Dispositions (Dir);
            begin
               if Format /= "text" and then Format /= "json" then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: disposition list: unsupported --format '" & Format &
                     "' (supported: text, json)");
                  return Exit_Usage;
               end if;
               if Format = "json" then
                  declare
                     W : Fusa.Json.Writer.Instance;
                  begin
                     W.Object_Start;
                     Fusa.Report.Write_Header (W, "disposition-list");
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
                        W.Object_End;
                     end loop;
                     W.Array_End;
                     W.Object_End;
                     Emit (Rest, Fusa.Json.Writer.To_String (W));
                  end;
               else
                  declare
                     Buf : Unbounded_String := Null_Unbounded_String;
                  begin
                     for E of Disps loop
                        Append
                          (Buf,
                           (if Length (E.Fingerprint) > 0 then To_String (E.Fingerprint)
                            else To_String (E.Rule_Id)) &
                             ": " & Image (E.Status) & " -- " & To_String (E.Note) & ASCII.LF);
                     end loop;
                     Append (Buf, Trim_Img (Natural (Disps.Length)) & " dispositions");
                     Emit (Rest, To_String (Buf));
                  end;
               end if;
            end;
            return Exit_Ok;

         elsif Verb = "add" then
            declare
               Dir            : constant String := Dir_Of (Rest);
               Fp             : Unbounded_String := Null_Unbounded_String;
               Status_Str     : Unbounded_String := Null_Unbounded_String;
               Rationale      : Unbounded_String := Null_Unbounded_String;
               Positional_Idx : Natural := 0;
            begin
               declare
                  I : Positive := 1;
               begin
                  while I <= Natural (Rest.Length) loop
                     declare
                        A : constant String := Rest.Element (I);
                     begin
                        if A = "--dir" or else A = "--rule-id" or else A = "--file"
                          or else A = "--line" or else A = "--by"
                        then
                           I := I + 2;
                        elsif A'Length > 0 and then A (A'First) /= '-' then
                           Positional_Idx := Positional_Idx + 1;
                           case Positional_Idx is
                              when 1 => Fp := To_Unbounded_String (A);
                              when 2 => Status_Str := To_Unbounded_String (A);
                              when 3 => Rationale := To_Unbounded_String (A);
                              when others => null;
                           end case;
                           I := I + 1;
                        else
                           I := I + 1;
                        end if;
                     end;
                  end loop;
               end;

               if Length (Fp) = 0 or else Length (Status_Str) = 0 then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: disposition add: requires <fingerprint-or-ruleId> " &
                       "<accepted|deferred|rejected> [rationale]");
                  return Exit_Usage;
               end if;

               if To_String (Status_Str) /= "accepted"
                 and then To_String (Status_Str) /= "deferred"
                 and then To_String (Status_Str) /= "rejected"
               then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: disposition add: status must be one of accepted, " &
                       "deferred, rejected");
                  return Exit_Usage;
               end if;

               declare
                  Disps  : Fusa.Config.Disposition_List := Fusa.Config.Load_Dispositions (Dir);
                  E      : Fusa.Config.Disposition_Entry;
                  Fp_Str : constant String := To_String (Fp);
               begin
                  --  A bare rule id (e.g. "ADA001") is distinguished from a
                  --  fingerprint by the "sha256:" prefix a fingerprint
                  --  always carries (spec section 4.2).
                  if Fp_Str'Length >= 7
                    and then Fp_Str (Fp_Str'First .. Fp_Str'First + 6) = "sha256:"
                  then
                     E.Fingerprint := Fp;
                  else
                     E.Rule_Id := Fp;
                  end if;
                  E.File := To_Unbounded_String (Flag_Value (Rest, "--file", ""));
                  declare
                     Line_Str : constant String := Flag_Value (Rest, "--line", "");
                  begin
                     if Line_Str'Length > 0 then
                        begin
                           E.Line := Natural'Value (Line_Str);
                        exception
                           when Constraint_Error =>
                              Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Standard_Error,
                                 "ada-FuSa: disposition add: --line must be a " &
                                   "non-negative integer");
                              return Exit_Usage;
                        end;
                     end if;
                  end;
                  if Length (E.Rule_Id) = 0 then
                     E.Rule_Id := To_Unbounded_String (Flag_Value (Rest, "--rule-id", ""));
                  end if;
                  E.Status :=
                    (if To_String (Status_Str) = "accepted" then Accepted
                     elsif To_String (Status_Str) = "deferred" then Deferred
                     else Rejected);
                  E.Note    := Rationale;
                  E.By      := To_Unbounded_String (Flag_Value (Rest, "--by", ""));
                  E.At_Time := To_Unbounded_String (Fusa.Report.Now_Rfc3339);
                  Disps.Append (E);
                  Fusa.Config.Save_Dispositions (Dir, Disps);
                  Ada.Text_IO.Put_Line
                    ("added disposition for " & Fp_Str & " to " &
                       Fusa.Files.Join (Dir, Fusa.Config.Dispositions_File));
               end;
            end;
            return Exit_Ok;

         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: disposition: unknown subcommand '" & Verb & "' (expected list|add)");
            return Exit_Usage;
         end if;
      end;
   end Cmd_Disposition;

   ----------------------------------------------------------------------
   --  pr
   ----------------------------------------------------------------------

   --  fusa:req REQ-095
   function Cmd_Pr (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: pr: missing subcommand (init|list|add|close)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;
         declare
            Dir : constant String := Dir_Of (Rest);
         begin
            if Verb = "init" then
               if Fusa.Config.Pr_Exists (Dir) then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: " & Fusa.Files.Join (Dir, Fusa.Config.Pr_File) &
                       " already exists, leaving unchanged");
               else
                  Fusa.Config.Save_Pr (Dir, Fusa.Config.Problem_Report_Vectors.Empty_Vector);
                  Ada.Text_IO.Put_Line ("created " & Fusa.Files.Join (Dir, Fusa.Config.Pr_File));
               end if;
               return Exit_Ok;

            elsif Verb = "list" then
               declare
                  Format  : constant String := Flag_Value (Rest, "--format", "text");
                  Reports : constant Fusa.Config.Problem_Report_List := Fusa.Config.Load_Pr (Dir);
               begin
                  if Format /= "text" and then Format /= "json" then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "ada-FuSa: pr list: unsupported --format '" & Format &
                        "' (supported: text, json)");
                     return Exit_Usage;
                  end if;
                  if Format = "json" then
                     declare
                        W : Fusa.Json.Writer.Instance;
                     begin
                        W.Object_Start;
                        Fusa.Report.Write_Header (W, "pr-list");
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
                        Emit (Rest, Fusa.Json.Writer.To_String (W));
                     end;
                  else
                     declare
                        Buf : Unbounded_String := Null_Unbounded_String;
                     begin
                        for P of Reports loop
                           Append (Buf, To_String (P.Id) & " [" & To_String (P.Status) & "]: " &
                                     To_String (P.Title) & ASCII.LF);
                        end loop;
                        Append (Buf, Trim_Img (Natural (Reports.Length)) & " problem reports");
                        Emit (Rest, To_String (Buf));
                     end;
                  end if;
               end;
               return Exit_Ok;

            elsif Verb = "add" then
               declare
                  Id, Title : Unbounded_String := Null_Unbounded_String;
               begin
                  declare
                     I : Positive := 1;
                  begin
                     while I <= Natural (Rest.Length) loop
                        declare
                           A : constant String := Rest.Element (I);
                        begin
                           if A = "--dir" or else A = "--severity" then
                              I := I + 2;
                           elsif A'Length > 0 and then A (A'First) /= '-' then
                              if Length (Id) = 0 then
                                 Id := To_Unbounded_String (A);
                              elsif Length (Title) = 0 then
                                 Title := To_Unbounded_String (A);
                              end if;
                              I := I + 1;
                           else
                              I := I + 1;
                           end if;
                        end;
                     end loop;
                  end;

                  if Length (Id) = 0 or else Length (Title) = 0 then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error, "ada-FuSa: pr add: requires <id> <title>");
                     return Exit_Usage;
                  end if;

                  declare
                     Reports : Fusa.Config.Problem_Report_List := Fusa.Config.Load_Pr (Dir);
                  begin
                     for P of Reports loop
                        if To_String (P.Id) = To_String (Id) then
                           Ada.Text_IO.Put_Line
                             (Ada.Text_IO.Standard_Error,
                              "ada-FuSa: pr add: id """ & To_String (Id) & """ already exists");
                           return Exit_Usage;
                        end if;
                     end loop;

                     declare
                        New_Pr : Fusa.Config.Problem_Report;
                     begin
                        New_Pr.Id        := Id;
                        New_Pr.Title     := Title;
                        New_Pr.Severity  := To_Unbounded_String (Flag_Value (Rest, "--severity", ""));
                        New_Pr.Status    := To_Unbounded_String ("open");
                        New_Pr.Opened_At := To_Unbounded_String (Fusa.Report.Now_Rfc3339);
                        Reports.Append (New_Pr);
                     end;
                     Fusa.Config.Save_Pr (Dir, Reports);
                     Ada.Text_IO.Put_Line
                       ("added " & To_String (Id) & " to " &
                          Fusa.Files.Join (Dir, Fusa.Config.Pr_File));
                  end;
               end;
               return Exit_Ok;

            elsif Verb = "close" then
               declare
                  Id : Unbounded_String := Null_Unbounded_String;
               begin
                  declare
                     I : Positive := 1;
                  begin
                     while I <= Natural (Rest.Length) loop
                        declare
                           A : constant String := Rest.Element (I);
                        begin
                           if A = "--dir" or else A = "--resolution" then
                              I := I + 2;
                           elsif A'Length > 0 and then A (A'First) /= '-' then
                              if Length (Id) = 0 then
                                 Id := To_Unbounded_String (A);
                              end if;
                              I := I + 1;
                           else
                              I := I + 1;
                           end if;
                        end;
                     end loop;
                  end;

                  if Length (Id) = 0 then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error, "ada-FuSa: pr close: requires <id>");
                     return Exit_Usage;
                  end if;

                  declare
                     Reports : Fusa.Config.Problem_Report_List := Fusa.Config.Load_Pr (Dir);
                     Found   : Boolean := False;
                  begin
                     for I in 1 .. Natural (Reports.Length) loop
                        if To_String (Reports.Element (I).Id) = To_String (Id) then
                           declare
                              P : Fusa.Config.Problem_Report := Reports.Element (I);
                           begin
                              P.Status     := To_Unbounded_String ("closed");
                              P.Resolution := To_Unbounded_String (Flag_Value (Rest, "--resolution", ""));
                              P.Closed_At  := To_Unbounded_String (Fusa.Report.Now_Rfc3339);
                              Reports.Replace_Element (I, P);
                           end;
                           Found := True;
                           exit;
                        end if;
                     end loop;

                     if not Found then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: pr close: no problem report with id """ &
                             To_String (Id) & """");
                        return Exit_Usage;
                     end if;

                     Fusa.Config.Save_Pr (Dir, Reports);
                     Ada.Text_IO.Put_Line ("closed " & To_String (Id));
                  end;
               end;
               return Exit_Ok;

            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "ada-FuSa: pr: unknown subcommand '" & Verb & "' (expected init|list|add|close)");
               return Exit_Usage;
            end if;
         end;
      end;
   end Cmd_Pr;

   ----------------------------------------------------------------------
   --  metrics
   ----------------------------------------------------------------------

   --  fusa:req REQ-094
   function Cmd_Metrics (Args : String_List) return Integer is
      Record_Mode : Boolean := False;
      Rest        : String_List := Args;
   begin
      if not Args.Is_Empty and then Args.Element (1) = "record" then
         Record_Mode := True;
         Rest.Delete_First;
      end if;

      declare
         Dir    : constant String := Dir_Of (Rest);
         Format : constant String := Flag_Value (Rest, "--format", "text");
      begin
         if Format /= "text" and then Format /= "json" then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: metrics: unsupported --format '" & Format &
                 "' (supported: text, json)");
            return Exit_Usage;
         end if;

         if Record_Mode then
            declare
               Cfg : Fusa.Config.Project_Config;
            begin
               begin
                  Cfg := Fusa.Config.Load (Dir);
               exception
                  when Fusa.Config.No_Config_Error =>
                     return Emit_Runtime_Error
                       (Rest, "metrics", "no-config", "no .fusa.json found in " & Dir);
                  when Fusa.Config.Invalid_Config_Error =>
                     return Emit_Runtime_Error
                       (Rest, "metrics", "invalid-config", "invalid .fusa.json in " & Dir);
               end;

               declare
                  Files        : constant String_List :=
                    Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
                  Findings     : constant Finding_List := Fusa.Engine.Run_All (Dir, Files);
                  Dup          : Finding_List;
                  Reqs         : constant Fusa.Config.Requirement_List :=
                    Fusa.Config.Load_Requirements (Dir, Dup);
                  Comp_Results : constant Fusa.Comp.Comp_Result_List :=
                    Fusa.Comp.Analyze (Dir, Files, 10);
                  Snap         : Fusa.Config.Metric_Snapshot;
               begin
                  for F of Findings loop
                     case F.Severity is
                        when Error   => Snap.Check_Errors := Snap.Check_Errors + 1;
                        when Warning => Snap.Check_Warnings := Snap.Check_Warnings + 1;
                        when Info    => Snap.Check_Infos := Snap.Check_Infos + 1;
                     end case;
                  end loop;
                  for C of Comp_Results loop
                     if C.Exceeds_Threshold then
                        Snap.Comp_Violations := Snap.Comp_Violations + 1;
                     end if;
                  end loop;
                  Snap.Total_Reqs := Natural (Reqs.Length);
                  Snap.At_Time    := To_Unbounded_String (Fusa.Report.Now_Rfc3339);

                  declare
                     Snapshots : Fusa.Config.Metric_Snapshot_List := Fusa.Config.Load_Metrics (Dir);
                  begin
                     Snapshots.Append (Snap);
                     Fusa.Config.Save_Metrics (Dir, Snapshots);
                     Ada.Text_IO.Put_Line
                       ("recorded snapshot to " &
                          Fusa.Files.Join (Dir, Fusa.Config.Metrics_File) & " (" &
                          Trim_Img (Natural (Snapshots.Length)) & " total)");
                  end;
               end;
            end;
            return Exit_Ok;
         end if;

         declare
            Snapshots : constant Fusa.Config.Metric_Snapshot_List := Fusa.Config.Load_Metrics (Dir);
         begin
            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "metrics");
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
                  Emit (Rest, Fusa.Json.Writer.To_String (W));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for S of Snapshots loop
                     Append (Buf, To_String (S.At_Time) & ": reqs=" & Trim_Img (S.Total_Reqs) &
                               " errors=" & Trim_Img (S.Check_Errors) &
                               " warnings=" & Trim_Img (S.Check_Warnings) &
                               " compViolations=" & Trim_Img (S.Comp_Violations) & ASCII.LF);
                  end loop;
                  Append (Buf, Trim_Img (Natural (Snapshots.Length)) & " snapshots");
                  Emit (Rest, To_String (Buf));
               end;
            end if;
         end;
         return Exit_Ok;
      end;
   end Cmd_Metrics;

   ----------------------------------------------------------------------
   --  sign
   ----------------------------------------------------------------------

   function Resolve_Key (Args : String_List) return String is
      Key_Str  : constant String := Flag_Value (Args, "--key", "");
      Key_File : constant String := Flag_Value (Args, "--key-file", "");
   begin
      if Key_File'Length > 0 then
         return Fusa.Files.Read_File (Key_File);
      end if;
      return Key_Str;
   end Resolve_Key;

   --  fusa:req REQ-093
   function Cmd_Sign (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: sign: missing subcommand (sign|verify)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;
         if Verb /= "sign" and then Verb /= "verify" then
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: sign: unknown subcommand '" & Verb & "' (expected sign|verify)");
            return Exit_Usage;
         end if;

         declare
            File_Path : Unbounded_String := Null_Unbounded_String;
         begin
            declare
               I : Positive := 1;
            begin
               while I <= Natural (Rest.Length) loop
                  declare
                     A : constant String := Rest.Element (I);
                  begin
                     if A = "--dir" or else A = "--key" or else A = "--key-file"
                       or else A = "--sig"
                     then
                        I := I + 2;
                     elsif A'Length > 0 and then A (A'First) /= '-' then
                        if Length (File_Path) = 0 then
                           File_Path := To_Unbounded_String (A);
                        end if;
                        I := I + 1;
                     else
                        I := I + 1;
                     end if;
                  end;
               end loop;
            end;

            if Length (File_Path) = 0 then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "ada-FuSa: sign " & Verb & ": requires <file>");
               return Exit_Usage;
            end if;

            declare
               Key : constant String := Resolve_Key (Rest);
            begin
               if Key'Length = 0 then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: sign " & Verb & ": requires --key <key> or --key-file <path>");
                  return Exit_Usage;
               end if;

               if not Fusa.Files.Exists (To_String (File_Path)) then
                  return Emit_Runtime_Error
                    (Rest, "sign", "no-file", "file not found: " & To_String (File_Path));
               end if;

               declare
                  Content : constant String := Fusa.Files.Read_File (To_String (File_Path));
                  Sig     : constant String := Fusa.Hmac.Sha256_Hex (Key, Content);
               begin
                  if Verb = "sign" then
                     declare
                        Sig_Path : constant String :=
                          Flag_Value (Rest, "--sig", To_String (File_Path) & ".sig");
                     begin
                        Fusa.Files.Write_File (Sig_Path, "sha256-hmac:" & Sig & ASCII.LF);
                        Ada.Text_IO.Put_Line ("wrote " & Sig_Path);
                     end;
                     return Exit_Ok;
                  else --  "verify"
                     declare
                        Sig_Path : constant String :=
                          Flag_Value (Rest, "--sig", To_String (File_Path) & ".sig");
                     begin
                        if not Fusa.Files.Exists (Sig_Path) then
                           return Emit_Runtime_Error
                             (Rest, "sign", "no-signature",
                              "signature file not found: " & Sig_Path);
                        end if;
                        declare
                           Stored_Raw : constant String := Fusa.Files.Read_File (Sig_Path);
                           Prefix     : constant String := "sha256-hmac:";
                           Stored     : Unbounded_String := Null_Unbounded_String;
                           Last       : Natural := Stored_Raw'Last;
                        begin
                           --  Ada.Strings.Fixed.Trim's blank set is space
                           --  only, not LF/CR -- Write_File always appends
                           --  a trailing ASCII.LF, so that must be
                           --  stripped explicitly or every verify would
                           --  spuriously fail.
                           while Last >= Stored_Raw'First
                             and then (Stored_Raw (Last) = ASCII.LF
                                       or else Stored_Raw (Last) = ASCII.CR
                                       or else Stored_Raw (Last) = ' ')
                           loop
                              Last := Last - 1;
                           end loop;
                           if Last >= Stored_Raw'First
                             and then Last - Stored_Raw'First + 1 >= Prefix'Length
                             and then Stored_Raw (Stored_Raw'First .. Stored_Raw'First +
                                                     Prefix'Length - 1) = Prefix
                           then
                              Stored := To_Unbounded_String
                                (Stored_Raw (Stored_Raw'First + Prefix'Length .. Last));
                           end if;
                           --  Constant-time compare (CWE-208): a plain
                           --  "=" here would leak, via comparison time,
                           --  how many leading hex characters of an
                           --  attacker-supplied .sig file match the true
                           --  signature.
                           if Fusa.Hmac.Constant_Time_Equal (To_String (Stored), Sig) then
                              Ada.Text_IO.Put_Line ("OK: signature matches");
                              return Exit_Ok;
                           else
                              Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Standard_Error,
                                 "FAILED: signature does not match");
                              return Exit_Gate_Fail;
                           end if;
                        end;
                     end;
                  end if;
               end;
            end;
         end;
      end;
   end Cmd_Sign;

   ----------------------------------------------------------------------
   --  hooks
   ----------------------------------------------------------------------

   Hook_Marker : constant String := "# installed by ada-FuSa (adafusa hooks install)";

   --  Regression: the chmod() return code used to be discarded
   --  (pragma Unreferenced), so a failure (e.g. a read-only filesystem,
   --  or the file having vanished between Write_File and this call) was
   --  silently ignored -- `hooks install` would report success and leave
   --  a hook that git silently skips because it isn't actually
   --  executable. Returns True on success.
   function Make_Executable (Path : String) return Boolean is
      function C_Chmod
        (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int) return Interfaces.C.int;
      pragma Import (C, C_Chmod, "chmod");
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Result : Interfaces.C.int;
   begin
      Result := C_Chmod (C_Path, 8#755#);
      Interfaces.C.Strings.Free (C_Path);
      return Result = 0;
   end Make_Executable;

   --  fusa:req REQ-092
   function Cmd_Hooks (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: hooks: missing subcommand (install|remove)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;
         declare
            Dir       : constant String := Dir_Of (Rest);
            Hooks_Dir : constant String := Fusa.Files.Join (Dir, ".git/hooks");
            Hook_Path : constant String := Fusa.Files.Join (Hooks_Dir, "pre-commit");
         begin
            if Verb = "install" then
               if not Fusa.Files.Is_Directory (Fusa.Files.Join (Dir, ".git")) then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: hooks install: " & Dir &
                       " is not a git repository (no .git directory)");
                  return Exit_Runtime;
               end if;
               if Fusa.Files.Exists (Hook_Path) then
                  declare
                     Existing : constant String := Fusa.Files.Read_File (Hook_Path);
                  begin
                     if Ada.Strings.Fixed.Index (Existing, Hook_Marker) = 0 then
                        Ada.Text_IO.Put_Line
                          (Ada.Text_IO.Standard_Error,
                           "ada-FuSa: hooks install: " & Hook_Path &
                             " already exists and was not installed by ada-FuSa -- " &
                             "remove it manually first");
                        return Exit_Runtime;
                     end if;
                  end;
               end if;
               if not Fusa.Files.Is_Directory (Hooks_Dir) then
                  Ada.Directories.Create_Path (Hooks_Dir);
               end if;
               Fusa.Files.Write_File
                 (Hook_Path,
                  "#!/bin/sh" & ASCII.LF &
                    Hook_Marker & ASCII.LF &
                    "adafusa check --strict || exit 1" & ASCII.LF);
               if not Make_Executable (Hook_Path) then
                  return Emit_Runtime_Error
                    (Args, "hooks", "internal",
                     "failed to make " & Hook_Path & " executable");
               end if;
               Ada.Text_IO.Put_Line ("installed " & Hook_Path);
               return Exit_Ok;

            elsif Verb = "remove" then
               if not Fusa.Files.Exists (Hook_Path) then
                  Ada.Text_IO.Put_Line ("no pre-commit hook installed at " & Hook_Path);
                  return Exit_Ok;
               end if;
               declare
                  Existing : constant String := Fusa.Files.Read_File (Hook_Path);
               begin
                  if Ada.Strings.Fixed.Index (Existing, Hook_Marker) = 0 then
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "ada-FuSa: hooks remove: " & Hook_Path &
                          " was not installed by ada-FuSa -- refusing to remove it");
                     return Exit_Runtime;
                  end if;
               end;
               Ada.Directories.Delete_File (Hook_Path);
               Ada.Text_IO.Put_Line ("removed " & Hook_Path);
               return Exit_Ok;

            else
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error,
                  "ada-FuSa: hooks: unknown subcommand '" & Verb &
                    "' (expected install|remove)");
               return Exit_Usage;
            end if;
         end;
      end;
   end Cmd_Hooks;

   ----------------------------------------------------------------------
   --  standards gap-report commands (do178/iso26262/iso21434/iec61508/
   --  iec62443/unece/slsa) -- spec section 9.2/9.3.
   --
   --  ada-FuSa has no way to automatically determine whether a project
   --  actually satisfies a given safety/security standard's objectives --
   --  that is a human assessor's judgement call backed by real evidence.
   --  These commands therefore follow the same input-file-driven pattern
   --  as hara/tara: scaffold a starter template on first run, then on
   --  subsequent runs load/validate/render whatever assessment a human
   --  has recorded in `.fusa-<standard>-objectives.json`. They gate ONLY
   --  on structural validation errors (a missing "id"), never on the
   --  presence of "gap"-status objectives -- a standards gap report is a
   --  normal, expected artifact of in-progress compliance work, not a
   --  pass/fail check in itself.
   ----------------------------------------------------------------------

   --  fusa:req REQ-097
   function Cmd_Gap_Report
     (Args : String_List; Cmd_Name, Standard_Id : String;
      Starter : Fusa.Config.Gap_Objective_List) return Integer
   is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: " & Cmd_Name & ": unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Gap_Objectives_Exist (Dir, Standard_Id) then
         Fusa.Config.Scaffold_Gap_Objectives (Dir, Standard_Id, Starter);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Gap_Objectives_File (Standard_Id)) &
              " (template) -- record your " & Standard_Id &
              " objective assessment and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings   : Finding_List;
         Objectives : constant Fusa.Config.Gap_Objective_List :=
           Fusa.Config.Load_Gap_Objectives (Dir, Standard_Id, Findings);
         Satisfied, Partial, Gaps : Natural := 0;
      begin
         for O of Objectives loop
            declare
               S : constant String := To_String (O.Status);
            begin
               if S = "satisfied" then
                  Satisfied := Satisfied + 1;
               elsif S = "partial" then
                  Partial := Partial + 1;
               elsif S = "gap" then
                  Gaps := Gaps + 1;
               end if;
            end;
         end loop;

         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               --  §3.1: the closed `kind` enum's gap-report value is the
               --  literal string "gap-report" for every standard, NOT
               --  "<standard>-gap-report" -- py-FuSa shipped this exact
               --  mistake and had to fix it (spec change history, issue #1).
               Fusa.Report.Write_Header (W, "gap-report");
               W.Field ("standard", Standard_Id);
               W.Key ("objectives");
               W.Array_Start;
               for O of Objectives loop
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
               --  §9.3 canonical schema: "summary" is the objectives
               --  tally (total/satisfied/partial/gaps), NOT the generic
               --  errors/warnings/infos tally every other JSON report
               --  uses -- Write_Summary's default Key would collide with
               --  it, so the config-validation findings below (GAP001/
               --  GAP002 etc., e.g. a malformed objectives file) get a
               --  distinctly-named "findingsSummary" instead.
               W.Key ("summary");
               W.Object_Start;
               W.Field ("total", Natural (Objectives.Length));
               W.Field ("satisfied", Satisfied);
               W.Field ("partial", Partial);
               W.Field ("gaps", Gaps);
               W.Object_End;
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings, "findingsSummary");
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         else
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for O of Objectives loop
                  Append (Buf, To_String (O.Id) & ": " & To_String (O.Title) &
                            " (" & To_String (O.Status) & ")" & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Natural (Objectives.Length)) & " objectives (" &
                         Trim_Img (Satisfied) & " satisfied, " & Trim_Img (Partial) &
                         " partial, " & Trim_Img (Gaps) & " gaps), " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings");
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Gap_Report;

   function Empty_Objective_Starter return Fusa.Config.Gap_Objective_List is
      Empty : Fusa.Config.Gap_Objective_List;
   begin
      return Empty;
   end Empty_Objective_Starter;

   --  A small, non-authoritative starter reference for DO-178C: it uses
   --  ada-FuSa's OWN id scheme ("DO178-<AREA>-<N>") rather than RTCA's
   --  official Annex A table/objective numbers, since this tool has not
   --  verified those exact ids/wording against the official DO-178C text
   --  and must not present a fabricated transcription as authoritative.
   --  Treat this strictly as a checklist starting point -- replace/extend
   --  it with your project's actual PSAC/SOI-derived objectives.
   function Do178_Starter return Fusa.Config.Gap_Objective_List is
      L : Fusa.Config.Gap_Objective_List;

      procedure Add (Id, Title, Clause : String) is
         O : Fusa.Config.Gap_Objective;
      begin
         O.Id     := To_Unbounded_String (Id);
         O.Title  := To_Unbounded_String (Title);
         O.Clause := To_Unbounded_String (Clause);
         O.Status := To_Unbounded_String ("gap");
         L.Append (O);
      end Add;
   begin
      Add ("DO178-PLAN-1", "Software planning process documented (PSAC/SDP/SVP/SCMP/SQAP)",
           "DO-178C Section 4 (non-authoritative reference)");
      Add ("DO178-REQ-1", "High-level requirements developed and traced to system requirements",
           "DO-178C Section 5.1 (non-authoritative reference)");
      Add ("DO178-DES-1", "Software design (low-level requirements/architecture) developed and traced",
           "DO-178C Section 5.2 (non-authoritative reference)");
      Add ("DO178-CODE-1", "Source code developed per coding standards and traced to design",
           "DO-178C Section 5.3 (non-authoritative reference)");
      Add ("DO178-VER-1", "Reviews and analyses performed on requirements, design, and code",
           "DO-178C Section 6.3 (non-authoritative reference)");
      Add ("DO178-TEST-1", "Requirements-based test cases developed and executed",
           "DO-178C Section 6.4 (non-authoritative reference)");
      Add ("DO178-COV-1", "Structural coverage analysis performed on the test suite",
           "DO-178C Section 6.4.4 (non-authoritative reference)");
      Add ("DO178-CM-1", "Configuration management process controls all life-cycle data",
           "DO-178C Section 7 (non-authoritative reference)");
      Add ("DO178-QA-1", "Software quality assurance process conducted",
           "DO-178C Section 8 (non-authoritative reference)");
      return L;
   end Do178_Starter;

   function Cmd_Do178 (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "do178", "do178c", Do178_Starter));

   function Cmd_Iso26262 (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "iso26262", "iso26262", Empty_Objective_Starter));

   function Cmd_Iso21434 (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "iso21434", "iso21434", Empty_Objective_Starter));

   function Cmd_Iec61508 (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "iec61508", "iec61508", Empty_Objective_Starter));

   function Cmd_Iec62443 (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "iec62443", "iec62443-4-1", Empty_Objective_Starter));

   function Cmd_Unece (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "unece", "unece-r155", Empty_Objective_Starter));

   function Cmd_Slsa (Args : String_List) return Integer is
     (Cmd_Gap_Report (Args, "slsa", "slsa", Empty_Objective_Starter));

   ----------------------------------------------------------------------
   --  verify -- evidence manifest (#26)
   ----------------------------------------------------------------------

   --  fusa:req REQ-099
   function Cmd_Verify (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: verify: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Verify_Exists (Dir) then
         Fusa.Config.Scaffold_Verify (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Verify_File) &
              " (template) -- record your verification suite results and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings     : Finding_List;
         Passed, Failed : Natural;
         Suites       : constant Fusa.Config.Verify_Suite_List :=
           Fusa.Config.Load_Verify (Dir, Findings, Passed, Failed);
      begin
         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               --  §13 canonical direction: {passed, failed, suites:[{name,
               --  passed, failed, tests:[{name,result}]}]}.
               Fusa.Report.Write_Header (W, "verify-report");
               W.Field ("passed", Passed);
               W.Field ("failed", Failed);
               W.Key ("suites");
               W.Array_Start;
               for S of Suites loop
                  declare
                     Suite_Passed, Suite_Failed : Natural := 0;
                  begin
                     for T of S.Tests loop
                        if To_String (T.Result) = "PASS" then
                           Suite_Passed := Suite_Passed + 1;
                        elsif To_String (T.Result) = "FAIL" then
                           Suite_Failed := Suite_Failed + 1;
                        end if;
                     end loop;
                     W.Object_Start;
                     W.Field ("name", To_String (S.Name));
                     W.Field ("passed", Suite_Passed);
                     W.Field ("failed", Suite_Failed);
                     W.Key ("tests");
                     W.Array_Start;
                     for T of S.Tests loop
                        W.Object_Start;
                        W.Field ("name", To_String (T.Name));
                        W.Field_If_Non_Blank ("result", To_String (T.Result));
                        W.Object_End;
                     end loop;
                     W.Array_End;
                     W.Object_End;
                  end;
               end loop;
               W.Array_End;
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings);
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         else
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               for S of Suites loop
                  Append (Buf, To_String (S.Name) & ":" & ASCII.LF);
                  for T of S.Tests loop
                     Append (Buf, "  " & To_String (T.Name) & " [" & To_String (T.Result) &
                               "]" & ASCII.LF);
                  end loop;
               end loop;
               Append (Buf, Trim_Img (Passed) & " passed, " & Trim_Img (Failed) & " failed, " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings");
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) or else Failed > 0 then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Verify;

   ----------------------------------------------------------------------
   --  diff -- compare two report documents by fingerprint (#26)
   ----------------------------------------------------------------------

   type Diff_Item is record
      Fingerprint : Unbounded_String;
      Rule_Id     : Unbounded_String;
      Severity    : Unbounded_String;
      Message     : Unbounded_String;
   end record;

   package Diff_Item_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Diff_Item);
   subtype Diff_Item_List is Diff_Item_Vectors.Vector;

   function Contains_Fingerprint (L : Diff_Item_List; Fp : String) return Boolean is
   begin
      for Item of L loop
         if To_String (Item.Fingerprint) = Fp then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Fingerprint;

   --  Raises Fusa.Json.Json_Error on malformed JSON; a document with no
   --  "findings" array (or one that isn't an array) yields an empty list
   --  rather than an error, mirroring the JSON accessors' own
   --  fail-safe-on-absent convention.
   function Parse_Report_Findings (Path : String) return Diff_Item_List is
      Result  : Diff_Item_List;
      Content : constant String := Fusa.Files.Read_File (Path);
      Root    : constant Fusa.Json.Value_Access := Fusa.Json.Parse (Content);
      Items   : constant Fusa.Json.Value_Access := Fusa.Json.Get_Array (Root, "findings");
   begin
      for I in 1 .. Fusa.Json.Array_Length (Items) loop
         declare
            Item : constant Fusa.Json.Value_Access := Fusa.Json.Array_Item (Items, I);
            D    : Diff_Item;
         begin
            D.Fingerprint := To_Unbounded_String (Fusa.Json.Get_String (Item, "fingerprint"));
            D.Rule_Id     := To_Unbounded_String (Fusa.Json.Get_String (Item, "ruleId"));
            D.Severity    := To_Unbounded_String (Fusa.Json.Get_String (Item, "severity"));
            D.Message     := To_Unbounded_String (Fusa.Json.Get_String (Item, "message"));
            Result.Append (D);
         end;
      end loop;
      return Result;
   end Parse_Report_Findings;

   --  §13 canonical direction: added/removed are bare fingerprint strings,
   --  not full finding objects -- severity is still used internally (see
   --  Cmd_Diff) to decide the exit code, just not repeated in the output.
   procedure Write_Fingerprints (W : in out Fusa.Json.Writer.Instance; Items : Diff_Item_List) is
   begin
      W.Array_Start;
      for Item of Items loop
         W.Value (To_String (Item.Fingerprint));
      end loop;
      W.Array_End;
   end Write_Fingerprints;

   function From_Findings (Findings : Finding_List) return Diff_Item_List is
      Result : Diff_Item_List;
   begin
      for F of Findings loop
         declare
            D : Diff_Item;
         begin
            D.Fingerprint := F.Fingerprint;
            D.Rule_Id     := F.Rule_Id;
            D.Severity    := To_Unbounded_String (Image (F.Severity));
            D.Message     := F.Message;
            Result.Append (D);
         end;
      end loop;
      return Result;
   end From_Findings;

   --  fusa:req REQ-100
   function Cmd_Diff (Args : String_List) return Integer is
      Dir           : constant String := Dir_Of (Args);
      Format        : constant String := Flag_Value (Args, "--format", "text");
      Strict        : constant Boolean := Has_Flag (Args, "--strict");
      Baseline_Path : constant String := Flag_Value (Args, "--baseline", "");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: diff: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if Baseline_Path'Length = 0 then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: diff: requires --baseline <file>");
         return Exit_Usage;
      end if;

      if not Fusa.Files.Exists (Baseline_Path) then
         return Emit_Runtime_Error
           (Args, "diff", "not-found", "baseline report not found: " & Baseline_Path);
      end if;

      declare
         List_A : Diff_Item_List;
      begin
         begin
            List_A := Parse_Report_Findings (Baseline_Path);
         exception
            when Fusa.Json.Json_Error =>
               return Emit_Runtime_Error
                 (Args, "diff", "invalid-report", "malformed JSON in " & Baseline_Path);
         end;

         --  The "current" side is always a live `check` run, mirroring how
         --  `report` re-runs analysis rather than reading a cached file --
         --  a baseline is the only thing diff ever reads from disk.
         declare
            Cfg : Fusa.Config.Project_Config;
         begin
            begin
               Cfg := Fusa.Config.Load (Dir);
            exception
               when Fusa.Config.No_Config_Error =>
                  return Emit_Runtime_Error
                    (Args, "diff", "no-config", "no .fusa.json found in " & Dir);
               when Fusa.Config.Invalid_Config_Error =>
                  return Emit_Runtime_Error
                    (Args, "diff", "invalid-config", "invalid .fusa.json in " & Dir);
            end;

            declare
               Files          : constant String_List :=
                 Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
               Live_Findings  : Finding_List := Fusa.Engine.Run_All (Dir, Files);
            begin
               if Fusa.Config.Dispositions_Exist (Dir) then
                  declare
                     Disps           : constant Fusa.Config.Disposition_List :=
                       Fusa.Config.Load_Dispositions (Dir);
                     Orphan_Findings : Finding_List;
                  begin
                     Fusa.Config.Apply_Dispositions (Live_Findings, Disps, Orphan_Findings);
                     for F of Orphan_Findings loop
                        Live_Findings.Append (F);
                     end loop;
                  end;
               end if;

               declare
                  List_B : constant Diff_Item_List := From_Findings (Live_Findings);
                  Added, Removed : Diff_Item_List;
                  Has_Error_Add  : Boolean := False;
               begin
                  for Item of List_B loop
                     if not Contains_Fingerprint (List_A, To_String (Item.Fingerprint)) then
                        Added.Append (Item);
                        if To_String (Item.Severity) = "ERROR" then
                           Has_Error_Add := True;
                        end if;
                     end if;
                  end loop;
                  for Item of List_A loop
                     if not Contains_Fingerprint (List_B, To_String (Item.Fingerprint)) then
                        Removed.Append (Item);
                     end if;
                  end loop;

                  if Format = "json" then
                     declare
                        W : Fusa.Json.Writer.Instance;
                     begin
                        W.Object_Start;
                        --  §13 canonical direction: {added:[fingerprint],
                        --  removed:[fingerprint], unchanged:N}.
                        Fusa.Report.Write_Header (W, "diff-report");
                        W.Key ("added");
                        Write_Fingerprints (W, Added);
                        W.Key ("removed");
                        Write_Fingerprints (W, Removed);
                        W.Field ("unchanged", Natural (List_B.Length) - Natural (Added.Length));
                        W.Object_End;
                        Emit (Args, Fusa.Json.Writer.To_String (W));
                     end;
                  else
                     declare
                        Buf : Unbounded_String := Null_Unbounded_String;
                     begin
                        for Item of Added loop
                           Append (Buf, "+ [" & To_String (Item.Severity) & "] " &
                                     To_String (Item.Rule_Id) & " " & To_String (Item.Message) &
                                     ASCII.LF);
                        end loop;
                        for Item of Removed loop
                           Append (Buf, "- [" & To_String (Item.Severity) & "] " &
                                     To_String (Item.Rule_Id) & " " & To_String (Item.Message) &
                                     ASCII.LF);
                        end loop;
                        Append (Buf, Trim_Img (Natural (Added.Length)) & " added, " &
                                  Trim_Img (Natural (Removed.Length)) & " removed, " &
                                  Trim_Img (Natural (List_B.Length) - Natural (Added.Length)) &
                                  " unchanged");
                        Emit (Args, To_String (Buf));
                     end;
                  end if;

                  --  .fusa.json's "strict" used to only be honoured by
                  --  check/cyber.
                  if Has_Error_Add
                    or else ((Strict or else Cfg.Strict) and then Natural (Added.Length) > 0)
                  then
                     return Exit_Gate_Fail;
                  end if;
                  return Exit_Ok;
               end;
            end;
         end;
      end;
   end Cmd_Diff;

   ----------------------------------------------------------------------
   --  badge -- SVG status badge (#26)
   ----------------------------------------------------------------------

   --  fusa:req REQ-101
   function Cmd_Badge (Args : String_List) return Integer is
      Dir             : constant String := Dir_Of (Args);
      Label           : constant String := Flag_Value (Args, "--label", "fusa");
      Message_Given   : constant Boolean := Has_Flag (Args, "--message");
      Message_Flag    : constant String := Flag_Value (Args, "--message", "");
      Color_Given     : constant Boolean := Has_Flag (Args, "--color");
      Color_Flag      : constant String := Flag_Value (Args, "--color", "");
   begin
      --  Explicit --message/--color skips running check entirely, so
      --  `badge` can also render an arbitrary custom status (e.g. a
      --  version badge) without needing a project to analyse.
      if Message_Given or else Color_Given then
         Emit (Args, Fusa.Badge.Render_Svg
                 (Label,
                  (if Message_Given then Message_Flag else "unknown"),
                  (if Color_Given then Color_Flag else "#9f9f9f")));
         return Exit_Ok;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "badge", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "badge", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files        : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Findings     : Finding_List := Fusa.Engine.Run_All (Dir, Files);
            Errors, Warnings : Natural := 0;
         begin
            if Fusa.Config.Dispositions_Exist (Dir) then
               declare
                  Disps           : constant Fusa.Config.Disposition_List :=
                    Fusa.Config.Load_Dispositions (Dir);
                  Orphan_Findings : Finding_List;
               begin
                  Fusa.Config.Apply_Dispositions (Findings, Disps, Orphan_Findings);
                  for F of Orphan_Findings loop
                     Findings.Append (F);
                  end loop;
               end;
            end if;

            for F of Findings loop
               if F.Disposition = Open or else F.Disposition = Rejected then
                  case F.Severity is
                     when Error   => Errors   := Errors + 1;
                     when Warning => Warnings := Warnings + 1;
                     when Info    => null;
                  end case;
               end if;
            end loop;

            if Errors > 0 then
               Emit (Args, Fusa.Badge.Render_Svg
                       (Label, Trim_Img (Errors) & " errors", "#e05d44"));
            elsif Warnings > 0 then
               Emit (Args, Fusa.Badge.Render_Svg
                       (Label, Trim_Img (Warnings) & " warnings", "#dfb317"));
            else
               Emit (Args, Fusa.Badge.Render_Svg (Label, "passing", "#4c1"));
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Badge;

   ----------------------------------------------------------------------
   --  boundary -- package/unit dependency graph (#26)
   ----------------------------------------------------------------------

   function Mermaid_Id (Name : String) return String is
      Result : String (Name'Range);
   begin
      for I in Name'Range loop
         Result (I) := (if Name (I) = '.' then '_' else Name (I));
      end loop;
      return Result;
   end Mermaid_Id;

   --  fusa:req REQ-103
   function Cmd_Boundary (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "dot");
   begin
      if Format /= "dot" and then Format /= "mermaid" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: boundary: unsupported --format '" & Format &
            "' (supported: dot, mermaid)");
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
                 (Args, "boundary", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "boundary", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Nodes : constant Fusa.Deps.Dep_Node_List := Fusa.Deps.Analyze (Dir, Files);
            Buf   : Unbounded_String := Null_Unbounded_String;
         begin
            if Format = "mermaid" then
               Append (Buf, "graph TD" & ASCII.LF);
               for N of Nodes loop
                  Append (Buf, "  " & Mermaid_Id (To_String (N.Name)) & "[""" &
                            To_String (N.Name) & """]" & ASCII.LF);
               end loop;
               for N of Nodes loop
                  for D of N.Deps loop
                     Append (Buf, "  " & Mermaid_Id (To_String (N.Name)) & " --> " &
                               Mermaid_Id (D) & ASCII.LF);
                  end loop;
               end loop;
            else
               Append (Buf, "digraph Boundary {" & ASCII.LF);
               for N of Nodes loop
                  Append (Buf, "  """ & To_String (N.Name) & """;" & ASCII.LF);
               end loop;
               for N of Nodes loop
                  for D of N.Deps loop
                     Append (Buf, "  """ & To_String (N.Name) & """ -> """ & D & """;" & ASCII.LF);
                  end loop;
               end loop;
               Append (Buf, "}" & ASCII.LF);
            end if;
            Emit (Args, To_String (Buf));
            return Exit_Ok;
         end;
      end;
   end Cmd_Boundary;

   ----------------------------------------------------------------------
   --  impact -- change-impact analysis given a file list (#26)
   ----------------------------------------------------------------------

   --  fusa:req REQ-104
   function Cmd_Impact (Args : String_List) return Integer is
      Dir     : constant String := Dir_Of (Args);
      Format  : constant String := Flag_Value (Args, "--format", "text");
      Changed : String_List;
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: impact: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      declare
         I : Positive := 1;
      begin
         while I <= Natural (Args.Length) loop
            declare
               A : constant String := Args.Element (I);
            begin
               if A = "--dir" or else A = "--format" or else A = "--output" then
                  I := I + 2;
               elsif A'Length > 0 and then A (A'First) /= '-' then
                  Changed.Append (A);
                  I := I + 1;
               else
                  I := I + 1;
               end if;
            end;
         end loop;
      end;

      if Changed.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: impact: requires at least one changed file");
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
                 (Args, "impact", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "impact", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Nodes    : constant Fusa.Deps.Dep_Node_List := Fusa.Deps.Analyze (Dir, Files);
            Impacted : Fusa.Deps.Dep_Node_List;
         begin
            for C of Changed loop
               declare
                  Unit : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, C);
               begin
                  if Length (Unit.Name) > 0 then
                     for R of Fusa.Deps.Reverse_Reachable (Nodes, To_String (Unit.Name)) loop
                        declare
                           Already : Boolean := False;
                        begin
                           for Ex of Impacted loop
                              if To_String (Ex.Name) = To_String (R.Name) then
                                 Already := True;
                                 exit;
                              end if;
                           end loop;
                           if not Already then
                              Impacted.Append (R);
                           end if;
                        end;
                     end loop;
                  end if;
               end;
            end loop;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "impact-report");
                  W.Key ("changed");
                  W.Array_Start;
                  for C of Changed loop
                     declare
                        Unit : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, C);
                     begin
                        W.Object_Start;
                        W.Field ("file", C);
                        W.Field_If_Non_Blank ("unit", To_String (Unit.Name));
                        W.Object_End;
                     end;
                  end loop;
                  W.Array_End;
                  W.Key ("impacted");
                  W.Array_Start;
                  for N of Impacted loop
                     W.Object_Start;
                     W.Field ("name", To_String (N.Name));
                     W.Key ("files");
                     W.Array_Start;
                     for F of N.Files loop
                        W.Value (F);
                     end loop;
                     W.Array_End;
                     W.Object_End;
                  end loop;
                  W.Array_End;
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for C of Changed loop
                     declare
                        Unit : constant Fusa.Deps.Dep_Node := Fusa.Deps.Find_By_File (Nodes, C);
                     begin
                        if Length (Unit.Name) > 0 then
                           Append (Buf, C & " -> " & To_String (Unit.Name) & ASCII.LF);
                        else
                           Append (Buf, C & " -> (not a recognised project unit)" & ASCII.LF);
                        end if;
                     end;
                  end loop;
                  Append (Buf, Trim_Img (Natural (Impacted.Length)) & " impacted unit(s):" &
                            ASCII.LF);
                  for N of Impacted loop
                     Append (Buf, "  " & To_String (N.Name) & ASCII.LF);
                  end loop;
                  Emit (Args, To_String (Buf));
               end;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Impact;

   ----------------------------------------------------------------------
   --  coupling -- structural fan-in/fan-out coupling metric (#26)
   ----------------------------------------------------------------------

   --  fusa:req REQ-105
   function Cmd_Coupling (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: coupling: unsupported --format '" & Format &
            "' (supported: text, json)");
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
                 (Args, "coupling", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "coupling", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Nodes : constant Fusa.Deps.Dep_Node_List := Fusa.Deps.Analyze (Dir, Files);

            --  Direct (one-hop) fan-in: how many other units name this one
            --  in their own Deps -- unlike `impact`'s Reverse_Reachable,
            --  coupling is a per-unit structural metric, not a transitive
            --  change-impact set.
            function Fan_In (Name : String) return Natural is
               Count : Natural := 0;
            begin
               for N of Nodes loop
                  for D of N.Deps loop
                     if D = Name then
                        Count := Count + 1;
                        exit;
                     end if;
                  end loop;
               end loop;
               return Count;
            end Fan_In;

            --  Ordered by descending total coupling (most-coupled first --
            --  the units most worth a closer manual review), via a plain
            --  insertion sort since the unit count is small.
            Order : array (1 .. Natural (Nodes.Length)) of Positive;
            Totals : array (1 .. Natural (Nodes.Length)) of Natural;
         begin
            for I in Order'Range loop
               Order (I) := I;
               Totals (I) :=
                 Natural (Nodes.Element (I).Deps.Length) + Fan_In (To_String (Nodes.Element (I).Name));
            end loop;
            for I in Order'First + 1 .. Order'Last loop
               declare
                  Key_Idx   : constant Positive := Order (I);
                  Key_Total : constant Natural := Totals (Key_Idx);
                  J         : Integer := I - 1;
               begin
                  while J >= Order'First and then Totals (Order (J)) < Key_Total loop
                     Order (J + 1) := Order (J);
                     J := J - 1;
                  end loop;
                  Order (J + 1) := Key_Idx;
               end;
            end loop;

            if Format = "json" then
               declare
                  W          : Fusa.Json.Writer.Instance;
                  Edge_Count : Natural := 0;
               begin
                  for N of Nodes loop
                     Edge_Count := Edge_Count + Natural (N.Deps.Length);
                  end loop;

                  W.Object_Start;
                  --  §13 canonical direction: graph {modules, edges, metrics}
                  --  -- deliberately NOT the flat finding-list-shaped
                  --  "units[]" array an earlier revision of this command
                  --  used (the spec explicitly warns against deepening
                  --  investment in that shape).
                  Fusa.Report.Write_Header (W, "coupling-report");
                  W.Key ("modules");
                  W.Array_Start;
                  for Idx of Order loop
                     declare
                        N : constant Fusa.Deps.Dep_Node := Nodes.Element (Idx);
                        In_C  : constant Natural := Fan_In (To_String (N.Name));
                        Out_C : constant Natural := Natural (N.Deps.Length);
                     begin
                        W.Object_Start;
                        W.Field ("name", To_String (N.Name));
                        W.Field ("fanIn", In_C);
                        W.Field ("fanOut", Out_C);
                        W.Object_End;
                     end;
                  end loop;
                  W.Array_End;
                  W.Key ("edges");
                  W.Array_Start;
                  for N of Nodes loop
                     for D of N.Deps loop
                        W.Object_Start;
                        W.Field ("from", To_String (N.Name));
                        W.Field ("to", D);
                        W.Field ("weight", 1);
                        W.Object_End;
                     end loop;
                  end loop;
                  W.Array_End;
                  W.Key ("metrics");
                  W.Object_Start;
                  W.Field ("totalModules", Natural (Nodes.Length));
                  W.Field ("totalEdges", Edge_Count);
                  W.Object_End;
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for Idx of Order loop
                     declare
                        N : constant Fusa.Deps.Dep_Node := Nodes.Element (Idx);
                        In_C  : constant Natural := Fan_In (To_String (N.Name));
                        Out_C : constant Natural := Natural (N.Deps.Length);
                     begin
                        Append (Buf, To_String (N.Name) & ": fan-in=" & Trim_Img (In_C) &
                                  " fan-out=" & Trim_Img (Out_C) &
                                  " total=" & Trim_Img (In_C + Out_C) & ASCII.LF);
                     end;
                  end loop;
                  Append (Buf, Trim_Img (Natural (Nodes.Length)) & " units");
                  Emit (Args, To_String (Buf));
               end;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Coupling;

   ----------------------------------------------------------------------
   --  fmea -- design FMEA (#26)
   ----------------------------------------------------------------------

   function Csv_Field (S : String) return String is
      Needs_Quoting : Boolean := False;
   begin
      for C of S loop
         if C = ',' or else C = '"' or else C = ASCII.LF or else C = ASCII.CR then
            Needs_Quoting := True;
            exit;
         end if;
      end loop;
      if not Needs_Quoting then
         return S;
      end if;
      declare
         Buf : Unbounded_String := Null_Unbounded_String;
      begin
         Append (Buf, '"');
         for C of S loop
            if C = '"' then
               Append (Buf, """""");
            else
               Append (Buf, C);
            end if;
         end loop;
         Append (Buf, '"');
         return To_String (Buf);
      end;
   end Csv_Field;

   --  fusa:req REQ-106
   function Cmd_Fmea (Args : String_List) return Integer is
      Dir         : constant String := Dir_Of (Args);
      Format      : constant String := Flag_Value (Args, "--format", "text");
      Min_Cov_Str : constant String := Flag_Value (Args, "--min-coverage", "");
   begin
      if Format /= "text" and then Format /= "json" and then Format /= "csv" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: fmea: unsupported --format '" & Format &
            "' (supported: text, json, csv)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Fmea_Exists (Dir) then
         Fusa.Config.Scaffold_Fmea (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Fmea_File) &
              " (template) -- fill in your FMEA entries and re-run");
         return Exit_Ok;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "fmea-report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "fmea-report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Findings : Finding_List;
            Doc      : constant Fusa.Config.Fmea_Document := Fusa.Config.Load_Fmea (Dir, Findings);
            Entries  : Fusa.Config.Fmea_Entry_List renames Doc.Entries;

            --  summary.componentsInProject: the same denominator as
            --  trace --func-coverage (section 5, section 1.4.1) --
            --  public/exported functions/methods.
            Files       : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Funcs       : constant Fusa.Func_Scan.Func_List :=
              Fusa.Func_Scan.Scan_Public_Functions (Dir, Files);
            High_Priority : Natural := 0;
            Components_Analyzed  : constant Natural := Natural (Entries.Length);
            Components_In_Project : constant Natural :=
              (if Doc.Components_In_Project_Given then Doc.Components_In_Project
               else Natural (Funcs.Length));
            Coverage_Pct : constant Natural :=
              (if Components_In_Project = 0 then 100
               else Components_Analyzed * 100 / Components_In_Project);
            Min_Coverage : Natural := 0;
            Gate_Fail    : Boolean := False;
         begin
            for E of Entries loop
               if To_String (E.Action_Priority) = "high" then
                  High_Priority := High_Priority + 1;
               end if;
            end loop;

            if Min_Cov_Str'Length > 0 then
               begin
                  Min_Coverage := Natural'Value (Min_Cov_Str);
               exception
                  when Constraint_Error =>
                     Ada.Text_IO.Put_Line
                       (Ada.Text_IO.Standard_Error,
                        "ada-FuSa: fmea: --min-coverage must be a non-negative integer");
                     return Exit_Usage;
               end;
            end if;
            if Min_Coverage > 0 and then Coverage_Pct < Min_Coverage then
               Gate_Fail := True;
            end if;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  --  section 9.2: "summary" is the canonical coverage
                  --  block, NOT the generic errors/warnings/infos tally
                  --  every other JSON report uses -- that tally goes
                  --  under "findingsSummary" instead (same collision
                  --  gap-report/tara had, fixed the same way).
                  Fusa.Report.Write_Header (W, "fmea-report");
                  W.Field_If_Non_Blank ("ratingScale", To_String (Doc.Rating_Scale));
                  W.Key ("entries");
                  W.Array_Start;
                  for E of Entries loop
                     W.Object_Start;
                     W.Field ("id", To_String (E.Id));
                     W.Field_If_Non_Blank ("item", To_String (E.Item));
                     W.Field_If_Non_Blank ("file", To_String (E.File));
                     W.Field_If_Non_Blank ("failureMode", To_String (E.Failure_Mode));
                     W.Field_If_Non_Blank ("effect", To_String (E.Effect));
                     W.Field_If_Non_Blank ("cause", To_String (E.Cause));
                     W.Field ("severity", E.Severity);
                     W.Field ("occurrence", E.Occurrence);
                     W.Field ("detection", E.Detection);
                     W.Field_If_Non_Blank ("actionPriority", To_String (E.Action_Priority));
                     W.Field ("rpn", E.Rpn);
                     W.Key ("mitigations");
                     W.Array_Start;
                     for M of E.Mitigations loop
                        W.Value (M);
                     end loop;
                     W.Array_End;
                     W.Key ("requirementIds");
                     W.Array_Start;
                     for R of E.Requirement_Ids loop
                        W.Value (R);
                     end loop;
                     W.Array_End;
                     W.Object_End;
                  end loop;
                  W.Array_End;
                  W.Key ("summary");
                  W.Object_Start;
                  W.Field ("total", Components_Analyzed);
                  W.Field ("highPriority", High_Priority);
                  W.Field ("componentsAnalyzed", Components_Analyzed);
                  W.Field ("componentsInProject", Components_In_Project);
                  W.Field ("coveragePct", Coverage_Pct);
                  W.Object_End;
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings, "findingsSummary");
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            elsif Format = "csv" then
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  Append (Buf, "id,item,file,failureMode,effect,cause,severity,occurrence," &
                            "detection,actionPriority,rpn,mitigations" & ASCII.LF);
                  for E of Entries loop
                     declare
                        Mits_Joined : Unbounded_String := Null_Unbounded_String;
                     begin
                        for M of E.Mitigations loop
                           if Length (Mits_Joined) > 0 then
                              Append (Mits_Joined, "; ");
                           end if;
                           Append (Mits_Joined, M);
                        end loop;
                        Append (Buf, Csv_Field (To_String (E.Id)) & "," &
                                  Csv_Field (To_String (E.Item)) & "," &
                                  Csv_Field (To_String (E.File)) & "," &
                                  Csv_Field (To_String (E.Failure_Mode)) & "," &
                                  Csv_Field (To_String (E.Effect)) & "," &
                                  Csv_Field (To_String (E.Cause)) & "," &
                                  Trim_Img (E.Severity) & "," & Trim_Img (E.Occurrence) & "," &
                                  Trim_Img (E.Detection) & "," &
                                  Csv_Field (To_String (E.Action_Priority)) & "," &
                                  Trim_Img (E.Rpn) & "," &
                                  Csv_Field (To_String (Mits_Joined)) & ASCII.LF);
                     end;
                  end loop;
                  Emit (Args, To_String (Buf));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for E of Entries loop
                     Append (Buf, To_String (E.Id) & ": " & To_String (E.Failure_Mode) &
                               " (RPN=" & Trim_Img (E.Rpn) & ")" & ASCII.LF);
                  end loop;
                  Append (Buf, Trim_Img (Components_Analyzed) & " entries, " &
                            Trim_Img (Components_Analyzed) & "/" &
                            Trim_Img (Components_In_Project) &
                            " components analyzed (" & Trim_Img (Coverage_Pct) & "%), " &
                            Trim_Img (Natural (Findings.Length)) & " validation findings");
                  Emit (Args, To_String (Buf));
               end;
            end if;

            if Gate_Fail or else Fusa.Report.Has_Gate_Failure (Findings, False) then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Fmea;

   ----------------------------------------------------------------------
   --  safety-case -- GSN safety case (#26)
   ----------------------------------------------------------------------

   --  fusa:req REQ-107
   function Cmd_Safety_Case (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" and then Format /= "md"
        and then Format /= "mermaid"
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: safety-case: unsupported --format '" & Format &
            "' (supported: text, json, md, mermaid)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Safety_Case_Exists (Dir) then
         Fusa.Config.Scaffold_Safety_Case (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Safety_Case_File) &
              " (template) -- build your GSN argument and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings  : Finding_List;
         Root_Goal : Unbounded_String;
         Nodes     : constant Fusa.Config.Gsn_Node_List :=
           Fusa.Config.Load_Safety_Case (Dir, Findings, Root_Goal);

         function Find_Node (Id : String) return Fusa.Config.Gsn_Node is
            Empty : Fusa.Config.Gsn_Node;
         begin
            for N of Nodes loop
               if To_String (N.Id) = Id then
                  return N;
               end if;
            end loop;
            return Empty;
         end Find_Node;
      begin
         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               --  §13 canonical direction: {nodes:[{id,type,text}],
               --  edges:[{from,to,type}]} -- supportedBy/inContextOf move
               --  out of each node into a separate top-level edges array,
               --  rather than being embedded per-node as an earlier
               --  revision of this command did.
               Fusa.Report.Write_Header (W, "safety-case");
               W.Field_If_Non_Blank ("rootGoal", To_String (Root_Goal));
               W.Key ("nodes");
               W.Array_Start;
               for N of Nodes loop
                  W.Object_Start;
                  W.Field ("id", To_String (N.Id));
                  W.Field_If_Non_Blank ("type", To_String (N.Kind));
                  W.Field_If_Non_Blank ("text", To_String (N.Text));
                  W.Object_End;
               end loop;
               W.Array_End;
               W.Key ("edges");
               W.Array_Start;
               for N of Nodes loop
                  for R of N.Supported_By loop
                     W.Object_Start;
                     W.Field ("from", To_String (N.Id));
                     W.Field ("to", R);
                     W.Field ("type", "supportedBy");
                     W.Object_End;
                  end loop;
                  for R of N.In_Context_Of loop
                     W.Object_Start;
                     W.Field ("from", To_String (N.Id));
                     W.Field ("to", R);
                     W.Field ("type", "inContextOf");
                     W.Object_End;
                  end loop;
               end loop;
               W.Array_End;
               Fusa.Report.Write_Findings_Array (W, Findings);
               Fusa.Report.Write_Summary (W, Findings);
               W.Object_End;
               Emit (Args, Fusa.Json.Writer.To_String (W));
            end;
         elsif Format = "mermaid" then
            declare
               Buf : Unbounded_String := Null_Unbounded_String;
            begin
               Append (Buf, "graph TD" & ASCII.LF);
               for N of Nodes loop
                  declare
                     Kind : constant String := To_String (N.Kind);
                     Nid  : constant String := Mermaid_Id (To_String (N.Id));
                  begin
                     if Kind = "strategy" then
                        Append (Buf, "  " & Nid & "[/" & To_String (N.Id) & "/]" & ASCII.LF);
                     elsif Kind = "solution" then
                        Append (Buf, "  " & Nid & "((" & To_String (N.Id) & "))" & ASCII.LF);
                     elsif Kind = "context" then
                        Append (Buf, "  " & Nid & "(" & To_String (N.Id) & ")" & ASCII.LF);
                     elsif Kind = "assumption" or else Kind = "justification" then
                        Append (Buf, "  " & Nid & "{" & To_String (N.Id) & "}" & ASCII.LF);
                     else
                        Append (Buf, "  " & Nid & "[" & To_String (N.Id) & "]" & ASCII.LF);
                     end if;
                  end;
               end loop;
               for N of Nodes loop
                  for R of N.Supported_By loop
                     Append (Buf, "  " & Mermaid_Id (To_String (N.Id)) & " --> " &
                               Mermaid_Id (R) & ASCII.LF);
                  end loop;
                  for R of N.In_Context_Of loop
                     Append (Buf, "  " & Mermaid_Id (To_String (N.Id)) & " -.-> " &
                               Mermaid_Id (R) & ASCII.LF);
                  end loop;
               end loop;
               Emit (Args, To_String (Buf));
            end;
         else
            declare
               Buf     : Unbounded_String := Null_Unbounded_String;
               Visited : String_List;

               procedure Render_Node (Id : String; Indent : Natural) is
                  N      : constant Fusa.Config.Gsn_Node := Find_Node (Id);
                  Prefix : constant String (1 .. Indent * 2) := (others => ' ');
               begin
                  if Length (N.Id) = 0 then
                     Append (Buf, Prefix & "- (unresolved reference: " & Id & ")" & ASCII.LF);
                     return;
                  end if;
                  for V of Visited loop
                     if V = Id then
                        Append (Buf, Prefix & "- [" & To_String (N.Kind) & "] " & Id &
                                  " (see above)" & ASCII.LF);
                        return;
                     end if;
                  end loop;
                  Visited.Append (Id);
                  Append (Buf, Prefix & "- [" & To_String (N.Kind) & "] " & Id & ": " &
                            To_String (N.Text) & ASCII.LF);
                  for Ctx of N.In_Context_Of loop
                     Append (Buf, Prefix & "    (context: " & Ctx & ")" & ASCII.LF);
                  end loop;
                  for Child of N.Supported_By loop
                     Render_Node (Child, Indent + 1);
                  end loop;
               end Render_Node;
            begin
               if Format = "md" then
                  Append (Buf, "# Safety Case" & ASCII.LF & ASCII.LF);
               end if;
               if Length (Root_Goal) > 0
                 and then Length (Find_Node (To_String (Root_Goal)).Id) > 0
               then
                  Render_Node (To_String (Root_Goal), 0);
               end if;
               for N of Nodes loop
                  declare
                     Already : Boolean := False;
                  begin
                     for V of Visited loop
                        if V = To_String (N.Id) then
                           Already := True;
                           exit;
                        end if;
                     end loop;
                     if not Already then
                        Render_Node (To_String (N.Id), 0);
                     end if;
                  end;
               end loop;
               Append (Buf, Trim_Img (Natural (Nodes.Length)) & " nodes, " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings" &
                         ASCII.LF);
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) then
            return Exit_Gate_Fail;
         end if;
         return Exit_Ok;
      end;
   end Cmd_Safety_Case;

   ----------------------------------------------------------------------
   --  cyber -- cybersecurity finding-list (spec section 9.2 SHOULD)
   ----------------------------------------------------------------------

   --  Runs the same rule + disposition pipeline as `check`, then narrows
   --  the result to Category = Security -- ada-FuSa's SEC001-004 rules are
   --  already CWE-mapped cybersecurity findings; `cyber` is a dedicated
   --  view onto that subset (its own report kind/gate), not a second,
   --  independent detection pass.
   --  fusa:req REQ-108
   function Cmd_Cyber (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Strict : constant Boolean := Has_Flag (Args, "--strict");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: cyber: unsupported --format '" & Format &
            "' (supported: text, json)");
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
                 (Args, "cyber-report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "cyber-report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Effective_Strict : constant Boolean := Strict or else Cfg.Strict;
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            All_Findings : Finding_List := Fusa.Engine.Run_All (Dir, Files);
            Findings     : Finding_List;
         begin
            if Fusa.Config.Dispositions_Exist (Dir) then
               declare
                  Disps           : constant Fusa.Config.Disposition_List :=
                    Fusa.Config.Load_Dispositions (Dir);
                  Orphan_Findings : Finding_List;
               begin
                  Fusa.Config.Apply_Dispositions (All_Findings, Disps, Orphan_Findings);
                  for F of Orphan_Findings loop
                     All_Findings.Append (F);
                  end loop;
               end;
            end if;

            for F of All_Findings loop
               if F.Category = Security then
                  Findings.Append (F);
               end if;
            end loop;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "cyber-report");
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings);
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               Emit (Args, Fusa.Report.Render_Text (Findings));
            end if;

            if Fusa.Report.Has_Gate_Failure (Findings, Effective_Strict) then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Cyber;

   ----------------------------------------------------------------------
   --  sci -- Software Configuration Index (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  Every source file plus the known evidence-artifact filenames,
   --  each with a SHA-256 digest and byte size -- a configuration-item
   --  manifest (DO-178C section 7.5-ish "what exactly constitutes this
   --  build"), purely mechanical/derivable, unlike sas below which
   --  additionally requires a human's context. Always exits 0.
   --  fusa:req REQ-109
   function Cmd_Sci (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: sci: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error (Args, "sci", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error (Args, "sci", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Items : String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);

            Evidence_Names : constant array (1 .. 7) of Unbounded_String :=
              (To_Unbounded_String (".fusa.json"),
               To_Unbounded_String (".fusa-reqs.json"),
               To_Unbounded_String (".fusa-dispositions.json"),
               To_Unbounded_String ("qualify-report.json"),
               To_Unbounded_String ("sbom.json"),
               To_Unbounded_String ("comp-report.json"),
               To_Unbounded_String ("vuln.json"));
         begin
            for N of Evidence_Names loop
               if Fusa.Files.Exists (Fusa.Files.Join (Dir, To_String (N))) then
                  Items.Append (To_String (N));
               end if;
            end loop;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "sci");
                  W.Key ("items");
                  W.Array_Start;
                  for Item of Items loop
                     declare
                        Content : constant String :=
                          Fusa.Files.Read_File (Fusa.Files.Join (Dir, Item));
                     begin
                        W.Object_Start;
                        W.Field ("file", Item);
                        W.Field ("sha256", Fusa.Sha256.Hex_Digest (Content));
                        W.Field ("sizeBytes", Content'Length);
                        W.Object_End;
                     end;
                  end loop;
                  W.Array_End;
                  W.Key ("summary");
                  W.Object_Start;
                  W.Field ("total", Natural (Items.Length));
                  W.Object_End;
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for Item of Items loop
                     Append (Buf, Item & ASCII.LF);
                  end loop;
                  Append (Buf, Trim_Img (Natural (Items.Length)) & " configuration items");
                  Emit (Args, To_String (Buf));
               end;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Sci;

   ----------------------------------------------------------------------
   --  analyze -- deeper own-pass static analysis (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  fusa:req REQ-112
   function Cmd_Analyze (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Strict : constant Boolean := Has_Flag (Args, "--strict");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: analyze: unsupported --format '" & Format &
            "' (supported: text, json)");
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
                 (Args, "analyze-report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "analyze-report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Findings : constant Finding_List := Fusa.Analyze.Analyze (Dir, Files);
         begin
            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "analyze-report");
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings);
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               Emit (Args, Fusa.Report.Render_Text (Findings));
            end if;

            --  .fusa.json's "strict" used to only be honoured by check/cyber.
            if Fusa.Report.Has_Gate_Failure (Findings, Strict or else Cfg.Strict) then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Analyze;

   ----------------------------------------------------------------------
   --  lint -- general-correctness/formatting hygiene (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  fusa:req REQ-113
   function Cmd_Lint (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Strict : constant Boolean := Has_Flag (Args, "--strict");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: lint: unsupported --format '" & Format &
            "' (supported: text, json)");
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
                 (Args, "lint-report", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error
                 (Args, "lint-report", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files    : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Findings : constant Finding_List := Fusa.Rules_Lint.Scan (Dir, Files);
         begin
            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "lint-report");
                  Fusa.Report.Write_Findings_Array (W, Findings);
                  Fusa.Report.Write_Summary (W, Findings);
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               Emit (Args, Fusa.Report.Render_Text (Findings));
            end if;

            --  .fusa.json's "strict" used to only be honoured by check/cyber.
            if Fusa.Report.Has_Gate_Failure (Findings, Strict or else Cfg.Strict) then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Lint;

   ----------------------------------------------------------------------
   --  sas -- Software Accomplishment Summary (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  Always writes BOTH sas.json and sas.md to Output_Dir (mirroring the
   --  spec's own note that sas is "sas.json (envelope + tool-defined
   --  body) plus sas.md"), the same "write the artifact unconditionally"
   --  pattern release uses for sbom.json. Every figure in it is
   --  mechanically aggregated from data ada-FuSa already computes
   --  elsewhere (requirement/annotation counts, check's own findings,
   --  comp violations, disposition/problem-report status) -- an
   --  accomplishment summary asserting the software life cycle is
   --  complete is a human sign-off ada-FuSa cannot make; this only
   --  reports the current, honest state of that evidence, whatever it is.
   --  Always exits 0 -- like `report`, it documents rather than gates.
   --  fusa:req REQ-114
   function Cmd_Sas (Args : String_List) return Integer is
      Dir        : constant String := Dir_Of (Args);
      Output_Dir : constant String := Flag_Value (Args, "--output-dir", Dir);
   begin
      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error (Args, "sas", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error (Args, "sas", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         if not Fusa.Files.Exists (Output_Dir) then
            Ada.Directories.Create_Path (Output_Dir);
         end if;

         declare
            Files : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);

            Dup_Findings : Finding_List;
            Reqs         : constant Fusa.Config.Requirement_List :=
              Fusa.Config.Load_Requirements (Dir, Dup_Findings);
            Ann_Findings : Finding_List;
            Tags         : constant Fusa.Annotations.Tag_List :=
              Fusa.Annotations.Scan (Dir, Files, Ann_Findings);
            Req_Total, Req_Traced, Req_Tested, Req_Sec_Tested : Natural := 0;

            Check_Findings : constant Finding_List := Fusa.Engine.Run_All (Dir, Files);
            Chk_Errors, Chk_Warnings, Chk_Infos : Natural := 0;

            Comp_Results : constant Fusa.Comp.Comp_Result_List := Fusa.Comp.Analyze (Dir, Files, 10);
            Comp_Violations : Natural := 0;

            Disp_Accepted, Disp_Deferred, Disp_Rejected : Natural := 0;
            Pr_Open, Pr_Closed : Natural := 0;
         begin
            Req_Total := Natural (Reqs.Length);
            for R of Reqs loop
               declare
                  Traced, Tested, Sec_Tested : Boolean := False;
               begin
                  for T of Tags loop
                     if To_String (T.Requirement_Id) = To_String (R.Id) then
                        Traced := True;
                        if T.Kind = Test or else T.Kind = Sec_Test then
                           Tested := True;
                        end if;
                        if T.Kind = Sec_Test then
                           Sec_Tested := True;
                        end if;
                     end if;
                  end loop;
                  if Traced then
                     Req_Traced := Req_Traced + 1;
                  end if;
                  if Tested then
                     Req_Tested := Req_Tested + 1;
                  end if;
                  if Sec_Tested then
                     Req_Sec_Tested := Req_Sec_Tested + 1;
                  end if;
               end;
            end loop;

            for F of Check_Findings loop
               case F.Severity is
                  when Error   => Chk_Errors   := Chk_Errors + 1;
                  when Warning => Chk_Warnings := Chk_Warnings + 1;
                  when Info    => Chk_Infos    := Chk_Infos + 1;
               end case;
            end loop;

            for R of Comp_Results loop
               if R.Exceeds_Threshold then
                  Comp_Violations := Comp_Violations + 1;
               end if;
            end loop;

            if Fusa.Config.Dispositions_Exist (Dir) then
               for D of Fusa.Config.Load_Dispositions (Dir) loop
                  case D.Status is
                     when Accepted => Disp_Accepted := Disp_Accepted + 1;
                     when Deferred => Disp_Deferred := Disp_Deferred + 1;
                     when Rejected => Disp_Rejected := Disp_Rejected + 1;
                     when Open     => null;
                  end case;
               end loop;
            end if;

            if Fusa.Config.Pr_Exists (Dir) then
               for P of Fusa.Config.Load_Pr (Dir) loop
                  if To_String (P.Status) = "closed" then
                     Pr_Closed := Pr_Closed + 1;
                  else
                     Pr_Open := Pr_Open + 1;
                  end if;
               end loop;
            end if;

            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               Fusa.Report.Write_Header (W, "sas");
               W.Key ("project");
               W.Object_Start;
               W.Field ("name", To_String (Cfg.Name));
               W.Field_If_Non_Blank ("standard", To_String (Cfg.Standard));
               W.Object_End;
               W.Key ("requirements");
               W.Object_Start;
               W.Field ("total", Req_Total);
               W.Field ("traced", Req_Traced);
               W.Field ("tested", Req_Tested);
               W.Field ("secTested", Req_Sec_Tested);
               W.Object_End;
               W.Key ("check");
               W.Object_Start;
               W.Field ("errors", Chk_Errors);
               W.Field ("warnings", Chk_Warnings);
               W.Field ("infos", Chk_Infos);
               W.Object_End;
               W.Key ("comp");
               W.Object_Start;
               W.Field ("totalFunctions", Natural (Comp_Results.Length));
               W.Field ("violations", Comp_Violations);
               W.Object_End;
               W.Key ("dispositions");
               W.Object_Start;
               W.Field ("accepted", Disp_Accepted);
               W.Field ("deferred", Disp_Deferred);
               W.Field ("rejected", Disp_Rejected);
               W.Object_End;
               W.Key ("problemReports");
               W.Object_Start;
               W.Field ("open", Pr_Open);
               W.Field ("closed", Pr_Closed);
               W.Object_End;
               W.Object_End;
               Fusa.Files.Write_File
                 (Fusa.Files.Join (Output_Dir, "sas.json"), Fusa.Json.Writer.To_String (W) & ASCII.LF);
            end;
            Ada.Text_IO.Put_Line ("wrote " & Fusa.Files.Join (Output_Dir, "sas.json"));

            declare
               Md : Unbounded_String := Null_Unbounded_String;
            begin
               Append (Md, "# Software Accomplishment Summary -- " & To_String (Cfg.Name) &
                         ASCII.LF & ASCII.LF);
               Append (Md, "**Standard:** " & To_String (Cfg.Standard) & ASCII.LF & ASCII.LF);
               Append (Md, "## Requirements" & ASCII.LF & ASCII.LF);
               Append (Md, "- Total: " & Trim_Img (Req_Total) & ASCII.LF);
               Append (Md, "- Traced: " & Trim_Img (Req_Traced) & ASCII.LF);
               Append (Md, "- Tested: " & Trim_Img (Req_Tested) & ASCII.LF);
               Append (Md, "- Security-tested: " & Trim_Img (Req_Sec_Tested) & ASCII.LF & ASCII.LF);
               Append (Md, "## Check findings" & ASCII.LF & ASCII.LF);
               Append (Md, "- Errors: " & Trim_Img (Chk_Errors) & ASCII.LF);
               Append (Md, "- Warnings: " & Trim_Img (Chk_Warnings) & ASCII.LF);
               Append (Md, "- Infos: " & Trim_Img (Chk_Infos) & ASCII.LF & ASCII.LF);
               Append (Md, "## Cyclomatic complexity" & ASCII.LF & ASCII.LF);
               Append (Md, "- Functions analysed: " &
                         Trim_Img (Natural (Comp_Results.Length)) & ASCII.LF);
               Append (Md, "- Threshold violations: " & Trim_Img (Comp_Violations) &
                         ASCII.LF & ASCII.LF);
               Append (Md, "## Dispositions (waivers)" & ASCII.LF & ASCII.LF);
               Append (Md, "- Accepted: " & Trim_Img (Disp_Accepted) & ASCII.LF);
               Append (Md, "- Deferred: " & Trim_Img (Disp_Deferred) & ASCII.LF);
               Append (Md, "- Rejected: " & Trim_Img (Disp_Rejected) & ASCII.LF & ASCII.LF);
               Append (Md, "## Problem reports" & ASCII.LF & ASCII.LF);
               Append (Md, "- Open: " & Trim_Img (Pr_Open) & ASCII.LF);
               Append (Md, "- Closed: " & Trim_Img (Pr_Closed) & ASCII.LF);
               Fusa.Files.Write_File (Fusa.Files.Join (Output_Dir, "sas.md"), To_String (Md));
            end;
            Ada.Text_IO.Put_Line ("wrote " & Fusa.Files.Join (Output_Dir, "sas.md"));
         end;
      end;
      return Exit_Ok;
   end Cmd_Sas;

   ----------------------------------------------------------------------
   --  template -- project scaffolding (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  Only one template ("default") exists: a source-tree/build/CI
   --  skeleton complementary to `init` (which only ever writes
   --  .fusa.json/.fusa-reqs.json) -- not a second copy of the same
   --  templates enumerated to have several when the only real difference
   --  between candidate variants would be cosmetic. Deliberately does
   --  NOT write a LICENSE file: choosing a license is a legal/business
   --  decision this tool must never make on a user's behalf: the
   --  scaffolded README explicitly tells the user to add one.
   procedure Write_If_Absent (Path, Content : String; Force : Boolean) is
   begin
      if Force or else not Fusa.Files.Exists (Path) then
         Fusa.Files.Write_File (Path, Content);
         Ada.Text_IO.Put_Line ("created " & Path);
      else
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: " & Path & " already exists, leaving unchanged " &
            "(use --force to overwrite)");
      end if;
   end Write_If_Absent;

   --  fusa:req REQ-115
   function Cmd_Template (Args : String_List) return Integer is
   begin
      if Args.Is_Empty then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error, "ada-FuSa: template: missing subcommand (list|apply)");
         return Exit_Usage;
      end if;
      declare
         Verb : constant String := Args.Element (1);
         Rest : String_List := Args;
      begin
         Rest.Delete_First;

         if Verb = "list" then
            declare
               Format : constant String := Flag_Value (Rest, "--format", "text");
            begin
               if Format /= "text" and then Format /= "json" then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: template list: unsupported --format '" & Format &
                     "' (supported: text, json)");
                  return Exit_Usage;
               end if;
               if Format = "json" then
                  declare
                     W : Fusa.Json.Writer.Instance;
                  begin
                     W.Object_Start;
                     Fusa.Report.Write_Header (W, "template-list");
                     W.Key ("templates");
                     W.Array_Start;
                     W.Object_Start;
                     W.Field ("name", "default");
                     W.Field ("description",
                       "minimal Ada project skeleton: .gpr, src/, tests/, README.md, " &
                       ".github/workflows/ci.yml -- does not write a LICENSE file");
                     W.Object_End;
                     W.Array_End;
                     W.Object_End;
                     Emit (Rest, Fusa.Json.Writer.To_String (W));
                  end;
               else
                  Emit (Rest, "default: minimal Ada project skeleton (.gpr, src/, tests/, " &
                          "README.md, .github/workflows/ci.yml -- no LICENSE)");
               end if;
            end;
            return Exit_Ok;

         elsif Verb = "apply" then
            if Rest.Is_Empty then
               Ada.Text_IO.Put_Line
                 (Ada.Text_IO.Standard_Error, "ada-FuSa: template apply: requires <name>");
               return Exit_Usage;
            end if;
            declare
               Name  : constant String := Rest.Element (1);
               Dir   : constant String := Dir_Of (Rest);
               Force : constant Boolean := Has_Flag (Rest, "--force");
               Proj_Name : constant String :=
                 Flag_Value (Rest, "--project-name", "myproject");
            begin
               if Name /= "default" then
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada-FuSa: template apply: unknown template '" & Name &
                     "' (available: default)");
                  return Exit_Usage;
               end if;

               if not Fusa.Files.Exists (Dir) then
                  Ada.Directories.Create_Path (Dir);
               end if;
               if not Fusa.Files.Exists (Dir & "/src") then
                  Ada.Directories.Create_Path (Dir & "/src");
               end if;
               if not Fusa.Files.Exists (Dir & "/tests") then
                  Ada.Directories.Create_Path (Dir & "/tests");
               end if;
               if not Fusa.Files.Exists (Dir & "/.github/workflows") then
                  Ada.Directories.Create_Path (Dir & "/.github/workflows");
               end if;

               Write_If_Absent
                 (Fusa.Files.Join (Dir, Proj_Name & ".gpr"),
                  "project " & Proj_Name & " is" & ASCII.LF & ASCII.LF &
                  "   for Source_Dirs use (""src"");" & ASCII.LF &
                  "   for Object_Dir use ""obj"";" & ASCII.LF &
                  "   for Exec_Dir use ""bin"";" & ASCII.LF & ASCII.LF &
                  "   package Compiler is" & ASCII.LF &
                  "      for Default_Switches (""Ada"") use" & ASCII.LF &
                  "        (""-gnatwa"", ""-gnat2022"", ""-g"");" & ASCII.LF &
                  "   end Compiler;" & ASCII.LF & ASCII.LF &
                  "end " & Proj_Name & ";" & ASCII.LF,
                  Force);

               Write_If_Absent
                 (Fusa.Files.Join (Dir, "README.md"),
                  "# " & Proj_Name & ASCII.LF & ASCII.LF &
                  "TODO: describe this project." & ASCII.LF & ASCII.LF &
                  "## License" & ASCII.LF & ASCII.LF &
                  "TODO: choose and add a LICENSE file appropriate for this project -- " &
                  "ada-FuSa does not select one on your behalf." & ASCII.LF,
                  Force);

               Write_If_Absent
                 (Fusa.Files.Join (Dir, ".github/workflows/ci.yml"),
                  "name: CI" & ASCII.LF & ASCII.LF &
                  "on: [push, pull_request]" & ASCII.LF & ASCII.LF &
                  "jobs:" & ASCII.LF &
                  "  build:" & ASCII.LF &
                  "    runs-on: ubuntu-latest" & ASCII.LF &
                  "    steps:" & ASCII.LF &
                  "      - uses: actions/checkout@v4" & ASCII.LF &
                  "      - uses: alire-project/setup-alire@v4" & ASCII.LF &
                  "      - run: alr build" & ASCII.LF &
                  "      # add `adafusa check`/`adafusa qualify` steps here once " &
                  "ada-FuSa is installed in this CI image" & ASCII.LF,
                  Force);

               return Exit_Ok;
            end;

         else
            Ada.Text_IO.Put_Line
              (Ada.Text_IO.Standard_Error,
               "ada-FuSa: template: unknown subcommand '" & Verb & "' (expected list|apply)");
            return Exit_Usage;
         end if;
      end;
   end Cmd_Template;

   ----------------------------------------------------------------------
   --  fix -- safe auto-fix (spec section 9.3 MAY)
   ----------------------------------------------------------------------

   --  The first command that writes to a user's actual source files --
   --  see Fusa.Fix's own header comment for why the transform it applies
   --  is deliberately narrow (whitespace/formatting only, never anything
   --  requiring a judgement call). Defaults to a DRY RUN: without
   --  --apply, nothing is ever written, and the command gate-fails if any
   --  file WOULD change -- the same "gofmt -l"/"prettier --check" CI
   --  pattern, so a project can fail CI on unformatted code without
   --  fix ever touching a file unless a human explicitly asks it to
   --  (--apply, typically run locally, not in CI).
   --  fusa:req REQ-116
   function Cmd_Fix (Args : String_List) return Integer is
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
      Apply  : constant Boolean := Has_Flag (Args, "--apply");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: fix: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      declare
         Cfg : Fusa.Config.Project_Config;
      begin
         begin
            Cfg := Fusa.Config.Load (Dir);
         exception
            when Fusa.Config.No_Config_Error =>
               return Emit_Runtime_Error (Args, "fix", "no-config", "no .fusa.json found in " & Dir);
            when Fusa.Config.Invalid_Config_Error =>
               return Emit_Runtime_Error (Args, "fix", "invalid-config", "invalid .fusa.json in " & Dir);
         end;

         declare
            Files   : constant String_List := Fusa.Source_Scan.Find_Source_Files (Dir, Cfg);
            Changed : String_List;
         begin
            for Rel of Files loop
               declare
                  Full : constant String := Fusa.Files.Join (Dir, Rel);
               begin
                  if Fusa.Files.Exists (Full) then
                     declare
                        Original : constant String := Fusa.Files.Read_File (Full);
                        Fixed    : constant String := Fusa.Fix.Fix_Content (Original);
                     begin
                        if Fixed /= Original then
                           Changed.Append (Rel);
                           if Apply then
                              --  Write_File_Atomic (not the plain
                              --  Write_File every other command uses)
                              --  closes the TOCTOU window between the
                              --  Read_File above and this write -- fix
                              --  is the one command that overwrites an
                              --  existing project source file based on
                              --  content read moments earlier.
                              Fusa.Files.Write_File_Atomic (Full, Fixed);
                           end if;
                        end if;
                     end;
                  end if;
               end;
            end loop;

            if Format = "json" then
               declare
                  W : Fusa.Json.Writer.Instance;
               begin
                  W.Object_Start;
                  Fusa.Report.Write_Header (W, "fix-report");
                  W.Field ("applied", Apply);
                  W.Key ("files");
                  W.Array_Start;
                  for F of Changed loop
                     W.Value (F);
                  end loop;
                  W.Array_End;
                  W.Object_End;
                  Emit (Args, Fusa.Json.Writer.To_String (W));
               end;
            else
               declare
                  Buf : Unbounded_String := Null_Unbounded_String;
               begin
                  for F of Changed loop
                     Append (Buf, (if Apply then "fixed  " else "would fix  ") & F & ASCII.LF);
                  end loop;
                  Append (Buf, Trim_Img (Natural (Changed.Length)) &
                            (if Apply then " file(s) fixed" else " file(s) would be fixed " &
                               "(re-run with --apply to write the changes)"));
                  Emit (Args, To_String (Buf));
               end;
            end if;

            if not Apply and then not Changed.Is_Empty then
               return Exit_Gate_Fail;
            end if;
            return Exit_Ok;
         end;
      end;
   end Cmd_Fix;

   ----------------------------------------------------------------------
   --  Usage / dispatch
   ----------------------------------------------------------------------

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "usage: adafusa <command> [options]" & ASCII.LF &
        "commands: version capabilities init check trace qualify release audit-pack " &
        "report comp hara tara vuln req disposition pr metrics sign hooks " &
        "do178 iso26262 iso21434 iec61508 iec62443 unece slsa " &
        "verify diff badge boundary impact coupling fmea safety-case " &
        "cyber sci analyze lint sas template fix");
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
         elsif Cmd = "comp" then
            return Cmd_Comp (Rest);
         elsif Cmd = "hara" then
            return Cmd_Hara (Rest);
         elsif Cmd = "tara" then
            return Cmd_Tara (Rest);
         elsif Cmd = "vuln" then
            return Cmd_Vuln (Rest);
         elsif Cmd = "req" then
            return Cmd_Req (Rest);
         elsif Cmd = "disposition" then
            return Cmd_Disposition (Rest);
         elsif Cmd = "pr" then
            return Cmd_Pr (Rest);
         elsif Cmd = "metrics" then
            return Cmd_Metrics (Rest);
         elsif Cmd = "sign" then
            return Cmd_Sign (Rest);
         elsif Cmd = "hooks" then
            return Cmd_Hooks (Rest);
         elsif Cmd = "do178" then
            return Cmd_Do178 (Rest);
         elsif Cmd = "iso26262" then
            return Cmd_Iso26262 (Rest);
         elsif Cmd = "iso21434" then
            return Cmd_Iso21434 (Rest);
         elsif Cmd = "iec61508" then
            return Cmd_Iec61508 (Rest);
         elsif Cmd = "iec62443" then
            return Cmd_Iec62443 (Rest);
         elsif Cmd = "unece" then
            return Cmd_Unece (Rest);
         elsif Cmd = "slsa" then
            return Cmd_Slsa (Rest);
         elsif Cmd = "verify" then
            return Cmd_Verify (Rest);
         elsif Cmd = "diff" then
            return Cmd_Diff (Rest);
         elsif Cmd = "badge" then
            return Cmd_Badge (Rest);
         elsif Cmd = "boundary" then
            return Cmd_Boundary (Rest);
         elsif Cmd = "impact" then
            return Cmd_Impact (Rest);
         elsif Cmd = "coupling" then
            return Cmd_Coupling (Rest);
         elsif Cmd = "fmea" then
            return Cmd_Fmea (Rest);
         elsif Cmd = "safety-case" then
            return Cmd_Safety_Case (Rest);
         elsif Cmd = "cyber" then
            return Cmd_Cyber (Rest);
         elsif Cmd = "sci" then
            return Cmd_Sci (Rest);
         elsif Cmd = "analyze" then
            return Cmd_Analyze (Rest);
         elsif Cmd = "lint" then
            return Cmd_Lint (Rest);
         elsif Cmd = "sas" then
            return Cmd_Sas (Rest);
         elsif Cmd = "template" then
            return Cmd_Template (Rest);
         elsif Cmd = "fix" then
            return Cmd_Fix (Rest);
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
