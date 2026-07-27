--  Trivial Rule_Interface implementations used only by Test_Engine, kept
--  in their own library-level package (rather than declared inside the
--  Test_Engine procedure body) so `new Dummy_Rule`/`new First_Rule` are
--  convertible to Fusa.Engine.Rule_Access (a library-level general access
--  type) -- Ada's accessibility rules reject that conversion for a type
--  declared inside a subprogram body.

with Fusa; use Fusa;
with Fusa.Engine;

package Test_Engine_Rules is

   type Dummy_Rule is new Fusa.Engine.Rule_Interface with null record;
   overriding function Id (R : Dummy_Rule) return String;
   overriding function Description (R : Dummy_Rule) return String;
   overriding function Run
     (R : Dummy_Rule; Project_Root : String; Files : String_List)
      return Finding_List;

   --  Sorts before every already-registered rule id ("ADA001".."ADA008"),
   --  exercising Register's "insert before an existing entry" branch.
   type First_Rule is new Fusa.Engine.Rule_Interface with null record;
   overriding function Id (R : First_Rule) return String;
   overriding function Description (R : First_Rule) return String;
   overriding function Run
     (R : First_Rule; Project_Root : String; Files : String_List)
      return Finding_List;

end Test_Engine_Rules;
