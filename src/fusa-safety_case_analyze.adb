with Fusa.Files;

package body Fusa.Safety_Case_Analyze is

   type Artifact_Fact is record
      Name  : Unbounded_String;
      Claim : Unbounded_String;
   end record;

   --  README's own "Evidence Artifacts" table -- the same fixed
   --  filenames Cmd_Audit_Pack's Add_If_Exists allowlist already treats
   --  as this project's real, well-known evidence artifacts.
   Known_Artifacts : constant array (Positive range <>) of Artifact_Fact :=
     ((To_Unbounded_String ("fusa-report.json"),
       To_Unbounded_String ("static analysis findings are captured")),
      (To_Unbounded_String ("qualify-report.json"),
       To_Unbounded_String ("tool qualification evidence is captured")),
      (To_Unbounded_String ("comp-report.json"),
       To_Unbounded_String ("cyclomatic complexity analysis is captured")),
      (To_Unbounded_String ("sbom.json"),
       To_Unbounded_String ("a software bill of materials is captured")),
      (To_Unbounded_String ("vuln.json"),
       To_Unbounded_String ("a dependency vulnerability scan is captured")),
      (To_Unbounded_String ("fmea.json"),
       To_Unbounded_String ("a failure mode and effects analysis is captured")),
      (To_Unbounded_String ("sci.json"),
       To_Unbounded_String ("a software configuration index is captured")),
      (To_Unbounded_String ("sas.json"),
       To_Unbounded_String ("a software accomplishment summary is captured")));

   function Derive_Nodes
     (Project_Root : String; Root_Goal : out Unbounded_String)
      return Fusa.Config.Gsn_Node_List
   is
      Result       : Fusa.Config.Gsn_Node_List;
      Solution_Ids : Fusa.String_List;
      Project_Name : Unbounded_String := To_Unbounded_String ("this project");
   begin
      begin
         declare
            Cfg : constant Fusa.Config.Project_Config := Fusa.Config.Load (Project_Root);
         begin
            if Length (Cfg.Name) > 0 then
               Project_Name := Cfg.Name;
            end if;
         end;
      exception
         when Fusa.Config.No_Config_Error | Fusa.Config.Invalid_Config_Error =>
            null;
      end;

      for A of Known_Artifacts loop
         declare
            Path : constant String := Fusa.Files.Join (Project_Root, To_String (A.Name));
         begin
            if Fusa.Files.Exists (Path) and then not Fusa.Files.Is_Directory (Path) then
               declare
                  Sol_Id : constant String := "SLN-" & To_String (A.Name);
                  Node   : Fusa.Config.Gsn_Node;
               begin
                  Node.Id       := To_Unbounded_String (Sol_Id);
                  Node.Kind     := To_Unbounded_String ("solution");
                  Node.Text     :=
                    To_Unbounded_String
                      (To_String (A.Claim) & " in " & To_String (A.Name));
                  Node.Evidence := A.Name;
                  Result.Append (Node);
                  Solution_Ids.Append (Sol_Id);
               end;
            end if;
         end;
      end loop;

      --  Nothing real to cite yet -- an honestly-missing argument, not a
      --  fabricated one (section 1.6.1's own rule for solution nodes).
      if Solution_Ids.Is_Empty then
         Root_Goal := Null_Unbounded_String;
         return Result;
      end if;

      declare
         Goal     : Fusa.Config.Gsn_Node;
         Strategy : Fusa.Config.Gsn_Node;
      begin
         Goal.Id   := To_Unbounded_String ("G1");
         Goal.Kind := To_Unbounded_String ("goal");
         Goal.Text :=
           To_Unbounded_String
             (To_String (Project_Name) &
              "'s safety-relevant behaviour is developed and evidenced by " &
              "its own currently-generated ada-FuSa evidence artifacts");
         Goal.Supported_By.Append ("S1");

         Strategy.Id   := To_Unbounded_String ("S1");
         Strategy.Kind := To_Unbounded_String ("strategy");
         Strategy.Text :=
           To_Unbounded_String
             ("argument by citing each real, currently-present ada-FuSa " &
              "evidence artifact this project has actually generated");
         Strategy.Supported_By := Solution_Ids;

         Result.Prepend (Strategy);
         Result.Prepend (Goal);
      end;

      Root_Goal := To_Unbounded_String ("G1");
      return Result;
   end Derive_Nodes;

end Fusa.Safety_Case_Analyze;
