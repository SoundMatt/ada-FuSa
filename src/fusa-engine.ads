--  Rule registration/execution framework. Concrete rules (see
--  Fusa.Rules.Style) derive from Rule_Interface and register an instance
--  of themselves via Register, typically from their package body's
--  elaboration code -- see fusa-rules-style.adb.

package Fusa.Engine is

   type Rule_Interface is interface;

   --  fusa:req REQ-038
   function Id (R : Rule_Interface) return String is abstract;
   --  fusa:req REQ-038
   function Description (R : Rule_Interface) return String is abstract;

   --  Files are project-relative ("/" separated) .ads/.adb paths, as
   --  returned by Fusa.Source_Scan.Find_Source_Files.
   --  fusa:req REQ-039
   function Run
     (R : Rule_Interface; Project_Root : String; Files : String_List)
      return Finding_List is abstract;

   type Rule_Access is access all Rule_Interface'Class;

   Duplicate_Rule_Error : exception;

   --  Raises Duplicate_Rule_Error if a rule with the same Id is already
   --  registered.
   --  fusa:req REQ-040
   procedure Register (R : Rule_Access);

   --  fusa:req REQ-041
   function Rule_Count return Natural;

   --  1-indexed, rules ordered by ascending Id.
   --  fusa:req REQ-041
   function Get_Rule (Index : Positive) return Rule_Access;

   --  Runs every registered rule over Files and concatenates their
   --  findings, in rule-id order.
   --  fusa:req REQ-042
   function Run_All
     (Project_Root : String; Files : String_List) return Finding_List;

end Fusa.Engine;
