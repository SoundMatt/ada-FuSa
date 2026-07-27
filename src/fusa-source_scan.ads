with Fusa.Config;

package Fusa.Source_Scan is

   --  Returns project-relative ("/"-separated) paths of every .ads/.adb
   --  file under Cfg.Source_Dirs (or the whole Project_Root when
   --  Source_Dirs is empty), honouring Cfg.Exclude_Patterns and always
   --  skipping .git, obj, bin, alire, and .alire directories.
   function Find_Source_Files
     (Project_Root : String; Cfg : Fusa.Config.Project_Config) return String_List;

end Fusa.Source_Scan;
