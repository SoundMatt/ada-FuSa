with Fusa.Files;
with Test_Framework; use Test_Framework;

procedure Test_Files is
begin
   --  Regression: Relative_To had no path-boundary check, so a directory
   --  name that is a literal prefix of an unrelated sibling produced a
   --  wrong "relative" path instead of returning Path unchanged.
   Check (Fusa.Files.Relative_To ("/foo/bar", "/foo/bar/x.adb") = "x.adb",
          "a genuine subdirectory still strips the prefix correctly");
   Check (Fusa.Files.Relative_To ("/foo/bar", "/foo/barbaz/x.adb") = "/foo/barbaz/x.adb",
          "a sibling directory that is merely a string-prefix of Root is "
          & "NOT treated as a subdirectory -- Path is returned unchanged");
   Check (Fusa.Files.Relative_To ("/foo/bar", "/foo/bar") = "/foo/bar",
          "Path identical to Root (no trailing separator) is returned unchanged, "
          & "not turned into an empty string");
   Check (Fusa.Files.Relative_To ("/foo", "/other/x.adb") = "/other/x.adb",
          "a completely unrelated path is returned unchanged");

   --  Regression: Join never normalised "." path segments, so a
   --  sourceDirs entry like "./src" leaked a literal "./" into every
   --  relative path built from it.
   Check (Fusa.Files.Join ("/proj", "./src") = "/proj/src",
          "a leading './' segment in Name is normalised away");
   Check (Fusa.Files.Join ("/proj/./sub", "x.adb") = "/proj/sub/x.adb",
          "an embedded '/./' segment in Dir is normalised away");
   Check (Fusa.Files.Join ("proj", "src") = "proj/src",
          "the ordinary no-dot case is unaffected");
   Check (Fusa.Files.Join ("proj/", "src") = "proj/src",
          "a trailing slash on Dir does not produce a double separator");

   declare
      Full : constant String := Fusa.Files.Join ("/proj", "./src");
   begin
      Check (Fusa.Files.Relative_To ("/proj", Fusa.Files.Join (Full, "x.adb")) = "src/x.adb",
             "a './'-prefixed sourceDirs entry produces the same relative "
             & "path as the plain form would");
   end;
end Test_Files;
