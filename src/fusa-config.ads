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

end Fusa.Config;
