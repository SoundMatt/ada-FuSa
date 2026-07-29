with Fusa; use Fusa;
with Fusa.Glob;
with Test_Framework; use Test_Framework;

procedure Test_Glob is
begin
   --  fusa:test REQ-048
   Check (Fusa.Glob.Match ("*.adb", "foo.adb"), "'*' matches a simple filename");
   Check (not Fusa.Glob.Match ("*.adb", "foo.ads"), "'*' pattern rejects wrong extension");
   Check (not Fusa.Glob.Match ("*.adb", "sub/foo.adb"),
          "single '*' does not cross a '/'");
   Check (Fusa.Glob.Match ("**/foo.adb", "a/b/foo.adb"), "'**' crosses multiple '/'");
   Check (Fusa.Glob.Match ("foo?.adb", "foo1.adb"), "'?' matches exactly one character");
   Check (not Fusa.Glob.Match ("foo?.adb", "foo12.adb"), "'?' does not match two characters");

   --  fusa:test REQ-049
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

   --  fusa:test REQ-048
   --  Regression: Match_Rec used to be a naive recursive backtracking
   --  matcher -- exponential time on a pattern with many '*' atoms
   --  against text with no valid match. excludePatterns is untrusted
   --  project config, so a crafted pattern could hang any source-scanning
   --  command. This is a canary: if the DP-based matcher ever regresses
   --  back to exponential recursion, this test (a moderately adversarial
   --  case, deliberately not huge so the *fixed* matcher still runs this
   --  instantly) will hang the whole suite rather than fail fast.
   declare
      Adversarial_Pattern : constant String :=
        "a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*a*ab";
      Adversarial_Text    : constant String (1 .. 40) := (others => 'a');
   begin
      Check (not Fusa.Glob.Match (Adversarial_Pattern, Adversarial_Text),
             "an adversarial many-'*' pattern against non-matching text "
             & "resolves (in polynomial time, not exponential) to no match");
   end;

   --  fusa:test REQ-048: '*' still matches zero characters (an empty run)
   Check (Fusa.Glob.Match ("foo*.adb", "foo.adb"),
          "'*' matches a zero-length run");
   --  fusa:test REQ-048: three consecutive '*' == "**" + "*" (matches the
   --  original greedy two-at-a-time consumption exactly)
   Check (Fusa.Glob.Match ("a***b", "a/x/yb"),
          "three consecutive '*' behaves as '**' followed by '*'");
   --  fusa:test REQ-048: empty pattern/text edge cases
   Check (Fusa.Glob.Match ("", ""), "empty pattern matches empty text");
   Check (not Fusa.Glob.Match ("", "x"),
          "empty pattern does not match non-empty text");
   Check (Fusa.Glob.Match ("**", ""), "'**' alone matches empty text");
   Check (Fusa.Glob.Match ("**", "a/b/c"), "'**' alone matches everything");
end Test_Glob;
