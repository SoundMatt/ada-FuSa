--  Root package of ada-FuSa: the functional safety enablement toolkit for
--  Ada/SPARK projects. Implements the x-FuSa spec (SoundMatt/FuSaOps
--  docs/x-fusa-spec.md) common data model shared by every command.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Vectors;

package Fusa is

   package String_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, String);
   subtype String_List is String_Vectors.Vector;

   Tool_Name    : constant String := "ada-FuSa";
   Version      : constant String := "0.1.0";
   Spec_Version : constant String := "1.11";

   --  §2.3 exit codes
   Exit_Ok        : constant := 0; --  success, no gate failure
   Exit_Gate_Fail : constant := 1; --  ran fine, found ERROR findings (or WARNING under --strict)
   Exit_Usage     : constant := 2; --  bad flag/argument
   Exit_Runtime   : constant := 3; --  could not complete analysis

   --  §2.4 severity enum
   type Severity_Kind is (Info, Warning, Error);
   function Image (S : Severity_Kind) return String;

   --  §4 finding category (closed enum)
   type Category_Kind is
     (Lint, Style, Safety, Security, Coverage, Requirement,
      Concurrency, Supply_Chain, Config_Category, Other);
   function Image (C : Category_Kind) return String;

   --  §4.1 disposition (open findings gate; accepted/deferred suppress)
   type Disposition_Kind is (Open, Accepted, Deferred, Rejected);
   function Image (D : Disposition_Kind) return String;

   type Location is record
      File       : Unbounded_String; --  project-relative, "/" separators
      Line       : Natural := 0;     --  1-indexed, 0 = unset
      Column     : Natural := 0;
      End_Line   : Natural := 0;
      End_Column : Natural := 0;
   end record;

   function Make_Location
     (File       : String;
      Line       : Natural := 0;
      Column     : Natural := 0;
      End_Line   : Natural := 0;
      End_Column : Natural := 0) return Location;

   type Finding is record
      Rule_Id     : Unbounded_String;
      Severity    : Severity_Kind;
      Message     : Unbounded_String;
      Loc         : Location;
      Category    : Category_Kind := Other;
      Standard    : Unbounded_String;
      Clause      : Unbounded_String;
      Remediation : Unbounded_String;
      Disposition : Disposition_Kind := Open;
      Fingerprint : Unbounded_String;
   end record;

   package Finding_Vectors is new Ada.Containers.Indefinite_Vectors (Positive, Finding);
   subtype Finding_List is Finding_Vectors.Vector;

   --  Builds a Finding and computes its §4.2 fingerprint automatically.
   function Make_Finding
     (Rule_Id     : String;
      Severity    : Severity_Kind;
      Message     : String;
      Loc         : Location;
      Category    : Category_Kind := Other;
      Standard    : String := "";
      Clause      : String := "";
      Remediation : String := "";
      Disposition : Disposition_Kind := Open) return Finding;

   --  §1.5.1 prefix -> category registry. Unrecognised prefixes map to Other.
   function Derive_Category (Rule_Id : String) return Category_Kind;

   --  §4.2 message normalisation: digit runs -> '#', whitespace collapsed,
   --  trimmed. (Unicode NFC normalisation for non-ASCII input is not
   --  applied -- see README "Known limitations".)
   function Normalize_Message (Msg : String) return String;

   --  §4.2 canonical fingerprint: "sha256:" & lowercase_hex(SHA-256(
   --  Rule_Id & US & Loc.File & US & Normalize_Message(Message))),
   --  where US is ASCII Unit Separator (0x1F).
   function Compute_Fingerprint (F : Finding) return String;

end Fusa;
