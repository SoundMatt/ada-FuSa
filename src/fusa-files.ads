--  Small file-system helpers shared by every command that reads project
--  files or writes evidence artifacts.

package Fusa.Files is

   --  fusa:req REQ-057
   function Exists (Path : String) return Boolean;
   --  fusa:req REQ-057
   function Is_Directory (Path : String) return Boolean;

   Read_Error  : exception;
   Write_Error : exception;

   --  Reads the entire file as a raw byte string (see Fusa.Sha256 for the
   --  "Character = one byte" convention used throughout ada-FuSa).
   --  fusa:req REQ-058
   function Read_File (Path : String) return String;

   --  Writes Content to Path, creating/overwriting it. Parent directories
   --  are not created.
   --  fusa:req REQ-059
   procedure Write_File (Path : String; Content : String);

   --  Same effect as Write_File, but closes the TOCTOU window between a
   --  caller's earlier Read_File(Path) and this write: Content is written
   --  to a fresh temporary file in Path's own directory, then atomically
   --  renamed onto Path (POSIX rename() replaces whatever is at the
   --  destination -- including a symlink entry itself, not whatever it
   --  points to -- so even if Path was swapped for a symlink after the
   --  read, this cannot be tricked into writing through it to an
   --  unintended location). For commands like `fix --apply` that
   --  overwrite a file based on content read moments earlier, unlike
   --  Write_File's plain create-or-truncate, which writes directly
   --  through whatever Path currently resolves to at the moment of the
   --  call.
   --  fusa:req REQ-118
   procedure Write_File_Atomic (Path : String; Content : String);

   --  Joins a directory and a relative path with exactly one "/".
   --  fusa:req REQ-060
   function Join (Dir, Name : String) return String;

   --  Returns Path relative to Root with "/" separators, for use as a
   --  Finding.Loc.File value (spec §3.2: project-relative, never absolute).
   --  If Path does not start with Root, Path is returned unchanged.
   --  fusa:req REQ-061
   function Relative_To (Root, Path : String) return String;

   --  Splits Content into lines on LF, stripping a trailing CR from each
   --  line (so both Unix and Windows line endings work).
   --  fusa:req REQ-062
   function Split_Lines (Content : String) return String_List;

   --  True if Path is Root itself, or a genuine subdirectory/file inside
   --  Root -- the same path-boundary rule Relative_To uses (a sibling
   --  directory that is merely a string-prefix of Root, e.g.
   --  Root="/foo/bar" and Path="/foo/barbaz", is NOT "within"). Both
   --  arguments are expected to already be lexically normalised (e.g. via
   --  Join, which resolves ".." segments) -- this is a string-boundary
   --  check, not a filesystem canonicalisation, so it does not protect
   --  against a symlink inside Root pointing outside it.
   --  fusa:req REQ-117
   function Is_Within (Root, Path : String) return Boolean;

end Fusa.Files;
