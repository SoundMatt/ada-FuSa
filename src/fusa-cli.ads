--  §9.1 command dispatch. Args excludes argv[0] (the program name).

package Fusa.Cli is

   function Run (Args : String_List) return Integer;

end Fusa.Cli;
