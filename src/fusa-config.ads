--  .fusa.json / .fusa-reqs.json handling per x-FuSa spec §1.2.

with Ada.Containers.Indefinite_Vectors;

package Fusa.Config is

   Config_File         : constant String := ".fusa.json";
   Legacy_Config_File   : constant String := ".adafusa.json";
   Reqs_File            : constant String := ".fusa-reqs.json";
   Legacy_Reqs_File     : constant String := ".adafusa-reqs.json";
   Config_File_Version  : constant String := "1.0";

   --  Raised when neither the canonical nor legacy config file exists.
   No_Config_Error : exception;

   --  Raised on a parse error or a config that is structurally invalid.
   Invalid_Config_Error : exception;

   type Project_Config is record
      Name             : Unbounded_String;
      Version          : Unbounded_String := To_Unbounded_String ("0.1.0");
      Standard         : Unbounded_String := To_Unbounded_String ("generic");
      Asil             : Unbounded_String; --  at most one of Asil/Sil/Dal
      Sil              : Unbounded_String; --  is non-blank
      Dal              : Unbounded_String;
      Strict           : Boolean := False;
      Source_Dirs      : String_List;
      Exclude_Patterns : String_List;
   end record;

   --  fusa:req REQ-050
   function Default_Config (Name : String) return Project_Config;

   --  True if a canonical or legacy config file exists under Project_Root.
   --  fusa:req REQ-051
   function Exists (Project_Root : String) return Boolean;

   --  Loads .fusa.json (falling back to legacy .adafusa.json with a stderr
   --  deprecation warning when only the legacy name exists -- canonical
   --  wins when both are present). Raises No_Config_Error / Invalid_Config_Error.
   --  fusa:req REQ-005
   function Load (Project_Root : String) return Project_Config;

   --  Writes the canonical §1.2.1 shape (always the nested `project` form).
   --  fusa:req REQ-052
   procedure Save (Project_Root : String; Cfg : Project_Config);

   ------------------------------------------------------------------
   --  .fusa-reqs.json
   ------------------------------------------------------------------

   type Requirement is record
      Id       : Unbounded_String;
      Title    : Unbounded_String;
      Text     : Unbounded_String;
      Standard : Unbounded_String;
      Level    : Unbounded_String; --  HLR | LLR | SYS | SW
      Asil     : Unbounded_String;
      Parent   : Unbounded_String;
   end record;

   package Requirement_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Requirement);
   subtype Requirement_List is Requirement_Vectors.Vector;

   --  True if a canonical or legacy requirements file exists.
   --  fusa:req REQ-053
   function Requirements_Exist (Project_Root : String) return Boolean;

   --  Loads .fusa-reqs.json (or legacy). Returns an empty list if absent.
   --  A duplicate `id` within the file MUST surface as an ERROR finding
   --  (category requirement) per spec §1.2 rather than being silently
   --  merged or dropped -- such findings are appended to Findings.
   --  fusa:req REQ-006
   function Load_Requirements
     (Project_Root : String;
      Findings     : in out Finding_List) return Requirement_List;

   --  fusa:req REQ-054
   procedure Save_Requirements
     (Project_Root : String; Reqs : Requirement_List);

   ------------------------------------------------------------------
   --  .fusa-dispositions.json (spec section 1.2.3 / section 4.1)
   ------------------------------------------------------------------

   Dispositions_File : constant String := ".fusa-dispositions.json";

   type Disposition_Entry is record
      Fingerprint : Unbounded_String; --  SHOULD, primary match key
      Rule_Id     : Unbounded_String; --  MAY, fallback match key
      File        : Unbounded_String; --  MAY, fallback match key (project-relative)
      Line        : Natural := 0;     --  MAY, fallback match key (0 = unset)
      Status      : Disposition_Kind := Open; --  MUST: accepted | deferred | rejected
      Note        : Unbounded_String; --  SHOULD
      By          : Unbounded_String; --  SHOULD
      At_Time     : Unbounded_String; --  SHOULD, RFC 3339 ("at" is an Ada reserved word)
   end record;

   package Disposition_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Disposition_Entry);
   subtype Disposition_List is Disposition_Vectors.Vector;

   --  True if a .fusa-dispositions.json file exists (no legacy fallback --
   --  this file was not part of the original v0.1.0 schema).
   --  fusa:req REQ-070
   function Dispositions_Exist (Project_Root : String) return Boolean;

   --  Loads .fusa-dispositions.json. Returns an empty list if absent. An
   --  entry with a missing/unrecognised "status" is skipped (Status stays
   --  Open, which Apply_Dispositions never applies to a finding).
   --  fusa:req REQ-071
   function Load_Dispositions (Project_Root : String) return Disposition_List;

   --  section 4.1 matching: fingerprint (MUST, when both sides have one) ->
   --  ruleId+file+line (MAY fallback) -> ruleId-only rule-level (MAY
   --  fallback), in that precedence order. Sets each matched Finding's
   --  Disposition field in place. An accepted/deferred entry matching no
   --  finding in Findings is an orphaned waiver (SHOULD warn, category
   --  config); a rejected orphan is silent (the denied finding was
   --  resolved, which is success).
   --  fusa:req REQ-072
   procedure Apply_Dispositions
     (Findings        : in out Finding_List;
      Disps           : Disposition_List;
      Orphan_Findings : in out Finding_List);

   ------------------------------------------------------------------
   --  .fusa-hara.json (spec section 13: hazard analysis & risk
   --  assessment, ISO 26262-3 -- an input file the hara command
   --  validates/normalises, scaffolding a template if absent)
   ------------------------------------------------------------------

   Hara_File : constant String := ".fusa-hara.json";

   type Hazard is record
      Id              : Unbounded_String;
      Description     : Unbounded_String;
      Severity        : Unbounded_String;
      Exposure        : Unbounded_String;
      Controllability : Unbounded_String;
      Asil            : Unbounded_String;
      Safety_Goal     : Unbounded_String;
   end record;

   package Hazard_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Hazard);
   subtype Hazard_List is Hazard_Vectors.Vector;

   --  fusa:req REQ-082
   function Hara_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-hara.json. Returns an empty list if absent. A hazard
   --  missing "id" is an ERROR finding (category safety) -- without an id
   --  it cannot be referenced or tracked; a hazard missing any other
   --  required field is a WARNING finding, so the hazard is still usable
   --  but incompletely specified.
   --  fusa:req REQ-082
   function Load_Hara
     (Project_Root : String;
      Findings     : in out Finding_List) return Hazard_List;

   --  Writes an empty-array template if .fusa-hara.json does not already
   --  exist; a no-op (does not overwrite) if it does.
   --  fusa:req REQ-082
   procedure Scaffold_Hara (Project_Root : String);

   ------------------------------------------------------------------
   --  .fusa-tara.json (spec section 13 "canonical direction": threat
   --  analysis & risk assessment, ISO 21434 ch.9 -- same input/
   --  validate/scaffold pattern as .fusa-hara.json)
   ------------------------------------------------------------------

   Tara_File : constant String := ".fusa-tara.json";

   type Threat is record
      Id             : Unbounded_String;
      Asset          : Unbounded_String;
      Description    : Unbounded_String;
      Attack_Vector  : Unbounded_String;
      Impact         : Unbounded_String;
      Likelihood     : Unbounded_String;
      Risk           : Unbounded_String;
      Treatment      : Unbounded_String;
      Mitigations    : String_List;
   end record;

   package Threat_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Threat);
   subtype Threat_List is Threat_Vectors.Vector;

   --  fusa:req REQ-083
   function Tara_Exists (Project_Root : String) return Boolean;

   --  Same validation rule as Load_Hara: missing "id" is an ERROR
   --  (category security), any other missing required field is a WARNING.
   --  fusa:req REQ-083
   function Load_Tara
     (Project_Root : String;
      Findings     : in out Finding_List) return Threat_List;

   --  fusa:req REQ-083
   procedure Scaffold_Tara (Project_Root : String);

   --  fusa:req REQ-088
   --  Writes Disps to .fusa-dispositions.json, for the `disposition add`
   --  management verb (see #29). Overwrites the whole file -- callers that
   --  want to add one entry MUST Load_Dispositions first, Append to the
   --  result, then Save_Dispositions the combined list.
   procedure Save_Dispositions (Project_Root : String; Disps : Disposition_List);

   ------------------------------------------------------------------
   --  .fusa-pr.json (DO-178C section 11.17 problem-report log)
   ------------------------------------------------------------------

   Pr_File : constant String := ".fusa-pr.json";

   type Problem_Report is record
      Id         : Unbounded_String;
      Title      : Unbounded_String;
      Severity   : Unbounded_String;
      Status     : Unbounded_String; --  "open" | "closed"
      Resolution : Unbounded_String; --  blank while open
      Opened_At  : Unbounded_String; --  RFC 3339
      Closed_At  : Unbounded_String; --  blank while open
   end record;

   package Problem_Report_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Problem_Report);
   subtype Problem_Report_List is Problem_Report_Vectors.Vector;

   --  fusa:req REQ-089
   function Pr_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-pr.json. Returns an empty list if absent.
   --  fusa:req REQ-089
   function Load_Pr (Project_Root : String) return Problem_Report_List;

   --  fusa:req REQ-089
   procedure Save_Pr (Project_Root : String; Reports : Problem_Report_List);

   ------------------------------------------------------------------
   --  .fusa-metrics.json (append-only safety-metrics history)
   ------------------------------------------------------------------

   Metrics_File : constant String := ".fusa-metrics.json";

   type Metric_Snapshot is record
      At_Time          : Unbounded_String; --  RFC 3339
      Total_Reqs       : Natural := 0;
      Check_Errors     : Natural := 0;
      Check_Warnings   : Natural := 0;
      Check_Infos      : Natural := 0;
      Comp_Violations  : Natural := 0;
   end record;

   package Metric_Snapshot_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Metric_Snapshot);
   subtype Metric_Snapshot_List is Metric_Snapshot_Vectors.Vector;

   --  fusa:req REQ-094
   function Load_Metrics (Project_Root : String) return Metric_Snapshot_List;

   --  fusa:req REQ-094
   procedure Save_Metrics (Project_Root : String; Snapshots : Metric_Snapshot_List);

   ------------------------------------------------------------------
   --  .fusa-<standard>-objectives.json (spec section 9.2/9.3 standards
   --  gap-report commands: do178/iso26262/iso21434/iec61508/iec62443/
   --  unece/slsa). Like .fusa-hara.json/.fusa-tara.json, these are input
   --  files a human assessor fills in -- ada-FuSa has no way to
   --  automatically determine whether a given standard's objective is
   --  actually satisfied, so it validates/reports on whatever assessment
   --  a human has recorded rather than fabricating one.
   ------------------------------------------------------------------

   type Gap_Objective is record
      Id       : Unbounded_String;
      Title    : Unbounded_String;
      Clause   : Unbounded_String;
      Status   : Unbounded_String; --  "satisfied" | "partial" | "gap"
      Evidence : String_List;
      Findings : String_List;      --  rule ids
   end record;

   package Gap_Objective_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Gap_Objective);
   subtype Gap_Objective_List is Gap_Objective_Vectors.Vector;

   --  ".fusa-<standard-id>-objectives.json", e.g. ".fusa-do178c-objectives.json".
   --  fusa:req REQ-096
   function Gap_Objectives_File (Standard_Id : String) return String;

   --  fusa:req REQ-096
   function Gap_Objectives_Exist (Project_Root, Standard_Id : String) return Boolean;

   --  Loads the objectives file for Standard_Id. Returns an empty list if
   --  absent. An objective missing "id" is an ERROR finding (category
   --  requirement) and excluded from the returned list; an objective with
   --  an id but a "status" that isn't satisfied/partial/gap is a WARNING
   --  finding but the entry is still returned with Status left as given
   --  (the caller's summary counting simply won't recognise it).
   --  fusa:req REQ-096
   function Load_Gap_Objectives
     (Project_Root, Standard_Id : String;
      Findings                  : in out Finding_List) return Gap_Objective_List;

   --  Writes Starter as the objectives file for Standard_Id if it does not
   --  already exist (a no-op otherwise) -- Starter may be an empty list
   --  (the general case) or a tool-specific reference scaffold (do178).
   --  fusa:req REQ-096
   procedure Scaffold_Gap_Objectives
     (Project_Root, Standard_Id : String; Starter : Gap_Objective_List);

   ------------------------------------------------------------------
   --  .fusa-fmea.json (`fmea` command, #26: design FMEA). Same
   --  input-file-driven pattern as .fusa-hara.json/.fusa-tara.json --
   --  failure-mode identification and severity/occurrence/detection
   --  ratings are a human safety engineer's judgement, not something
   --  this tool can determine. The one thing it DOES compute is the RPN
   --  (severity * occurrence * detection) when the three ratings are all
   --  present, so a human never has to keep that arithmetic in sync by
   --  hand; a human-supplied "rpn" that disagrees with the computed value
   --  is flagged, not silently overwritten.
   ------------------------------------------------------------------

   Fmea_File : constant String := ".fusa-fmea.json";

   type Fmea_Entry is record
      Id           : Unbounded_String;
      Item         : Unbounded_String;
      Func         : Unbounded_String;
      Failure_Mode : Unbounded_String;
      Effect       : Unbounded_String;
      Cause        : Unbounded_String;
      Severity     : Natural := 0; --  0 = absent/invalid (valid range is 1..10)
      Occurrence   : Natural := 0;
      Detection    : Natural := 0;
      Rpn          : Natural := 0; --  Severity * Occurrence * Detection when all three are set
      Mitigation   : Unbounded_String;
   end record;

   package Fmea_Entry_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Fmea_Entry);
   subtype Fmea_Entry_List is Fmea_Entry_Vectors.Vector;

   --  fusa:req REQ-106
   function Fmea_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-fmea.json. Returns an empty list if absent. An entry
   --  missing "id" is an ERROR finding (category safety) and excluded; an
   --  entry whose severity/occurrence/detection is absent or outside
   --  1..10 is a WARNING (entry still returned, with that rating left at
   --  0 and no RPN computed); an explicit "rpn" that disagrees with the
   --  computed Severity*Occurrence*Detection is a WARNING.
   --  fusa:req REQ-106
   function Load_Fmea
     (Project_Root : String; Findings : in out Finding_List) return Fmea_Entry_List;

   --  fusa:req REQ-106
   procedure Scaffold_Fmea (Project_Root : String);

   ------------------------------------------------------------------
   --  .fusa-safety-case.json (`safety-case` command, #26: GSN goal
   --  structuring notation). Same input-file-driven pattern again --
   --  whether a safety-case argument is actually sound is a certification
   --  engineer's judgement this tool cannot make. It validates only
   --  structural well-formedness (every id unique and non-empty; every
   --  supportedBy/inContextOf reference resolves to a real node) and
   --  renders the argument graph; it never claims the argument itself is
   --  valid or complete.
   ------------------------------------------------------------------

   Safety_Case_File : constant String := ".fusa-safety-case.json";

   type Gsn_Node is record
      Id             : Unbounded_String;
      Kind           : Unbounded_String; --  goal|strategy|context|solution|assumption|justification
      Text           : Unbounded_String;
      Supported_By   : String_List;
      In_Context_Of  : String_List;
   end record;

   package Gsn_Node_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Gsn_Node);
   subtype Gsn_Node_List is Gsn_Node_Vectors.Vector;

   --  fusa:req REQ-107
   function Safety_Case_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-safety-case.json. Returns an empty list (and
   --  Root_Goal left blank) if absent. A node missing "id" is an ERROR
   --  and excluded; a "supportedBy"/"inContextOf" entry naming an id that
   --  doesn't resolve to any node in the file is an ERROR (a genuinely
   --  broken argument reference, not just an incomplete field) but does
   --  not remove the referencing node itself; an unrecognised/missing
   --  "kind" is a WARNING (the node is still returned, rendered
   --  generically). Root_Goal is the file's "rootGoal" field verbatim,
   --  even if it names an id that doesn't (yet) resolve -- callers that
   --  render a tree from it are expected to handle that gracefully.
   --  fusa:req REQ-107
   function Load_Safety_Case
     (Project_Root : String;
      Findings     : in out Finding_List;
      Root_Goal    : out Unbounded_String) return Gsn_Node_List;

   --  fusa:req REQ-107
   procedure Scaffold_Safety_Case (Project_Root : String);

end Fusa.Config;
