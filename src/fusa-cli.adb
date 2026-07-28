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
      --  FUSA001-004 check Project_Root, not the single-file fixture
      --  Check_Rule writes -- they can't be "triggered" the same way the
      --  content-scanning rules above are, since qualify runs against
      --  ada-FuSa's own real project root (which already has all four
      --  markers). Their absence-of-false-positive behaviour is already
      --  exercised on every qualify run (Run_All below runs every
      --  registered rule, including these, against Dir); this just makes
      --  that an explicit, named, reported known-answer case rather than
      --  a silent side effect.
      declare
         Empty_Files : String_List;
         Findings    : constant Finding_List := Fusa.Engine.Run_All (Dir, Empty_Files);
         Fusa_Hit    : Boolean := False;
      begin
         for F of Findings loop
            if To_String (F.Rule_Id) = "FUSA001" or else To_String (F.Rule_Id) = "FUSA002"
              or else To_String (F.Rule_Id) = "FUSA003" or else To_String (F.Rule_Id) = "FUSA004"
            then
               Fusa_Hit := True;
            end if;
         end loop;
         Cases.Append
           (Case_Result'
              (Name   => To_Unbounded_String ("rule-FUSA00x-known-answer"),
               Result => To_Unbounded_String
                 (if not Fusa_Hit then "PASS" else "FAIL")));
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
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: hara: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Hara_Exists (Dir) then
         Fusa.Config.Scaffold_Hara (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Hara_File) &
              " (template) -- fill in your hazards and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings : Finding_List;
         Hazards  : constant Fusa.Config.Hazard_List := Fusa.Config.Load_Hara (Dir, Findings);
      begin
         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               Fusa.Report.Write_Header (W, "hara");
               W.Key ("hazards");
               W.Array_Start;
               for H of Hazards loop
                  W.Object_Start;
                  W.Field ("id", To_String (H.Id));
                  W.Field ("hazard", To_String (H.Description));
                  W.Field ("severity", To_String (H.Severity));
                  W.Field ("exposure", To_String (H.Exposure));
                  W.Field ("controllability", To_String (H.Controllability));
                  W.Field ("asil", To_String (H.Asil));
                  W.Field ("safetyGoal", To_String (H.Safety_Goal));
                  W.Object_End;
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
               for H of Hazards loop
                  Append (Buf, To_String (H.Id) & ": " & To_String (H.Description) &
                            " (ASIL " & To_String (H.Asil) & ")" & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Natural (Hazards.Length)) & " hazards, " &
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
      Dir    : constant String := Dir_Of (Args);
      Format : constant String := Flag_Value (Args, "--format", "text");
   begin
      if Format /= "text" and then Format /= "json" then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada-FuSa: tara: unsupported --format '" & Format &
            "' (supported: text, json)");
         return Exit_Usage;
      end if;

      if not Fusa.Config.Tara_Exists (Dir) then
         Fusa.Config.Scaffold_Tara (Dir);
         Ada.Text_IO.Put_Line
           ("created " & Fusa.Files.Join (Dir, Fusa.Config.Tara_File) &
              " (template) -- fill in your threats and re-run");
         return Exit_Ok;
      end if;

      declare
         Findings : Finding_List;
         Threats  : constant Fusa.Config.Threat_List := Fusa.Config.Load_Tara (Dir, Findings);
      begin
         if Format = "json" then
            declare
               W : Fusa.Json.Writer.Instance;
            begin
               W.Object_Start;
               Fusa.Report.Write_Header (W, "tara");
               W.Key ("threats");
               W.Array_Start;
               for T of Threats loop
                  W.Object_Start;
                  W.Field ("id", To_String (T.Id));
                  W.Field ("asset", To_String (T.Asset));
                  W.Field ("threat", To_String (T.Description));
                  W.Field ("attackVector", To_String (T.Attack_Vector));
                  W.Field ("impact", To_String (T.Impact));
                  W.Field ("likelihood", To_String (T.Likelihood));
                  W.Field ("risk", To_String (T.Risk));
                  W.Field ("treatment", To_String (T.Treatment));
                  W.Key ("mitigations");
                  W.Array_Start;
                  for M of T.Mitigations loop
                     W.Value (M);
                  end loop;
                  W.Array_End;
                  W.Object_End;
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
               for T of Threats loop
                  Append (Buf, To_String (T.Id) & ": " & To_String (T.Description) &
                            " (risk " & To_String (T.Risk) & ")" & ASCII.LF);
               end loop;
               Append (Buf, Trim_Img (Natural (Threats.Length)) & " threats, " &
                         Trim_Img (Natural (Findings.Length)) & " validation findings");
               Emit (Args, To_String (Buf));
            end;
         end if;

         if Fusa.Report.Has_Gate_Failure (Findings, False) then
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
                           if To_String (Stored) = Sig then
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

   procedure Make_Executable (Path : String) is
      function C_Chmod
        (Path : Interfaces.C.Strings.chars_ptr; Mode : Interfaces.C.int) return Interfaces.C.int;
      pragma Import (C, C_Chmod, "chmod");
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Result : Interfaces.C.int;
      pragma Unreferenced (Result);
   begin
      Result := C_Chmod (C_Path, 8#755#);
      Interfaces.C.Strings.Free (C_Path);
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
               Make_Executable (Hook_Path);
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
               Fusa.Report.Write_Header (W, Standard_Id & "-gap-report");
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
               W.Key ("objectiveSummary");
               W.Object_Start;
               W.Field ("total", Natural (Objectives.Length));
               W.Field ("satisfied", Satisfied);
               W.Field ("partial", Partial);
               W.Field ("gaps", Gaps);
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
   --  Usage / dispatch
   ----------------------------------------------------------------------

   procedure Print_Usage is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error,
        "usage: adafusa <command> [options]" & ASCII.LF &
        "commands: version capabilities init check trace qualify release audit-pack " &
        "report comp hara tara vuln req disposition pr metrics sign hooks " &
        "do178 iso26262 iso21434 iec61508 iec62443 unece slsa");
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
