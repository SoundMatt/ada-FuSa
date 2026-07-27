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

end Fusa.Config;
