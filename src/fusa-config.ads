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

   function Default_Config (Name : String) return Project_Config;

   --  True if a canonical or legacy config file exists under Project_Root.
   function Exists (Project_Root : String) return Boolean;

   --  Loads .fusa.json (falling back to legacy .adafusa.json with a stderr
   --  deprecation warning when only the legacy name exists -- canonical
   --  wins when both are present). Raises No_Config_Error / Invalid_Config_Error.
   --  fusa:req REQ-005
   function Load (Project_Root : String) return Project_Config;

   --  Writes the canonical §1.2.1 shape (always the nested `project` form).
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
   function Requirements_Exist (Project_Root : String) return Boolean;

   --  Loads .fusa-reqs.json (or legacy). Returns an empty list if absent.
   --  A duplicate `id` within the file MUST surface as an ERROR finding
   --  (category requirement) per spec §1.2 rather than being silently
   --  merged or dropped -- such findings are appended to Findings.
   --  fusa:req REQ-006
   function Load_Requirements
     (Project_Root : String;
      Findings     : in out Finding_List) return Requirement_List;

   procedure Save_Requirements
     (Project_Root : String; Reqs : Requirement_List);

end Fusa.Config;
