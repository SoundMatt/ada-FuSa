with Fusa; use Fusa;
with Fusa.Glob;
with Test_Framework; use Test_Framework;

procedure Test_Glob is
begin
   Check (Fusa.Glob.Match ("*.adb", "foo.adb"), "'*' matches a simple filename");
   Check (not Fusa.Glob.Match ("*.adb", "foo.ads"), "'*' pattern rejects wrong extension");
   Check (not Fusa.Glob.Match ("*.adb", "sub/foo.adb"),
          "single '*' does not cross a '/'");
   Check (Fusa.Glob.Match ("**/foo.adb", "a/b/foo.adb"), "'**' crosses multiple '/'");
   Check (Fusa.Glob.Match ("foo?.adb", "foo1.adb"), "'?' matches exactly one character");
   Check (not Fusa.Glob.Match ("foo?.adb", "foo12.adb"), "'?' does not match two characters");

   declare
      Patterns : String_List;
   begin
      Patterns.Append ("*.gen.adb");
      Check (Fusa.Glob.Is_Excluded (Patterns, "src/thing.gen.adb"),
             "no-slash pattern matches the basename anywhere in the tree");
      Check (not Fusa.Glob.Is_Excluded (Patterns, "src/thing.adb"),
             "non-matching file is not excluded");
   end;

   declare
      Patterns : String_List;
   begin
      Patterns.Append ("obj");
      Check (Fusa.Glob.Is_Excluded (Patterns, "obj/generated/x.adb"),
             "no-slash pattern also excludes by directory-segment name");
   end;

   declare
      Patterns : String_List;
   begin
      Patterns.Append ("src/vendor/*.adb");
      Check (Fusa.Glob.Is_Excluded (Patterns, "src/vendor/lib.adb"),
             "slash-anchored pattern matches the full relative path");
      Check (not Fusa.Glob.Is_Excluded (Patterns, "src/other/lib.adb"),
             "slash-anchored pattern does not match a different directory");
   end;
end Test_Glob;
