with Ada.Directories;
with Interfaces.C; use Interfaces.C;
with Interfaces.C.Strings;
with Fusa; use Fusa;
with Fusa.Files;
with Test_Framework; use Test_Framework;

procedure Test_Files is
   Root : constant String := "tmp_test_files";
begin
   if Ada.Directories.Exists (Root) then
      Ada.Directories.Delete_Tree (Root);
   end if;
   Ada.Directories.Create_Path (Root & "/sub");

   --  fusa:test REQ-057
   --  fusa:test REQ-058
   --  fusa:test REQ-059
   Check (not Fusa.Files.Exists (Root & "/x.txt"), "Exists is false before the file is written");
   Fusa.Files.Write_File (Root & "/x.txt", "line one" & ASCII.LF & "line two");
   Check (Fusa.Files.Exists (Root & "/x.txt"), "Exists is true once Write_File has written it");
   Check (not Fusa.Files.Is_Directory (Root & "/x.txt"),
          "Is_Directory is false for a plain file");
   Check (Fusa.Files.Is_Directory (Root & "/sub"), "Is_Directory is true for a directory");
   Check (Fusa.Files.Read_File (Root & "/x.txt") = "line one" & ASCII.LF & "line two",
          "Read_File returns exactly what Write_File wrote (a round trip)");

   --  fusa:test REQ-062
   declare
      Lines : constant String_List := Fusa.Files.Split_Lines ("a" & ASCII.LF & "b" & ASCII.LF);
   begin
      Check (Natural (Lines.Length) = 2
             and then Lines.Element (1) = "a" and then Lines.Element (2) = "b",
             "Split_Lines splits LF-separated content into individual lines");
   end;
   declare
      Lines : constant String_List := Fusa.Files.Split_Lines ("a" & ASCII.CR & ASCII.LF & "b");
   begin
      Check (Natural (Lines.Length) = 2 and then Lines.Element (1) = "a",
             "Split_Lines strips a trailing CR, so CRLF line endings work too");
   end;

   Ada.Directories.Delete_Tree (Root);

   --  Regression: Relative_To had no path-boundary check, so a directory
   --  name that is a literal prefix of an unrelated sibling produced a
   --  wrong "relative" path instead of returning Path unchanged.
   --  fusa:test REQ-061
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
   --  fusa:test REQ-060
   Check (Fusa.Files.Join ("/proj", "./src") = "/proj/src",
          "a leading './' segment in Name is normalised away");
   Check (Fusa.Files.Join ("/proj/./sub", "x.adb") = "/proj/sub/x.adb",
          "an embedded '/./' segment in Dir is normalised away");
   Check (Fusa.Files.Join ("proj", "src") = "proj/src",
          "the ordinary no-dot case is unaffected");
   Check (Fusa.Files.Join ("proj/", "src") = "proj/src",
          "a trailing slash on Dir does not produce a double separator");

   --  Regression (security): Join never resolved ".." segments, so
   --  Join("/proj", "../outside") produced the literal string
   --  "/proj/../outside" -- which Relative_To's purely-lexical prefix
   --  check then WRONGLY treated as "inside" /proj (the string does
   --  start with "/proj/"), silently letting a sourceDirs entry escape
   --  the project root for both reads and, downstream via `fix --apply`,
   --  writes.
   --  fusa:test REQ-060
   Check (Fusa.Files.Join ("/proj", "../outside") = "/outside",
          "'..' actually climbs out of the preceding real segment, not "
          & "left as a literal (still-escaping) path component");
   Check (Fusa.Files.Join ("/proj", "src/../../../etc") = "/etc",
          "multiple '..' segments climb correctly, stopping at '/' "
          & "rather than underflowing");
   Check (Fusa.Files.Join ("/proj", "a/b/../c") = "/proj/a/c",
          "an interior '..' pops exactly the one preceding real segment");
   Check (Fusa.Files.Join ("/proj", "..") = "/",
          "a bare '..' climbs to the parent of an absolute Dir");
   Check (Fusa.Files.Relative_To ("/proj", Fusa.Files.Join ("/proj", "../outside")) =
            "/outside",
          "once '..' is resolved, Relative_To correctly reports the escaped "
          & "path as NOT inside /proj (returned unchanged, still absolute) "
          & "instead of silently stripping a prefix that was never really there");

   --  fusa:test REQ-117
   Check (Fusa.Files.Is_Within ("/proj", "/proj"), "Root is within itself");
   Check (Fusa.Files.Is_Within ("/proj", "/proj/src/x.adb"),
          "a genuine subdirectory/file is within Root");
   Check (not Fusa.Files.Is_Within ("/proj", "/projbackup/x.adb"),
          "a sibling that is merely a string-prefix of Root is NOT within it");
   Check (not Fusa.Files.Is_Within ("/proj", "/outside/x.adb"),
          "a completely unrelated path is not within Root");

   declare
      Full : constant String := Fusa.Files.Join ("/proj", "./src");
   begin
      Check (Fusa.Files.Relative_To ("/proj", Fusa.Files.Join (Full, "x.adb")) = "src/x.adb",
             "a './'-prefixed sourceDirs entry produces the same relative "
             & "path as the plain form would");
   end;

   --  fusa:test REQ-118
   --  Regression: Write_File used to be the only overwrite primitive,
   --  meaning `fix --apply` wrote directly through whatever Path
   --  currently resolved to at the moment of the call -- a TOCTOU window
   --  between the earlier Read_File and the write. Write_File_Atomic
   --  writes to a temp file and renames onto Path instead.
   declare
      Atomic_Root : constant String := "tmp_test_files_atomic";
   begin
      if Ada.Directories.Exists (Atomic_Root) then
         Ada.Directories.Delete_Tree (Atomic_Root);
      end if;
      Ada.Directories.Create_Path (Atomic_Root);

      Fusa.Files.Write_File (Atomic_Root & "/target.txt", "original content");
      Fusa.Files.Write_File_Atomic (Atomic_Root & "/target.txt", "replacement content");
      Check (Fusa.Files.Read_File (Atomic_Root & "/target.txt") = "replacement content",
             "Write_File_Atomic overwrites an existing file's content, "
             & "same observable result as Write_File");
      Check (not Fusa.Files.Exists (Atomic_Root & "/target.txt.fusa-fix-tmp"),
             "the temp file used internally is renamed away, not left behind");

      --  The actual security property: even if Path has become a symlink
      --  since it was last read, Write_File_Atomic must never write
      --  through it -- POSIX rename() replaces the symlink *entry*
      --  itself, not whatever it points to.
      declare
         function C_Symlink
           (Target, Linkpath : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int;
         pragma Import (C, C_Symlink, "symlink");

         Sensitive_Path : constant String := Atomic_Root & "/sensitive.txt";
         Link_Path      : constant String := Atomic_Root & "/link.txt";
         Target_C, Link_C : Interfaces.C.Strings.chars_ptr;
         Rc               : Interfaces.C.int;
      begin
         Fusa.Files.Write_File (Sensitive_Path, "SENSITIVE - must not be overwritten");
         Target_C := Interfaces.C.Strings.New_String ("sensitive.txt");
         Link_C   := Interfaces.C.Strings.New_String (Link_Path);
         Rc := C_Symlink (Target_C, Link_C);
         Interfaces.C.Strings.Free (Target_C);
         Interfaces.C.Strings.Free (Link_C);
         Check (Rc = 0, "test setup: symlink() succeeded");

         Fusa.Files.Write_File_Atomic (Link_Path, "attacker-controlled content");

         Check (Fusa.Files.Read_File (Sensitive_Path) = "SENSITIVE - must not be overwritten",
                "the symlink's TARGET is untouched -- Write_File_Atomic never "
                & "wrote through it, unlike a plain Create/Write to the same path");
         Check (Fusa.Files.Read_File (Link_Path) = "attacker-controlled content",
                "the path that was a symlink now holds the new content directly "
                & "-- rename() replaced the symlink entry itself with a regular file");
      end;

      Ada.Directories.Delete_Tree (Atomic_Root);
   end;
end Test_Files;
