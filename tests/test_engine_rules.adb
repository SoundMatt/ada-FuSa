package body Test_Engine_Rules is

   function Id (R : Dummy_Rule) return String is ("ADA001");
   function Description (R : Dummy_Rule) return String is ("dummy");
   function Run
     (R : Dummy_Rule; Project_Root : String; Files : String_List)
      return Finding_List
   is
      Empty : Finding_List;
   begin
      return Empty;
   end Run;

   function Id (R : First_Rule) return String is ("AAA001");
   function Description (R : First_Rule) return String is ("first");
   function Run
     (R : First_Rule; Project_Root : String; Files : String_List)
      return Finding_List
   is
      Empty : Finding_List;
   begin
      return Empty;
   end Run;

end Test_Engine_Rules;
