--  Small file-system helpers shared by every command that reads project
--  files or writes evidence artifacts.

package Fusa.Files is

   function Exists (Path : String) return Boolean;
   function Is_Directory (Path : String) return Boolean;

   Read_Error : exception;

   --  Reads the entire file as a raw byte string (see Fusa.Sha256 for the
   --  "Character = one byte" convention used throughout ada-FuSa).
   function Read_File (Path : String) return String;

   --  Writes Content to Path, creating/overwriting it. Parent directories
   --  are not created.
   procedure Write_File (Path : String; Content : String);

   --  Joins a directory and a relative path with exactly one "/".
   function Join (Dir, Name : String) return String;

   --  Returns Path relative to Root with "/" separators, for use as a
   --  Finding.Loc.File value (spec §3.2: project-relative, never absolute).
   --  If Path does not start with Root, Path is returned unchanged.
   function Relative_To (Root, Path : String) return String;

   --  Splits Content into lines on LF, stripping a trailing CR from each
   --  line (so both Unix and Windows line endings work).
   function Split_Lines (Content : String) return String_List;

end Fusa.Files;
