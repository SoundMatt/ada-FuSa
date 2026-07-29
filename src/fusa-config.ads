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

   --  section 1.2.5 canonical shape: three cross-referenced top-level
   --  collections, not a flat hazard list -- a hazard can manifest in
   --  several operational situations and drive several safety goals, and
   --  a safety goal can be derived from several hazards.

   type Operational_Situation is record
      Id          : Unbounded_String;
      Description : Unbounded_String;
   end record;

   package Operational_Situation_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Operational_Situation);
   subtype Operational_Situation_List is Operational_Situation_Vectors.Vector;

   type Hazard_Risk is record
      Severity        : Unbounded_String; --  S0-S3
      Exposure        : Unbounded_String; --  E0-E4
      Controllability : Unbounded_String; --  C0-C3
      --  MUST be derived from Severity x Exposure x Controllability per
      --  ISO 26262-3:2018 Table 4 (see Fusa.Config.Determine_Asil), not
      --  accepted verbatim from the input file.
      Asil            : Unbounded_String;
   end record;

   type Hazard is record
      Id           : Unbounded_String;
      Description  : Unbounded_String;
      Source       : Unbounded_String;
      Situations   : String_List; --  ids into Operational_Situations
      Risk         : Hazard_Risk;
      Safety_Goals : String_List; --  ids into Safety_Goals
   end record;

   package Hazard_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Hazard);
   subtype Hazard_List is Hazard_Vectors.Vector;

   type Safety_Goal is record
      Id          : Unbounded_String;
      Description : Unbounded_String;
      Hazards     : String_List; --  ids back into Hazard_List
      Asil        : Unbounded_String;
      Safe_State  : Unbounded_String;
      --  MUST have >= 1 entry, each resolving into .fusa-reqs.json --
      --  a safety goal with no decomposing requirement is exactly the
      --  traceability gap ISO 26262-8 Clause 6 exists to prevent.
      Fssr_Refs   : String_List;
   end record;

   package Safety_Goal_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Safety_Goal);
   subtype Safety_Goal_List is Safety_Goal_Vectors.Vector;

   type Hara_Document is record
      Project                : Unbounded_String;
      Standard               : Unbounded_String;
      Created_At             : Unbounded_String;
      Operational_Situations : Operational_Situation_List;
      Hazards                : Hazard_List;
      Safety_Goals           : Safety_Goal_List;
      --  Count of cross-reference ids (hazards[].situations/safetyGoals,
      --  safetyGoals[].hazards/fssrRefs) that failed to resolve -- feeds
      --  the JSON output's draft "completeness" block.
      Dangling_References    : Natural := 0;
   end record;

   --  fusa:req REQ-082
   function Hara_Exists (Project_Root : String) return Boolean;

   --  Derives an ASIL rating from Severity x Exposure x Controllability
   --  per the published ISO 26262-3:2018 Table 4 determination -- see the
   --  body for the full 3x4x3 lookup. Returns "" if any of the three
   --  inputs is not a recognised S1-S3/E1-E4/C1-C3 code (S0/E0 and
   --  anything else fail safe to "" rather than guessing).
   --  fusa:req REQ-082
   function Determine_Asil
     (Severity, Exposure, Controllability : String) return String;

   --  Loads and validates .fusa-hara.json (section 1.2.5). Returns an
   --  empty document if absent -- callers that must distinguish "absent"
   --  from "present but empty" should check Hara_Exists first (see the
   --  hara command's --init handling). A hazard/situation/safety goal
   --  missing "id" is an ERROR finding (category safety); missing any
   --  other required field, a dangling cross-reference (situations/
   --  safetyGoals/hazards ids that don't resolve within the file, or a
   --  fssrRefs id that doesn't resolve into .fusa-reqs.json), or an
   --  unrecognised severity/exposure/controllability code is a WARNING.
   --  fusa:req REQ-082
   function Load_Hara
     (Project_Root : String;
      Findings     : in out Finding_List) return Hara_Document;

   --  Writes an empty-collections template (never dummy rows -- section
   --  1.6) if .fusa-hara.json does not already exist; a no-op (does not
   --  overwrite) if it does.
   --  fusa:req REQ-082
   procedure Scaffold_Hara (Project_Root : String; Standard : String; Project : String := "");

   ------------------------------------------------------------------
   --  .fusa-tara.json (spec section 13 "canonical direction": threat
   --  analysis & risk assessment, ISO 21434 ch.9 -- same input/
   --  validate/scaffold pattern as .fusa-hara.json)
   ------------------------------------------------------------------

   Tara_File : constant String := ".fusa-tara.json";

   --  section 9.2 canonical tara.json shape: impact is a per-category SFOP
   --  (Safety/Financial/Operational/Privacy) object, not a single generic
   --  severity -- a threat can rate differently on each axis.
   type Sfop_Impact is record
      Safety      : Unbounded_String;
      Financial   : Unbounded_String;
      Operational : Unbounded_String;
      Privacy     : Unbounded_String;
   end record;

   type Threat_Location is record
      Present : Boolean := False;
      File    : Unbounded_String;
      Line    : Natural := 0;
   end record;

   type Threat is record
      Id                 : Unbounded_String;
      Asset              : Unbounded_String;
      Description        : Unbounded_String;
      Cwe                : Unbounded_String; --  SHOULD, e.g. "CWE-78"
      Attack_Vector      : Unbounded_String;
      Attack_Feasibility : Unbounded_String; --  high|medium|low|very-low
      Impact             : Sfop_Impact;
      --  MUST be derived from Attack_Feasibility x the highest SFOP
      --  impact level (see Fusa.Config.Determine_Tara_Risk), not accepted
      --  verbatim from the input file.
      Risk               : Unbounded_String;
      Treatment          : Unbounded_String; --  mitigate|accept|transfer|avoid
      Mitigations        : String_List;
      Location           : Threat_Location;
      Cyber_Rule_Id      : Unbounded_String;
   end record;

   package Threat_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Threat);
   subtype Threat_List is Threat_Vectors.Vector;

   type Tara_Document is record
      Threats                 : Threat_List;
      --  Optional override for the summary.assetsInProject coverage
      --  denominator (no automated asset-discovery mechanism exists, so
      --  this is sourced from the input file); defaults to the number of
      --  distinct assets actually analysed (100% coverage) when absent.
      Assets_In_Project       : Natural := 0;
      Assets_In_Project_Given : Boolean := False;
      Asset_Inventory_Method  : Unbounded_String;
   end record;

   --  fusa:req REQ-083
   function Tara_Exists (Project_Root : String) return Boolean;

   --  Derives a risk rating from Attack_Feasibility and the highest-ranked
   --  of the four SFOP impact axes, via the x-FuSa family's own canonical
   --  feasibility x impact -> risk combination table (spec section 9.2,
   --  v1.14.1) -- ISO/SAE 21434 deliberately leaves risk determination
   --  organization-defined (Clause 15.3), so this table is the family's
   --  shared convention, not a claimed external standard. Impact axes use
   --  the closed enum critical|major|moderate|negligible (ranked in that
   --  order); Attack_Feasibility uses the separate closed enum
   --  high|medium|low|very-low -- the two are deliberately distinct
   --  scales for distinct questions (damage vs. likelihood) and MUST NOT
   --  be conflated. Returns "" if Attack_Feasibility, or every one of the
   --  four impact axes, is not a recognised value.
   --  fusa:req REQ-083
   function Determine_Tara_Risk
     (Attack_Feasibility : String; Impact : Sfop_Impact) return String;

   --  Same validation rule as Load_Hara: missing "id"/"asset"/"threat" is
   --  an ERROR (category security); missing any other required field, or
   --  an unrecognised attackFeasibility/impact level, is a WARNING.
   --  fusa:req REQ-083
   function Load_Tara
     (Project_Root : String;
      Findings     : in out Finding_List) return Tara_Document;

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

   --  section 9.2 (v1.13.0+) canonical shape: "item" is the sole
   --  component/function identifier (no separate "function" field --
   --  that was this codebase's own pre-conformance addition), plus a
   --  MUST "file" field, a SHOULD "actionPriority" (supersedes raw RPN
   --  per the AIAG-VDA Handbook's own move away from single-threshold
   --  RPN), and a SHOULD "requirementIds" back-link.
   type Fmea_Entry is record
      Id              : Unbounded_String;
      Item            : Unbounded_String;
      File            : Unbounded_String;
      Failure_Mode    : Unbounded_String;
      Effect          : Unbounded_String;
      Cause           : Unbounded_String;
      Severity        : Natural := 0; --  0 = absent/invalid (valid range is 1..10)
      Occurrence      : Natural := 0;
      Detection       : Natural := 0;
      Rpn             : Natural := 0; --  Severity * Occurrence * Detection when all three are set
      Action_Priority : Unbounded_String; --  "high" | "medium" | "low"
      Mitigations     : String_List;
      Requirement_Ids : String_List;
   end record;

   package Fmea_Entry_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Fmea_Entry);
   subtype Fmea_Entry_List is Fmea_Entry_Vectors.Vector;

   type Fmea_Document is record
      --  "aiag-vda-2019" whenever occurrence/detection are emitted (MUST
      --  in that case, per section 9.2) -- this tool has exactly one
      --  rating scale, so it is always set once any entry has ratings.
      Rating_Scale                : Unbounded_String;
      Entries                     : Fmea_Entry_List;
      --  Optional override for summary.componentsInProject (mirrors
      --  Tara_Document.Assets_In_Project) -- defaults to the real
      --  public-function count from Fusa.Func_Scan when absent.
      Components_In_Project       : Natural := 0;
      Components_In_Project_Given : Boolean := False;
   end record;

   --  fusa:req REQ-106
   function Fmea_Exists (Project_Root : String) return Boolean;

   --  Loads and validates .fusa-fmea.json. Returns an empty document if
   --  absent. An entry missing "id" is an ERROR finding (category
   --  safety) and excluded; an entry missing "item"/"file"/
   --  "failureMode"/"effect" (all MUST) is a WARNING; an entry whose
   --  severity/occurrence/detection is absent or outside 1..10 is a
   --  WARNING (entry still returned, with that rating left at 0 and no
   --  RPN computed); an explicit "rpn" that disagrees with the computed
   --  Severity*Occurrence*Detection is a WARNING.
   --  fusa:req REQ-106
   function Load_Fmea
     (Project_Root : String; Findings : in out Finding_List) return Fmea_Document;

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
      Evidence       : Unbounded_String; --  solution nodes SHOULD set (§9.2)
      Supported_By   : String_List;
      In_Context_Of  : String_List;
   end record;

   package Gsn_Node_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Gsn_Node);
   subtype Gsn_Node_List is Gsn_Node_Vectors.Vector;

   type Gsn_Completeness is record
      Total_Goals        : Natural := 0;
      Goals_With_Evidence : Natural := 0;
      Undeveloped         : Natural := 0;
   end record;

   --  fusa:req REQ-107
   function Safety_Case_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-safety-case.json. Returns an empty list (and
   --  Root_Goal left blank) if absent. A node missing "id" is an ERROR
   --  and excluded; a "supportedBy"/"inContextOf" entry naming an id that
   --  doesn't resolve to any node in the file is an ERROR (a genuinely
   --  broken argument reference, not just an incomplete field) but does
   --  not remove the referencing node itself; an unrecognised/missing
   --  "kind" is a WARNING (the node is still returned, rendered
   --  generically); a solution node whose "evidence" names a file that
   --  does not exist in the project is a WARNING (GSN004) -- a claim of
   --  evidence the project doesn't actually contain is worse than an
   --  honestly missing solution (§9.2). Root_Goal is the file's
   --  "rootGoal" field verbatim, even if it names an id that doesn't
   --  (yet) resolve -- callers that render a tree from it are expected
   --  to handle that gracefully.
   --  fusa:req REQ-107
   function Load_Safety_Case
     (Project_Root : String;
      Findings     : in out Finding_List;
      Root_Goal    : out Unbounded_String) return Gsn_Node_List;

   --  Computes the §9.2 "completeness" block: totalGoals is the count of
   --  "goal"-typed nodes; goalsWithEvidence is how many of those have a
   --  supportedBy chain (transitively) reaching a solution node with a
   --  non-blank evidence field; undeveloped is how many goals have no
   --  supportedBy chain at all.
   --  fusa:req REQ-107
   function Safety_Case_Completeness
     (Nodes : Gsn_Node_List) return Gsn_Completeness;

   --  fusa:req REQ-107
   procedure Scaffold_Safety_Case (Project_Root : String);

   ------------------------------------------------------------------
   --  .fusa-verify.json (`verify` command, #26/spec §13 canonical
   --  direction: `{ passed, failed, suites:[{name,passed,failed,
   --  tests:[{name,result}]}] }`, "result" per spec section 6's
   --  PASS|FAIL|SKIP|ERROR enum). Same input-file-driven pattern as
   --  hara/tara/fmea -- ada-FuSa cannot itself determine whether a
   --  project's verification activities passed; a human or a CI pipeline
   --  records each test's outcome, and this command only aggregates and
   --  validates the counts, never fabricates a result.
   ------------------------------------------------------------------

   Verify_File : constant String := ".fusa-verify.json";

   type Verify_Test is record
      Name   : Unbounded_String;
      Result : Unbounded_String; --  PASS | FAIL | SKIP | ERROR
   end record;

   package Verify_Test_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Verify_Test);
   subtype Verify_Test_List is Verify_Test_Vectors.Vector;

   type Verify_Suite is record
      Name  : Unbounded_String;
      Tests : Verify_Test_List;
   end record;

   package Verify_Suite_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Verify_Suite);
   subtype Verify_Suite_List is Verify_Suite_Vectors.Vector;

   --  fusa:req REQ-099
   function Verify_Exists (Project_Root : String) return Boolean;

   --  Loads .fusa-verify.json. Returns an empty list if absent. A suite
   --  missing "name" is an ERROR (excluded, along with all its tests); a
   --  test missing "name" is an ERROR (excluded); a test with a missing
   --  or unrecognised "result" is a WARNING (kept, but counted toward
   --  neither Passed nor Failed). Passed/Failed are always COMPUTED from
   --  the individual tests[], never trusted from redundant input fields,
   --  the same way fmea's rpn is computed rather than blindly accepted.
   --  fusa:req REQ-099
   function Load_Verify
     (Project_Root : String;
      Findings     : in out Finding_List;
      Passed, Failed : out Natural) return Verify_Suite_List;

   --  fusa:req REQ-099
   procedure Scaffold_Verify (Project_Root : String);

end Fusa.Config;
